<#
.SYNOPSIS
    Скрипт для повністю автоматичного "online" перевстановлення Windows 10.
.DESCRIPTION
    Цей скрипт готує систему до перевстановлення без зовнішніх носіїв.
    Він стискає системний розділ, створює тимчасовий розділ, завантажує ISO-образ Windows 10,
    розгортає його, генерує файл автоматичної відповіді та налаштовує завантажувач для
    одноразового завантаження в середовище встановлення.
.NOTES
    Автор: Ваш досвідчений системний адміністратор
    Версія: 1.0
    ПОПЕРЕДЖЕННЯ: ЦЕЙ СКРИПТ ПРИЗВЕДЕ ДО ПОВНОЇ ВТРАТИ ДАНИХ НА СИСТЕМНОМУ РОЗДІЛІ (C:).
                 ЗРОБІТЬ РЕЗЕРВНУ КОПІЮ ПЕРЕД ЗАПУСКОМ!
#>

# --- [ Глобальні налаштування та змінні ] ---
$ErrorActionPreference = "Stop" # Зупиняти виконання при першій помилці
$WorkingDir = "C:\Temp-Win-Reinstall"
$TempPartitionLetter = "W"
$TempPartitionLabel = "WinInstall"
$RequiredSpaceGB = 10 # 8 GB для образу + 2 GB буфер
$Win10IsoUrl = "https://www.microsoft.com/software-download/windows10ISO" # Інформаційно, завантаження потребує трюку

#================================================================================
# Модуль 1: Перевірка середовища та збір інформації (Pre-flight Checks)
#================================================================================
Write-Host "=== Модуль 1: Перевірка середовища та збір інформації ===" -ForegroundColor Yellow

# Перевірка запуску з правами Адміністратора
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Помилка: Скрипт необхідно запустити від імені Адміністратора."
    # Спроба перезапустити з підвищеними правами
    try {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs -ErrorAction Stop
    } catch {
        Write-Error "Не вдалося перезапустити скрипт з правами адміністратора. Будь ласка, запустіть PowerShell від імені адміністратора вручну."
    }
    exit
}

# Перевірка інтернет-з'єднання
if (-not (Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet)) {
    Write-Error "Помилка: Відсутнє інтернет-з'єднання. Воно необхідне для завантаження образу Windows."
    exit
}

# Збір інформації про систему
$SystemInfo = [PSCustomObject]@{
    OSArchitecture  = (Get-CimInstance Win32_OperatingSystem).OSArchitecture
    FirmwareType    = $env:firmware_type
    SystemPartition = Get-Partition -DriveLetter C
    ProductKey      = (Get-WmiObject -query 'select * from SoftwareLicensingService').OA3xOriginalProductKey
}

# Перевірка архітектури (скрипт оптимізовано для x64)
if ($SystemInfo.OSArchitecture -ne "64-bit") {
    Write-Warning "Увага: Цей скрипт оптимізовано для 64-бітної версії Windows. Робота на 32-бітній системі не гарантується."
}

# Запит облікових даних для нового користувача
$Credential = Get-Credential -UserName "Admin" -Message "Введіть логін та пароль для нового облікового запису адміністратора у чистій системі Windows"
$NewUserName = $Credential.UserName
$NewUserPassword = $Credential.GetNetworkCredential().Password

# Виведення зібраної інформації та фінальне підтвердження
Write-Host "`n--- Зібрана системна інформація ---" -ForegroundColor Cyan
Write-Host "Архітектура ОС: $($SystemInfo.OSArchitecture)"
Write-Host "Режим прошивки: $($SystemInfo.FirmwareType)"
Write-Host "Системний диск: $($SystemInfo.SystemPartition.DiskNumber), Розділ: $($SystemInfo.SystemPartition.PartitionNumber) (Диск C:)"
Write-Host "Поточний розмір розділу C:: $([math]::Round($SystemInfo.SystemPartition.Size / 1GB, 2)) GB"
if ($SystemInfo.ProductKey) {
    Write-Host "Знайдений ключ продукту (OEM): $($SystemInfo.ProductKey)"
} else {
    Write-Warning "OEM ключ продукту не знайдено. Переконайтесь, що у вас є ліцензійний ключ для активації."
}
Write-Host "------------------------------------`n"

