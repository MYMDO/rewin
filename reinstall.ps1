<#
.SYNOPSIS
    Скрипт для повністю автоматичного "online" перевстановлення Windows 10 (Версія 4.1).
.DESCRIPTION
    Фінальна, найбільш надійна версія. Включає ідентпотентну логіку, автоматичне
    визначення редакції Windows та безпечну стратегію роботи з диском. Ця версія
    має підвищену стійкість до збоїв служби WMI.
.NOTES
    Автор: Ваш досвідчений системний адміністратор
    Версія: 4.1 - Resilient WMI
#>

# --- [ Глобальні налаштування та змінні ] ---
$ErrorActionPreference = "Stop"
$WorkingDir = "C:\Temp-Win-Reinstall"
$TempPartitionLetter = "W"
$TempPartitionLabel = "WinInstall"
$RequiredSpaceGB = 10

#================================================================================
# Модуль 1: Перевірка середовища та збір інформації (з підвищеною стійкістю)
#================================================================================
Write-Host "=== Модуль 1: Перевірка середовища та збір інформації ===" -ForegroundColor Yellow

# Перевірка запуску з правами Адміністратора
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Помилка: Скрипт необхідно запустити від імені Адміністратора."
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs -ErrorAction Stop; exit
}

# Збір критично важливої інформації
try {
    $script:SystemInfo = [PSCustomObject]@{
        OSArchitecture  = (Get-CimInstance Win32_OperatingSystem).OSArchitecture
        FirmwareType    = $env:firmware_type
        SystemPartition = Get-Partition -DriveLetter C
        Disk            = Get-Disk -Number (Get-Partition -DriveLetter C).DiskNumber
    }
} catch {
    Write-Error "Не вдалося зібрати критично важливу інформацію про систему (диски, прошивка). Роботу скрипта зупинено. Причина: $($_.Exception.Message)"
    Read-Host "Натисніть Enter для виходу"
    exit
}

# Збір додаткової інформації (некритичної)
try {
    # Спроба отримати редакцію Windows
    $editionInfo = Get-CimInstance -ClassName Win32_OperatingSystem | Select-Object -ExpandProperty Caption
    $script:SystemInfo | Add-Member -MemberType NoteProperty -Name "EditionID" -Value ($editionInfo -replace "Microsoft Windows 10 ", "")
} catch {
    Write-Warning "Не вдалося визначити редакцію Windows. Можливо, доведеться вибрати її вручну під час встановлення."
    $script:SystemInfo | Add-Member -MemberType NoteProperty -Name "EditionID" -Value $null
}

try {
    # Спроба отримати ключ продукту
    $productKey = (Get-WmiObject -query 'select * from SoftwareLicensingService').OA3xOriginalProductKey
    $script:SystemInfo | Add-Member -MemberType NoteProperty -Name "ProductKey" -Value $productKey
} catch {
    Write-Warning "Не вдалося отримати ключ продукту з WMI."
    $script:SystemInfo | Add-Member -MemberType NoteProperty -Name "ProductKey" -Value $null
}


# Виведення інформації та фінальне підтвердження (тільки при першому запуску)
if (-not (Get-Volume -DriveLetter $TempPartitionLetter -ErrorAction SilentlyContinue)) {
    Write-Host "`n--- Зібрана системна інформація ---" -ForegroundColor Cyan
    Write-Host "Архітектура ОС: $($SystemInfo.OSArchitecture)"
    Write-Host "Редакція Windows: $($SystemInfo.EditionID | Get-ValueOrDefault 'Не визначено')"
    Write-Host "Режим прошивки: $($SystemInfo.FirmwareType)"
    Write-Host "Тип розмітки диска: $($SystemInfo.Disk.PartitionStyle)"
    if ($SystemInfo.ProductKey) { Write-Host "Знайдений ключ продукту (OEM): $($SystemInfo.ProductKey)" }
    else { Write-Warning "Ключ продукту не знайдено."}
    Write-Host "------------------------------------`n"
    Write-Warning "УВАГА! НАСТУПНИЙ КРОК РОЗПОЧНЕ НЕЗВОРОТНІ ЗМІНИ НА ВАШОМУ ДИСКУ!"
    $Confirmation = Read-Host "Для продовження введіть слово 'ТАК' і натисніть Enter"
    if ($Confirmation -ne 'ТАК') { Write-Host "Операцію скасовано користувачем."; exit }
}

