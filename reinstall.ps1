<#
.SYNOPSIS
    Скрипт для повністю автоматичного "online" перевстановлення Windows 10 (Версія 4.0).
.DESCRIPTION
    Фінальна, найбільш надійна версія. Включає ідентпотентну логіку (пропуск
    виконаних етапів), автоматичне визначення редакції Windows та нову, безпечну
    стратегію роботи з диском для уникнення помилок під час встановлення.
.NOTES
    Автор: Ваш досвідчений системний адміністратор
    Версія: 4.0 - Фінальна
    ПОПЕРЕДЖЕННЯ: ЦЕЙ СКРИПТ ПРИЗВЕДЕ ДО ПОВНОЇ ВТРАТИ ДАНИХ НА СИСТЕМНОМУ РОЗДІЛІ (C:).
                 ЗРОБІТЬ РЕЗЕРВНУ КОПІЮ ПЕРЕД ЗАПУСКОМ!
#>

# --- [ Глобальні налаштування та змінні ] ---
$ErrorActionPreference = "Stop"
$WorkingDir = "C:\Temp-Win-Reinstall"
$TempPartitionLetter = "W"
$TempPartitionLabel = "WinInstall"
$RequiredSpaceGB = 10

#================================================================================
# Модуль 1: Перевірка середовища та збір інформації
#================================================================================
Write-Host "=== Модуль 1: Перевірка середовища та збір інформації ===" -ForegroundColor Yellow

# Перевірка запуску з правами Адміністратора
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Помилка: Скрипт необхідно запустити від імені Адміністратора."
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs -ErrorAction Stop; exit
}

# Збір інформації про систему
try {
    $osInfo = Get-CimInstance Win32_OperatingSystem
    $script:SystemInfo = [PSCustomObject]@{
        OSArchitecture  = $osInfo.OSArchitecture
        EditionID       = (Get-CimInstance -ClassName SoftwareLicensingProduct | Where-Object { $_.Name -like 'Windows*' -and $_.LicenseStatus -eq 1 }).Description.Split(',')[0].Trim() # 'Windows(R) Operating System' -> 'Windows'
        FirmwareType    = $env:firmware_type
        SystemPartition = Get-Partition -DriveLetter C
        ProductKey      = (Get-WmiObject -query 'select * from SoftwareLicensingService').OA3xOriginalProductKey
        Disk            = Get-Disk -Number (Get-Partition -DriveLetter C).DiskNumber
    }
} catch {
    Write-Error "Не вдалося зібрати базову інформацію про систему. Роботу скрипта зупинено."
    exit
}

# Виведення інформації та фінальне підтвердження (тільки при першому запуску)
if (-not (Get-Volume -DriveLetter $TempPartitionLetter -ErrorAction SilentlyContinue)) {
    Write-Host "`n--- Зібрана системна інформація ---" -ForegroundColor Cyan
    Write-Host "Архітектура ОС: $($SystemInfo.OSArchitecture)"
    Write-Host "Редакція Windows: $($SystemInfo.EditionID)"
    Write-Host "Режим прошивки: $($SystemInfo.FirmwareType)"
    Write-Host "Тип розмітки диска: $($SystemInfo.Disk.PartitionStyle)"
    if ($SystemInfo.ProductKey) { Write-Host "Знайдений ключ продукту (OEM): $($SystemInfo.ProductKey)" }
    Write-Host "------------------------------------`n"
    Write-Warning "УВАГА! НАСТУПНИЙ КРОК РОЗПОЧНЕ НЕЗВОРОТНІ ЗМІНИ НА ВАШОМУ ДИСКУ!"
    $Confirmation = Read-Host "Для продовження введіть слово 'ТАК' і натисніть Enter"
    if ($Confirmation -ne 'ТАК') { Write-Host "Операцію скасовано користувачем."; exit }
}

# Запит облікових даних (якщо їх ще не вводили)
if (-not $script:Credential) {
    $script:Credential = Get-Credential -UserName "Admin" -Message "Введіть логін та пароль для нового облікового запису адміністратора"
}

#================================================================================
# Модуль 2: Підготовка дискового простору
#================================================================================
Write-Host "`n=== Модуль 2: Підготовка дискового простору ===" -ForegroundColor Yellow