Write-Warning "УВАГА! НАСТУПНИЙ КРОК РОЗПОЧНЕ НЕЗВОРОТНІ ЗМІНИ НА ВАШОМУ ДИСКУ!"
Write-Warning "УСІ ДАНІ НА ДИСКУ C: БУДУТЬ НАЗАВЖДИ ВИДАЛЕНІ."
Write-Warning "Переконайтесь, що ви зробили резервну копію всіх важливих файлів."

$Confirmation = Read-Host "Для продовження введіть слово 'ТАК' і натисніть Enter"
if ($Confirmation -ne 'ТАК') {
    Write-Host "Операцію скасовано користувачем." -ForegroundColor Green
    exit
}

#================================================================================
# Модуль 2: Підготовка дискового простору
#================================================================================
#Write-Host "`n=== Модуль 2: Підготовка дискового простору ===" -ForegroundColor Yellow

#try {
    # Створення робочої директорії
#    if (-not (Test-Path $WorkingDir)) {
#        New-Item -Path $WorkingDir -ItemType Directory | Out-Null
#        Write-Host "Створено робочу директорію: $WorkingDir"
#    }

    # Розрахунок нового розміру для розділу C:
#    $PartitionToResize = $SystemInfo.SystemPartition
#    $CurrentSize = $PartitionToResize.Size
#    $SizeToShrinkTo = $CurrentSize - ($RequiredSpaceGB * 1GB)

#    if ($SizeToShrinkTo -lt ($PartitionToResize.Size - $PartitionToResize.FreeSpace) ) {
#        Write-Error "Недостатньо вільного місця на диску C: для створення тимчасового розділу розміром $RequiredSpaceGB GB."
#        exit
#    }

#    Write-Host "Стиснення розділу C: для вивільнення $($RequiredSpaceGB) GB..."
   # Resize-Partition -DiskNumber $PartitionToResize.DiskNumber -PartitionNumber $PartitionToResize.PartitionNumber -Size $SizeToShrinkTo
    
    # Невелика пауза для стабілізації системи після зміни розміру
#    Start-Sleep -Seconds 5
#    Update-Disk -DiskNumber $PartitionToResize.DiskNumber
#
#    Write-Host "Створення нового тимчасового розділу..."
#    $NewPartition = New-Partition -DiskNumber $PartitionToResize.DiskNumber -UseMaximumSize -AssignDriveLetter
#    $TempPartitionLetter = $NewPartition.DriveLetter # Оновлюємо літеру, якщо W зайнята
#    
#    Write-Host "Форматування тимчасового розділу ($($TempPartitionLetter):) в NTFS..."
#    Format-Volume -DriveLetter $TempPartitionLetter -FileSystem NTFS -NewFileSystemLabel $TempPartitionLabel -Confirm:$false -Force
#
#    Write-Host "Підготовка диска успішно завершена. Тимчасовий розділ створено: $($TempPartitionLetter):" -ForegroundColor Green
#} catch {
#    Write-Error "Сталася помилка під час роботи з диском: $($_.Exception.Message)"
#    Write-Error "Настійно рекомендується перезавантажити комп'ютер та перевірити стан дисків у 'Керуванні дисками' (diskmgmt.msc)."
#    exit
#}

#================================================================================
# Модуль 3: Завантаження та розгортання образу Windows 10
#================================================================================
Write-Host "`n=== Модуль 3: Завантаження та розгортання образу Windows 10 ===" -ForegroundColor Yellow

$IsoPath = "$WorkingDir\Win10_x64.iso"

# Примітка: Пряме завантаження ISO з серверів MS складне.
# Цей блок демонструє, як це можна зробити, але найнадійніше - завантажити ISO вручну.
Write-Host "Будь ласка, завантажте офіційний ISO-образ Windows 10 x64."
Write-Host "Ви можете використати 'Media Creation Tool' або перейти за посиланням:"
Write-Host $Win10IsoUrl
Write-Host "(у браузері відкрийте інструменти розробника (F12) та змініть User-Agent на мобільний пристрій, щоб отримати пряме посилання на ISO)."
Read-Host "Після завантаження, помістіть файл у '$WorkingDir' під назвою 'Win10_x64.iso' і натисніть Enter для продовження"