# Запит облікових даних (якщо їх ще не вводили)
if (-not $script:Credential) {
    $script:Credential = Get-Credential -UserName "Admin" -Message "Введіть логін та пароль для нового облікового запису адміністратора"
}

# Допоміжна функція для виводу
function Get-ValueOrDefault($value, $default = "N/A") { if ($value) { $value } else { $default } }


#================================================================================
# Модуль 2: Підготовка дискового простору (Ідентпотентний)
#================================================================================
Write-Host "`n=== Модуль 2: Підготовка дискового простору ===" -ForegroundColor Yellow
# ... (Цей модуль залишається без змін, він надійний)
# ... (Повний код модуля з версії 3.0/4.0)

#================================================================================
# Модуль 3: Завантаження та розгортання образу (Ідентпотентний)
#================================================================================
Write-Host "`n=== Модуль 3: Завантаження та розгортання образу Windows 10 ===" -ForegroundColor Yellow
# ... (Цей модуль залишається без змін, він надійний)
# ... (Повний код модуля з версії 3.0/4.0)


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
    
    # --- Нова логіка для визначення індексу образу ---
    $installFromBlock = ""
    if ($SystemInfo.EditionID) {
        try {
            $imagePath = if (Test-Path "${TempPartitionLetter}:\sources\install.wim") { "${TempPartitionLetter}:\sources\install.wim" } else { "${TempPartitionLetter}:\sources\install.esd" }
            $imageIndex = (Get-WindowsImage -ImagePath $imagePath | Where-Object { $_.ImageName -eq $SystemInfo.EditionID }).ImageIndex[0]
            if ($imageIndex) {
                $installFromBlock = @"
                    <InstallFrom>
                        <MetaData wcm:action="add">
                            <Key>/IMAGE/INDEX</Key>
                            <Value>$($imageIndex)</Value>
                        </MetaData>
                    </InstallFrom>
"@
            }
        } catch { Write-Warning "Не вдалося визначити індекс образу для $($SystemInfo.EditionID). Інсталятор може показати меню вибору." }
    }
    
    # --- Нова логіка для ключа продукту ---
    $productKeyBlock = ""
    if ($SystemInfo.ProductKey) {
        $productKeyBlock = "<Key>$($SystemInfo.ProductKey)</Key>"
    }

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
                        <ModifyPartition wcm:action="add">
                            <Order>1</Order>
                            <PartitionID>1</PartitionID>
                            <Format>NTFS</Format>
                        </ModifyPartition>
                        <ModifyPartition wcm:action="add">
                            <Order>2</Order>
                            <PartitionID>2</PartitionID>
                            <Format>NTFS</Format>
                        </ModifyPartition>
                    </ModifyPartitions>
                </Disk>
            </DiskConfiguration>
            <ImageInstall>
                <OSImage>
                    $($installFromBlock)
                    <InstallTo>
                        <DiskID>0</DiskID>
                        <PartitionID>2</PartitionID>
                    </InstallTo>
                </OSImage>
            </ImageInstall>
            <UserData>
                <ProductKey>
                    $($productKeyBlock)
                    <WillShowUI>OnError</WillShowUI>
                </ProductKey>
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
# Модуль 5: Модифікація завантажувача (Надійний)
#================================================================================
Write-Host "`n=== Модуль 5: Модифікація завантажувача ===" -ForegroundColor Yellow
# ... (Цей модуль залишається без змін, він надійний)
# ... (Повний код модуля з версії 3.0/4.0)

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
