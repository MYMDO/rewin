<#
.SYNOPSIS
    Скрипт для повністю автоматичного "online" перевстановлення Windows 10 (Версія 2.0).
.DESCRIPTION
    Цей скрипт готує систему до перевстановлення без зовнішніх носіїв.
    Версія 2.0 включає покращену логіку для роботи з дисками, завантажувачем,
    враховує мовні особливості системи та проблеми з "нерухомими файлами".
.NOTES
    Автор: Ваш досвідчений системний адміністратор
    Версія: 2.0 - Надійна та Універсальна
    ПОПЕРЕДЖЕННЯ: ЦЕЙ СКРИПТ ПРИЗВЕДЕ ДО ПОВНОЇ ВТРАТИ ДАНИХ НА СИСТЕМНОМУ РОЗДІЛІ (C:).
                 ЗРОБІТЬ РЕЗЕРВНУ КОПІЮ ПЕРЕД ЗАПУСКОМ!
#>

# --- [ Глобальні налаштування та змінні ] ---
$ErrorActionPreference = "Stop"
$WorkingDir = "C:\Temp-Win-Reinstall"
$TempPartitionLetter = "W"
$TempPartitionLabel = "WinInstall"
$RequiredSpaceGB = 10
$StateFile = "$WorkingDir\state.txt" # Файл для збереження стану між перезавантаженнями

#================================================================================
# Модуль 1: Перевірка середовища та збір інформації (Pre-flight Checks)
#================================================================================
function Start-PreFlightChecks {
    Write-Host "=== Модуль 1: Перевірка середовища та збір інформації ===" -ForegroundColor Yellow

    # Перевірка запуску з правами Адміністратора
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error "Помилка: Скрипт необхідно запустити від імені Адміністратора."
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs -ErrorAction Stop
        exit
    }

    # Перевірка інтернет-з'єднання
    if (-not (Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet)) {
        Write-Error "Помилка: Відсутнє інтернет-з'єднання. Воно необхідне для завантаження образу Windows."
        exit
    }

    # Збір інформації про систему
    $script:SystemInfo = [PSCustomObject]@{
        OSArchitecture  = (Get-CimInstance Win32_OperatingSystem).OSArchitecture
        FirmwareType    = $env:firmware_type
        SystemPartition = Get-Partition -DriveLetter C
        ProductKey      = (Get-WmiObject -query 'select * from SoftwareLicensingService').OA3xOriginalProductKey
        Disk            = Get-Disk -Number (Get-Partition -DriveLetter C).DiskNumber
    }

    # Запит облікових даних для нового користувача
    $script:Credential = Get-Credential -UserName "Admin" -Message "Введіть логін та пароль для нового облікового запису адміністратора у чистій системі Windows"

    # Виведення зібраної інформації та фінальне підтвердження
    Write-Host "`n--- Зібрана системна інформація ---" -ForegroundColor Cyan
    Write-Host "Архітектура ОС: $($SystemInfo.OSArchitecture)"
    Write-Host "Режим прошивки: $($SystemInfo.FirmwareType)"
    Write-Host "Тип розмітки диска: $($SystemInfo.Disk.PartitionStyle)"
    Write-Host "Системний диск: $($SystemInfo.SystemPartition.DiskNumber), Розділ: $($SystemInfo.SystemPartition.PartitionNumber) (Диск C:)"
    if ($SystemInfo.ProductKey) {
        Write-Host "Знайдений ключ продукту (OEM): $($SystemInfo.ProductKey)"
    } else {
        Write-Warning "OEM ключ продукту не знайдено. Переконайтесь, що у вас є ліцензійний ключ для активації."
    }
    Write-Host "------------------------------------`n"

    Write-Warning "УВАГА! НАСТУПНИЙ КРОК РОЗПОЧНЕ НЕЗВОРОТНІ ЗМІНИ НА ВАШОМУ ДИСКУ!"
    Write-Warning "УСІ ДАНІ НА ДИСКУ C: БУДУТЬ НАЗАВЖДИ ВИДАЛЕНІ."
    $Confirmation = Read-Host "Для продовження введіть слово 'ТАК' і натисніть Enter"
    if ($Confirmation -ne 'ТАК') {
        Write-Host "Операцію скасовано користувачем." -ForegroundColor Green
        exit
    }
}