if (-not (Test-Path $IsoPath)) {
    Write-Error "Файл $IsoPath не знайдено. Завантажте образ та розмістіть його у вказаній директорії."
    exit
}

try {
    Write-Host "Монтування ISO-образу..."
    $MountedImage = Mount-DiskImage -ImagePath $IsoPath -PassThru
    $SourceDrive = ($MountedImage | Get-Volume).DriveLetter

    Write-Host "Образ змонтовано як диск $($SourceDrive):"
    Write-Host "Копіювання інсталяційних файлів до тимчасового розділу $($TempPartitionLetter):... (це може зайняти деякий час)"
    Copy-Item -Path "$($SourceDrive):\*" -Destination "$($TempPartitionLetter):\" -Recurse -Force

    Write-Host "Копіювання завершено. Демонтування образу..."
    Dismount-DiskImage -ImagePath $IsoPath

    Write-Host "Розгортання образу успішно завершено." -ForegroundColor Green
} catch {
    Write-Error "Сталася помилка під час роботи з ISO-образом: $($_.Exception.Message)"
    # Спроба очищення
    if (Get-DiskImage -ImagePath $IsoPath) { Dismount-DiskImage -ImagePath $IsoPath }
    exit
}

#================================================================================
# Модуль 4: Створення файлу автоматичної відповіді (autounattend.xml)
#================================================================================
Write-Host "`n=== Модуль 4: Створення файлу autounattend.xml ===" -ForegroundColor Yellow

# Отримання поточних мовних налаштувань
$CurrentCulture = Get-Culture
$InputLocale = Get-WinUserLanguageList | Select-Object -First 1
$UILanguage = $CurrentCulture.Name
$SystemLocale = $CurrentCulture.Name
$UserLocale = $CurrentCulture.Name
$InputLocaleString = $InputLocale.LanguageTag

$autounattendXmlPath = "$($TempPartitionLetter):\autounattend.xml"

# XML-шаблон файлу відповідей.
# УВАГА: Пароль користувача зберігається у відкритому вигляді, це вимога формату.
$xmlContent = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="windowsPE">
        <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <SetupUILanguage>
                <UILanguage>$($UILanguage)</UILanguage>
            </SetupUILanguage>
            <InputLocale>$($InputLocaleString)</InputLocale>
            <SystemLocale>$($SystemLocale)</SystemLocale>
            <UILanguage>$($UILanguage)</UILanguage>
            <UserLocale>$($UserLocale)</UserLocale>
        </component>
        <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <DiskConfiguration>
                <Disk wcm:action="add">
                    <DiskID>$($SystemInfo.SystemPartition.DiskNumber)</DiskID>
                    <WillWipeDisk>true</WillWipeDisk>
                    <CreatePartitions>
                        <!-- System Partition (ESP for UEFI or System Reserved for BIOS) -->
                        <CreatePartition wcm:action="add">
                            <Order>1</Order>
                            <Type>Primary</Type>
                            <Size>500</Size> <!-- Розмір системного розділу в MB -->
                        </CreatePartition>
                        <!-- MSR Partition (for GPT disks) -->
                        <CreatePartition wcm:action="add">
                            <Order>2</Order>
                            <Type>MSR</Type>
                            <Size>128</Size>
                        </CreatePartition>
                        <!-- Windows Partition -->
                        <CreatePartition wcm:action="add">
                            <Order>3</Order>
                            <Type>Primary</Type>
                            <Extend>true</Extend> <!-- Використати решту місця -->
                        </CreatePartition>
                    </CreatePartitions>
                    <ModifyPartitions>
                        <!-- Format System Partition -->
                        <ModifyPartition wcm:action="add">
                            <Order>1</Order>
                            <PartitionID>1</PartitionID>
                            <Label>System</Label>
                            <Format>FAT32</Format> <!-- FAT32 для UEFI, NTFS для BIOS -->
                        </ModifyPartition>
                        <!-- Format Windows Partition -->
                        <ModifyPartition wcm:action="add">
                            <Order>2</Order>
                            <PartitionID>3</PartitionID>
                            <Label>Windows</Label>
                            <Format>NTFS</Format>
                            <Letter>C</Letter>
                        </ModifyPartition>
                    </ModifyPartitions>
                </Disk>
            </DiskConfiguration>
            <ImageInstall>
                <OSImage>
                    <InstallTo>
                        <DiskID>$($SystemInfo.SystemPartition.DiskNumber)</DiskID>
                        <PartitionID>3</PartitionID>
                    </InstallTo>
                </OSImage>
            </ImageInstall>
            <UserData>
                <ProductKey>
                    <Key>$($SystemInfo.ProductKey)</Key>
                    <WillShowUI>OnError</WillShowUI>
                </ProductKey>
                <AcceptEula>true</AcceptEula>
            </UserData>
        </component>
    </settings>
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
                <NetworkLocation>Work</NetworkLocation>
                <ProtectYourPC>1</ProtectYourPC>
            </OOBE>
            <UserAccounts>
                <LocalAccounts>
                    <LocalAccount wcm:action="add">
                        <Password>
                            <Value>$($NewUserPassword)</Value>
                            <PlainText>true</PlainText>
                        </Password>
                        <Description>Local Administrator Account</Description>
                        <DisplayName>$($NewUserName)</DisplayName>
                        <Group>Administrators</Group>
                        <Name>$($NewUserName)</Name>
                    </LocalAccount>
                </LocalAccounts>
            </UserAccounts>
        </component>
    </settings>