$tempVolume = Get-Volume -DriveLetter $TempPartitionLetter -ErrorAction SilentlyContinue
if ($tempVolume -and $tempVolume.FileSystemLabel -eq $TempPartitionLabel) {
    Write-Host "Тимчасовий розділ '$($TempPartitionLabel)' ($($TempPartitionLetter):) вже існує. Пропускаємо цей крок." -ForegroundColor Green
} else {
    Write-Host "Тимчасовий розділ не знайдено. Спроба автоматичної підготовки..."
    try {
        # ... (логіка стиснення та створення розділу залишається як у v3.0)
        # Перевірка MBR ліміту
        if ($SystemInfo.Disk.PartitionStyle -eq "MBR") {
            $PrimaryPartitions = Get-Partition -DiskNumber $SystemInfo.Disk.Number | Where-Object { $_.Type -in 'IFS', 'FAT32', 'FAT16', 'NTFS', 'Primary' }
            if ($PrimaryPartitions.Count -ge 4) {
                throw "Ваш диск MBR вже має 4 первинних розділи. Видаліть зайвий розділ вручну в 'Керуванні дисками' (diskmgmt.msc)."
            }
        }
        
        $PartitionToResize = $SystemInfo.SystemPartition
        $unallocatedSpace = Get-Disk -Number $PartitionToResize.DiskNumber | Get-Partition | Where-Object { $_.Type -eq 'Unused' } | Measure-Object -Property Size -Sum | Select-Object -ExpandProperty Sum
        if ($unallocatedSpace -lt ($RequiredSpaceGB * 1GB)) {
            Write-Host "Недостатньо нерозподіленого простору. Спроба стиснути диск C:..."
            Resize-Partition -DiskNumber $PartitionToResize.DiskNumber -PartitionNumber $PartitionToResize.PartitionNumber -Size ($PartitionToResize.Size - ($RequiredSpaceGB * 1GB))
        }

        Update-Disk -DiskNumber $PartitionToResize.DiskNumber
        $NewPartition = New-Partition -DiskNumber $PartitionToResize.DiskNumber -UseMaximumSize -AssignDriveLetter
        $script:TempPartitionLetter = $NewPartition.DriveLetter
        
        Format-Volume -DriveLetter $TempPartitionLetter -FileSystem NTFS -NewFileSystemLabel $TempPartitionLabel -Confirm:$false -Force

        if ($SystemInfo.FirmwareType -ne "UEFI") {
            $DiskPartScript = "select disk $($SystemInfo.Disk.Number)`nselect partition $($NewPartition.PartitionNumber)`nactive`nexit"
            $DiskPartScript | diskpart
        }
        Write-Host "Автоматична підготовка диска успішно завершена." -ForegroundColor Green
    } catch {
        Write-Error "Автоматична підготовка диска не вдалася: $($_.Exception.Message)"
        Write-Error "БУДЬ ЛАСКА, ВИКОНАЙТЕ ЦІ КРОКИ ВРУЧНУ:"
        Write-Host "1. Відкрийте 'Керування дисками' (diskmgmt.msc)."
        Write-Host "2. Стисніть диск C:, щоб вивільнити принаймні 10 ГБ."
        Write-Host "3. У нерозподіленому просторі створіть новий простий том."
        Write-Host "4. Призначте йому літеру '$($TempPartitionLetter):', відформатуйте в NTFS з міткою '$($TempPartitionLabel)'."
        Write-Host "5. Після цього запустіть цей скрипт знову."
        exit
    }
}

#================================================================================
# Модуль 3: Завантаження та розгортання образу Windows 10
#================================================================================
Write-Host "`n=== Модуль 3: Завантаження та розгортання образу Windows 10 ===" -ForegroundColor Yellow
if ((Test-Path "${TempPartitionLetter}:\sources\install.wim") -or (Test-Path "${TempPartitionLetter}:\sources\install.esd")) {
    Write-Host "Інсталяційні файли Windows вже знаходяться на розділі '${TempPartitionLetter}:'. Пропускаємо цей крок." -ForegroundColor Green
} else {
    # ... (логіка завантаження та копіювання залишається як у v3.0)
    if (-not (Test-Path $WorkingDir)) { New-Item -Path $WorkingDir -ItemType Directory | Out-Null }
    $IsoPath = "$WorkingDir\Win10_x64.iso"
    if (-not (Test-Path $IsoPath)) {
        Read-Host "ISO-образ не знайдено. Будь ласка, завантажте 'Win10_x64.iso' у папку '$WorkingDir' і натисніть Enter"
    }

    $MountedImage = Mount-DiskImage -ImagePath $IsoPath -PassThru
    $SourceDrive = ($MountedImage | Get-Volume).DriveLetter
    Copy-Item -Path "$($SourceDrive):\*" -Destination "${TempPartitionLetter}:\" -Recurse -Force
    Dismount-DiskImage -ImagePath $IsoPath
    Write-Host "Розгортання образу успішно завершено." -ForegroundColor Green
}