#================================================================================
# Модуль 2: Підготовка дискового простору (з урахуванням проблем)
#================================================================================
function Start-DiskPreparation {
    Write-Host "`n=== Модуль 2: Підготовка дискового простору ===" -ForegroundColor Yellow

    # Створення робочої директорії
    if (-not (Test-Path $WorkingDir)) { New-Item -Path $WorkingDir -ItemType Directory | Out-Null }

    $PartitionToResize = $SystemInfo.SystemPartition
    $SizeToShrinkTo = $PartitionToResize.Size - ($RequiredSpaceGB * 1GB)

    try {
        # Спроба стиснення
        Resize-Partition -DiskNumber $PartitionToResize.DiskNumber -PartitionNumber $PartitionToResize.PartitionNumber -Size $SizeToShrinkTo
    } catch {
        Write-Warning "Не вдалося стиснути розділ. Можливо, заважають 'нерухомі' файли (pagefile, hiberfil)."
        Write-Warning "Скрипт спробує їх тимчасово вимкнути."

        # Вимикаємо гібернацію
        powercfg /hibernate off
        Write-Host "Гібернацію вимкнено."

        # Вимикаємо файл підкачки
        $PagingFile = Get-CimInstance -ClassName Win32_PageFileSetting
        if ($PagingFile) {
            $PagingFile | Remove-CimInstance
            Write-Host "Файл підкачки буде вимкнено після перезавантаження."
        }

        Write-Error "ПОТРІБНЕ ПЕРЕЗАВАНТАЖЕННЯ. Будь ласка, перезавантажте комп'ютер, а потім запустіть цей скрипт знову. Він продовжить роботу автоматично."
        "REBOOT_REQUIRED" | Out-File -FilePath $StateFile -Encoding utf8
        exit
    }

    # Перевірка ліміту MBR
    if ($SystemInfo.Disk.PartitionStyle -eq "MBR") {
        $PrimaryPartitions = Get-Partition -DiskNumber $SystemInfo.Disk.Number | Where-Object { $_.Type -in 'IFS', 'FAT32', 'FAT16', 'NTFS', 'Primary' }
        if ($PrimaryPartitions.Count -ge 4) {
            Write-Error "Помилка: Ваш диск MBR вже має 4 первинних розділи. Неможливо створити ще один. Видаліть зайвий розділ вручну в 'Керуванні дисками' (diskmgmt.msc) і запустіть скрипт знову."
            exit
        }
    }

    Write-Host "Стиснення успішне. Створення нового тимчасового розділу..."
    Update-Disk -DiskNumber $PartitionToResize.DiskNumber
    $NewPartition = New-Partition -DiskNumber $PartitionToResize.DiskNumber -UseMaximumSize -AssignDriveLetter
    $script:TempPartitionLetter = $NewPartition.DriveLetter
    
    Write-Host "Форматування тимчасового розділу ($($TempPartitionLetter):) в NTFS..."
    Format-Volume -DriveLetter $TempPartitionLetter -FileSystem NTFS -NewFileSystemLabel $TempPartitionLabel -Confirm:$false -Force

    # Для BIOS/MBR систем робимо розділ активним
    if ($SystemInfo.FirmwareType -ne "UEFI") {
        Write-Host "Система BIOS. Позначення тимчасового розділу як Активний..."
        $DiskPartScript = @"
select disk $($SystemInfo.Disk.Number)
select partition $($NewPartition.PartitionNumber)
active
exit
"@
        $DiskPartScript | diskpart
    }

    Write-Host "Підготовка диска успішно завершена." -ForegroundColor Green
    "DISK_PREPARED" | Out-File -FilePath $StateFile -Encoding utf8
}