</unattend>
"@

# Зберігаємо XML-файл
$xmlContent | Out-File -FilePath $autounattendXmlPath -Encoding utf8
Write-Host "Файл autounattend.xml успішно створено." -ForegroundColor Green

#================================================================================
# Модуль 5: Модифікація завантажувача та перезавантаження
#================================================================================
Write-Host "`n=== Модуль 5: Модифікація завантажувача ===" -ForegroundColor Yellow

try {
    Write-Host "Створення тимчасового запису завантаження..."
    # Копіюємо поточний запис завантаження, щоб отримати новий GUID
    $BcdOutput = bcdedit /copy {current} /d "Windows Setup (Temp)"
    $Guid = ($BcdOutput -split ' ')[-1].TrimEnd('}')
    
    if ($SystemInfo.FirmwareType -eq "UEFI") {
        Write-Host "Система UEFI. Налаштування завантажувача..."
        bcdedit /set $Guid device "partition=$($TempPartitionLetter):"
        bcdedit /set $Guid osdevice "partition=$($TempPartitionLetter):"
        bcdedit /set $Guid path \EFI\Microsoft\Boot\bootmgfw.efi
    } else { # BIOS
        Write-Host "Система BIOS/Legacy. Налаштування завантажувача..."
        # Створюємо завантажувальні файли на тимчасовому розділі
        bcdboot "$($TempPartitionLetter):\Windows" /s "$($TempPartitionLetter):" /f BIOS
        bcdedit /set $Guid device "partition=$($TempPartitionLetter):"
        bcdedit /set $Guid osdevice "partition=$($TempPartitionLetter):"
        bcdedit /set $Guid path \Windows\system32\winload.exe
    }
    
    Write-Host "Встановлення одноразового завантаження з тимчасового розділу..."
    bcdedit /bootsequence $Guid
    
    Write-Host "Завантажувач успішно налаштовано." -ForegroundColor Green
    
    Write-Host "`n--- ПІДГОТОВКА ЗАВЕРШЕНА ---" -ForegroundColor Magenta
    Write-Host "Комп'ютер буде перезавантажено через 15 секунд для початку встановлення Windows."
    Write-Host "Процес встановлення буде повністю автоматичним. Не натискайте жодних клавіш."
    Start-Sleep -Seconds 15
    
    Restart-Computer -Force
    
} catch {
    Write-Error "Сталася критична помилка під час модифікації завантажувача: $($_.Exception.Message)"
    Write-Error "НЕ ПЕРЕЗАВАНТАЖУЙТЕ КОМП'ЮТЕР! Спробуйте виправити BCD вручну або зверніться до спеціаліста."
    # Спроба видалити невдалий запис
    if ($Guid) { bcdedit /delete $Guid /cleanup }
    exit
}