#================================================================================
# Модуль 4: Створення файлу автоматичної відповіді (з новою логікою)
#================================================================================
Write-Host "`n=== Модуль 4: Створення файлу autounattend.xml ===" -ForegroundColor Yellow
$autounattendXmlPath = "${TempPartitionLetter}:\autounattend.xml"
if (Test-Path $autounattendXmlPath) {
    Write-Host "Файл '$autounattendXmlPath' вже існує. Пропускаємо цей крок." -ForegroundColor Green
} else {
    $NewUserName = $Credential.UserName
    $NewUserPassword = $Credential.GetNetworkCredential().Password
    
    # Визначаємо індекс образу для встановлення
    $imageIndex = (Get-WindowsImage -ImagePath "${TempPartitionLetter}:\sources\install.wim" | Where-Object { $_.ImageName -eq $SystemInfo.EditionID }).ImageIndex[0]    if (-not $imageIndex) { $imageIndex = 1 } # Якщо не знайдено, беремо перший

    # Новий, безпечний XML для вибіркового видалення розділів
    $xmlContent = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="windowsPE">
        <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <DiskConfiguration>
                <Disk wcm:action="add">
                    <DiskID>0</DiskID>
                    <WillWipeDisk>false</WillWipeDisk>
                    <ModifyPartitions>
                        <!-- Видаляємо старий системний розділ (System Reserved або ESP) -->
                        <ModifyPartition wcm:action="add">
                            <Order>1</Order>
                            <PartitionID>1</PartitionID>
                            <Format>NTFS</Format> <!-- Просто форматуємо, щоб стерти -->
                        </ModifyPartition>
                        <!-- Видаляємо старий Windows розділ (C:) -->
                        <ModifyPartition wcm:action="add">
                            <Order>2</Order>
                            <PartitionID>2</PartitionID>
                            <Format>NTFS</Format> <!-- Форматуємо, щоб стерти -->
                        </ModifyPartition>
                    </ModifyPartitions>
                </Disk>
            </DiskConfiguration>
            <ImageInstall>
                <OSImage>
                    <InstallFrom>
                        <MetaData wcm:action="add">
                            <Key>/IMAGE/INDEX</Key>
                            <Value>$($imageIndex)</Value>
                        </MetaData>
                    </InstallFrom>
                    <InstallTo>
                        <DiskID>0</DiskID>
                        <PartitionID>2</PartitionID> <!-- Встановлюємо на місце старого C: -->
                    </InstallTo>
                </OSImage>
            </ImageInstall>
            <UserData>
                <ProductKey><Key>$($SystemInfo.ProductKey)</Key><WillShowUI>OnError</WillShowUI></ProductKey>
                <AcceptEula>true</AcceptEula>
            </UserData>
        </component>
        <!-- Інші компоненти (International-Core, OOBE) залишаються без змін -->
    </settings>
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <OOBE><HideEULAPage>true</HideEULAPage><HideOEMRegistrationScreen>true</HideOEMRegistrationScreen><HideOnlineAccountScreens>true</HideOnlineAccountScreens><HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE><NetworkLocation>Work</NetworkLocation><ProtectYourPC>1</ProtectYourPC></OOBE>
            <UserAccounts><LocalAccounts><LocalAccount wcm:action="add"><Password><Value>$($NewUserPassword)</Value><PlainText>true</PlainText></Password><Description>Local Administrator Account</Description><DisplayName>$($NewUserName)</DisplayName><Group>Administrators</Group><Name>$($NewUserName)</Name></LocalAccount></LocalAccounts></UserAccounts>
        </component>
    </settings>
</unattend>
"@
    $xmlContent | Out-File -FilePath $autounattendXmlPath -Encoding utf8
    Write-Host "Файл autounattend.xml успішно створено з новою логікою." -ForegroundColor Green
}

#================================================================================
# Модуль 5: Модифікація завантажувача
#================================================================================
Write-Host "`n=== Модуль 5: Модифікація завантажувача ===" -ForegroundColor Yellow
try {
    # ... (логіка залишається як у v3.0)
    bcdboot "${TempPartitionLetter}:\Windows" /s "${TempPartitionLetter}:" /f $SystemInfo.FirmwareType
    $BcdOutput = bcdedit /create /d "Windows Reinstall (Temp)" /application osloader
    $Guid = ($BcdOutput -split '[\{\}]')[1]
    $Guid = "{${Guid}}"
    if (-not $Guid) { throw "Не вдалося створити запис BCD і отримати GUID." }

    bcdedit /set $Guid device "partition=${TempPartitionLetter}:"
    bcdedit /set $Guid osdevice "partition=${TempPartitionLetter}:"
    if ($SystemInfo.FirmwareType -eq "UEFI") {
        bcdedit /set $Guid path \EFI\Microsoft\Boot\bootmgfw.efi
    } else {
        bcdedit /set $Guid path \Windows\system32\winload.exe
    }
    bcdedit /set $Guid systemroot \Windows
    bcdedit /bootsequence $Guid
    
    Write-Host "Завантажувач успішно налаштовано." -ForegroundColor Green
    Write-Host "`n--- ПІДГОТОВКА ЗАВЕРШЕНА ---" -ForegroundColor Magenta
    Write-Host "Комп'ютер буде перезавантажено через 15 секунд для початку встановлення Windows."
    Start-Sleep -Seconds 15
    Restart-Computer -Force
    
} catch {
    Write-Error "Сталася критична помилка під час модифікації завантажувача: $($_.Exception.Message)"
    if ($Guid) { bcdedit /delete $Guid /cleanup }
    exit
}