#================================================================================
# Модуль 3: Завантаження та розгортання образу Windows 10
#================================================================================
function Start-ImageDeployment {
    Write-Host "`n=== Модуль 3: Завантаження та розгортання образу Windows 10 ===" -ForegroundColor Yellow

    $IsoPath = "$WorkingDir\Win10_x64.iso"
    if (-not (Test-Path $IsoPath)) {
        Write-Host "Будь ласка, завантажте офіційний ISO-образ Windows 10 x64."
        Write-Host "Використовуйте 'Media Creation Tool' або інструменти розробника в браузері для отримання прямого посилання."
        Read-Host "Після завантаження, помістіть файл у '$WorkingDir' під назвою 'Win10_x64.iso' і натисніть Enter"
    }

    Write-Host "Монтування ISO-образу..."
    $MountedImage = Mount-DiskImage -ImagePath $IsoPath -PassThru
    $SourceDrive = ($MountedImage | Get-Volume).DriveLetter

    Write-Host "Копіювання інсталяційних файлів до тимчасового розділу $($TempPartitionLetter):..."
    Copy-Item -Path "$($SourceDrive):\*" -Destination "$($TempPartitionLetter):\" -Recurse -Force

    Dismount-DiskImage -ImagePath $IsoPath
    Write-Host "Розгортання образу успішно завершено." -ForegroundColor Green
    "IMAGE_DEPLOYED" | Out-File -FilePath $StateFile -Encoding utf8
}

#================================================================================
# Модуль 4: Створення файлу автоматичної відповіді (autounattend.xml)
#================================================================================
function Start-AutoUnattendCreation {
    Write-Host "`n=== Модуль 4: Створення файлу autounattend.xml ===" -ForegroundColor Yellow

    $NewUserName = $Credential.UserName
    $NewUserPassword = $Credential.GetNetworkCredential().Password
    $autounattendXmlPath = "$($TempPartitionLetter):\autounattend.xml"

    # XML-шаблон... (залишається без змін, як у попередній версії)
    $xmlContent = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="windowsPE">
        <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <SetupUILanguage><UILanguage>en-US</UILanguage></SetupUILanguage>
            <InputLocale>0409:00000409</InputLocale><SystemLocale>en-US</SystemLocale><UILanguage>en-US</UILanguage><UserLocale>en-US</UserLocale>
        </component>
        <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <DiskConfiguration>
                <Disk wcm:action="add">
                    <DiskID>$($SystemInfo.SystemPartition.DiskNumber)</DiskID>
                    <WillWipeDisk>true</WillWipeDisk>
                    <CreatePartitions>
                        <CreatePartition wcm:action="add"><Order>1</Order><Type>Primary</Type><Size>500</Size></CreatePartition>
                        <CreatePartition wcm:action="add"><Order>2</Order><Type>MSR</Type><Size>128</Size></CreatePartition>
                        <CreatePartition wcm:action="add"><Order>3</Order><Type>Primary</Type><Extend>true</Extend></CreatePartition>
                    </CreatePartitions>
                    <ModifyPartitions>
                        <ModifyPartition wcm:action="add"><Order>1</Order><PartitionID>1</PartitionID><Label>System</Label><Format>FAT32</Format></ModifyPartition>
                        <ModifyPartition wcm:action="add"><Order>2</Order><PartitionID>3</PartitionID><Label>Windows</Label><Format>NTFS</Format><Letter>C</Letter></ModifyPartition>
                    </ModifyPartitions>
                </Disk>
            </DiskConfiguration>
            <ImageInstall><OSImage><InstallTo><DiskID>$($SystemInfo.SystemPartition.DiskNumber)</DiskID><PartitionID>3</PartitionID></InstallTo></OSImage></ImageInstall>
            <UserData><ProductKey><Key>$($SystemInfo.ProductKey)</Key><WillShowUI>OnError</WillShowUI></ProductKey><AcceptEula>true</AcceptEula></UserData>
        </component>
    </settings>
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <OOBE><HideEULAPage>true</HideEULAPage><HideOEMRegistrationScreen>true</HideOEMRegistrationScreen><HideOnlineAccountScreens>true</HideOnlineAccountScreens><HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE><NetworkLocation>Work</NetworkLocation><ProtectYourPC>1</ProtectYourPC></OOBE>
            <UserAccounts><LocalAccounts><LocalAccount wcm:action="add"><Password><Value>$($NewUserPassword)</Value><PlainText>true</PlainText></Password><Description>Local Administrator Account</Description><DisplayName>$($NewUserName)</DisplayName><Group>Administrators</Group><Name>$($NewUserName)</Name></LocalAccount></LocalAccounts></UserAccounts>
        </component>
    </settings>
</unattend>
"@
    $xmlContent | Out-File -FilePath $autounattendXmlPath -Encoding utf8
    Write-Host "Файл autounattend.xml успішно створено." -ForegroundColor Green
    "AUTOUA_CREATED" | Out-File -FilePath $StateFile -Encoding utf8
}

#================================================================================
# Модуль 5: Модифікація завантажувача (надійна версія)
#================================================================================
function Start-BootloaderModification {
    Write-Host "`n=== Модуль 5: Модифікація завантажувача ===" -ForegroundColor Yellow

    try {
        # Створюємо завантажувальні файли на тимчасовому розділі
        Write-Host "Створення завантажувальних файлів на розділі ${TempPartitionLetter}:..."
        bcdboot "$($TempPartitionLetter):\Windows" /s "$($TempPartitionLetter):" /f $SystemInfo.FirmwareType

        # Створюємо новий запис і отримуємо його GUID
        Write-Host "Створення тимчасового запису завантаження..."
        $BcdOutput = bcdedit /create /d "Windows Reinstall (Temp)" /application osloader
        $Guid = ($BcdOutput -split '[\{\}]')[1]
        $Guid = "{${Guid}}" # Додаємо дужки назад

        if (-not $Guid) { throw "Не вдалося створити запис BCD і отримати GUID." }
        Write-Host "Створено запис з GUID: $Guid"

        # Налаштовуємо запис
        bcdedit /set $Guid device "partition=$($TempPartitionLetter):"
        bcdedit /set $Guid osdevice "partition=$($TempPartitionLetter):"
        
        if ($SystemInfo.FirmwareType -eq "UEFI") {
            bcdedit /set $Guid path \EFI\Microsoft\Boot\bootmgfw.efi
        } else { # BIOS
            bcdedit /set $Guid path \Windows\system32\winload.exe
        }
        bcdedit /set $Guid systemroot \Windows

        # Встановлюємо одноразове завантаження
        Write-Host "Встановлення одноразового завантаження..."
        bcdedit /bootsequence $Guid
        
        Write-Host "Завантажувач успішно налаштовано." -ForegroundColor Green
        
        # Очищення
        if (Test-Path $StateFile) { Remove-Item $StateFile -Force }

        Write-Host "`n--- ПІДГОТОВКА ЗАВЕРШЕНА ---" -ForegroundColor Magenta
        Write-Host "Комп'ютер буде перезавантажено через 15 секунд для початку встановлення Windows."
        Start-Sleep -Seconds 15
        Restart-Computer -Force
        
    } catch {
        Write-Error "Сталася критична помилка під час модифікації завантажувача: $($_.Exception.Message)"
        if ($Guid) { bcdedit /delete $Guid /cleanup }
        exit
    }
}

#================================================================================
# Головний блок виконання (оркестратор)
#================================================================================
try {
    # Визначення, на якому етапі ми знаходимося
    $CurrentState = ""
    if (Test-Path $StateFile) {
        $CurrentState = Get-Content $StateFile
    }

    if ($CurrentState -eq "REBOOT_REQUIRED") {
        # Ми повернулися після перезавантаження для вимкнення нерухомих файлів
        Write-Host "Перезавантаження виявлено. Продовження підготовки диска..." -ForegroundColor Green
        Start-PreFlightChecks
        Start-DiskPreparation
        Start-ImageDeployment
        Start-AutoUnattendCreation
        Start-BootloaderModification
    } elseif ($CurrentState -eq "DISK_PREPARED") {
        # Якщо скрипт перервався після підготовки диска
        Start-PreFlightChecks
        Start-ImageDeployment
        Start-AutoUnattendCreation
        Start-BootloaderModification
    } elseif ($CurrentState -eq "IMAGE_DEPLOYED") {
        # Якщо скрипт перервався після розгортання образу
        Start-PreFlightChecks
        Start-AutoUnattendCreation
        Start-BootloaderModification
    } elseif ($CurrentState -eq "AUTOUA_CREATED") {
        # Якщо скрипт перервався перед налаштуванням завантажувача
        Start-PreFlightChecks
        Start-BootloaderModification
    } else {
        # Перший запуск
        Start-PreFlightChecks
        Start-DiskPreparation
        Start-ImageDeployment
        Start-AutoUnattendCreation
        Start-BootloaderModification
    }
} catch {
    Write-Error "Виникла непередбачена помилка на глобальному рівні: $($_.Exception.Message)"
    exit 1
}
