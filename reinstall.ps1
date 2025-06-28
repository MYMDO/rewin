<#
.SYNOPSIS
    Універсальний скрипт для автоматичного "online" перевстановлення Windows 10 (Версія 5.0).
.DESCRIPTION
    Ця фінальна версія є кульмінацією всіх попередніх ітерацій. Вона намагається
    автоматизувати всі можливі кроки, але має надійні механізми обробки помилок
    і може бути запущена повторно для продовження роботи після ручного втручання.
    Вона розроблена для максимальної універсальності та надійності.
.NOTES
    Автор: Ваш досвідчений системний адміністратор
    Версія: 5.0 - The Professional's Choice
#>

# --- [ Глобальні налаштування та змінні ] ---
$ErrorActionPreference = "Stop"
$WorkingDir = "C:\Temp-Win-Reinstall"
$TempPartitionLetter = "W"
$TempPartitionLabel = "WinInstall"
$RequiredSpaceGB = 12 # Збільшено для буфера та файлів завантаження

# --- [ Допоміжні функції ] ---
# Визначення функції на початку для гарантованої доступності в усьому скрипті
function Get-ValueOrDefault($value, $default = "N/A") {
    if ($value -and (-not [string]::IsNullOrWhiteSpace($value))) {
        return $value
    } else {
        return $default
    }
}

# --- [ Основний блок виконання ] ---
try {
    #================================================================================
    # Модуль 1: Перевірка середовища та збір інформації
    #================================================================================
    Write-Host "=== Модуль 1: Перевірка середовища та збір інформації ===" -ForegroundColor Yellow

    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error "Помилка: Скрипт необхідно запустити від імені Адміністратора."
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs -ErrorAction Stop; exit
    }

    try {
        $script:SystemInfo = [PSCustomObject]@{
            OSArchitecture  = (Get-CimInstance Win32_OperatingSystem).OSArchitecture
            FirmwareType    = $env:firmware_type
            SystemPartition = Get-Partition -DriveLetter C
            Disk            = Get-Disk -Number (Get-Partition -DriveLetter C).DiskNumber
        }
    } catch {
        throw "Не вдалося зібрати критично важливу інформацію про систему (диски, прошивка). Роботу скрипта зупинено. Причина: $($_.Exception.Message)"
    }

    try {
        $editionInfo = (Get-CimInstance -ClassName Win32_OperatingSystem).Caption
        $script:SystemInfo | Add-Member -MemberType NoteProperty -Name "EditionID" -Value ($editionInfo -replace "Microsoft Windows 10 ", "")
    } catch {
        $script:SystemInfo | Add-Member -MemberType NoteProperty -Name "EditionID" -Value $null
    }

    try {
        $productKey = (Get-WmiObject -query 'select * from SoftwareLicensingService').OA3xOriginalProductKey
        $script:SystemInfo | Add-Member -MemberType NoteProperty -Name "ProductKey" -Value $productKey
    } catch {
        $script:SystemInfo | Add-Member -MemberType NoteProperty -Name "ProductKey" -Value $null
    }

    if (-not (Get-Volume -DriveLetter $TempPartitionLetter -ErrorAction SilentlyContinue)) {
        Write-Host "`n--- Зібрана системна інформація ---" -ForegroundColor Cyan
        Write-Host "Архітектура ОС: $($SystemInfo.OSArchitecture)"
        Write-Host "Редакція Windows: $(Get-ValueOrDefault $SystemInfo.EditionID 'Не визначено')"
        Write-Host "Режим прошивки: $($SystemInfo.FirmwareType)"
        Write-Host "Тип розмітки диска: $($SystemInfo.Disk.PartitionStyle)"
        if ($SystemInfo.ProductKey) { Write-Host "Знайдений ключ продукту (OEM): $($SystemInfo.ProductKey)" }
        else { Write-Warning "Ключ продукту не знайдено."}
        Write-Host "------------------------------------`n"
        Write-Warning "УВАГА! НАСТУПНИЙ КРОК РОЗПОЧНЕ НЕЗВОРОТНІ ЗМІНИ НА ВАШОМУ ДИСКУ!"
        $Confirmation = Read-Host "Для продовження введіть слово 'ТАК' і натисніть Enter"
        if ($Confirmation -ne 'ТАК') { Write-Host "Операцію скасовано користувачем."; exit }
    }

    if (-not $script:Credential) {
        $script:Credential = Get-Credential -UserName "Admin" -Message "Введіть логін та пароль для нового облікового запису адміністратора"
    }

    #================================================================================
    # Модуль 2: Підготовка дискового простору
    #================================================================================
    Write-Host "`n=== Модуль 2: Підготовка дискового простору ===" -ForegroundColor Yellow
    $tempVolume = Get-Volume -DriveLetter $TempPartitionLetter -ErrorAction SilentlyContinue
    if ($tempVolume -and $tempVolume.FileSystemLabel -eq $TempPartitionLabel) {
        Write-Host "Тимчасовий розділ '$($TempPartitionLabel)' ($($TempPartitionLetter):) вже існує. Пропускаємо." -ForegroundColor Green
    } else {
        Write-Host "Тимчасовий розділ не знайдено. Спроба автоматичної підготовки..."
        try {
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
            
            Format-Volume -DriveLetter $script:TempPartitionLetter -FileSystem NTFS -NewFileSystemLabel $TempPartitionLabel -Confirm:$false -Force

            if ($SystemInfo.FirmwareType -ne "UEFI") {
                $DiskPartScript = "select disk $($SystemInfo.Disk.Number)`nselect partition $($NewPartition.PartitionNumber)`nactive`nexit"
                $DiskPartScript | diskpart
            }
            Write-Host "Автоматична підготовка диска успішно завершена." -ForegroundColor Green
        } catch {
            Write-Error "Автоматична підготовка диска не вдалася: $($_.Exception.Message)"
            Write-Error "БУДЬ ЛАСКА, ВИКОНАЙТЕ ЦІ КРОКИ ВРУЧНУ:"
            Write-Host "1. Відкрийте 'Керування дисками' (diskmgmt.msc)."
            Write-Host "2. Стисніть диск C:, щоб вивільнити принаймні $($RequiredSpaceGB) ГБ."
            Write-Host "3. У нерозподіленому просторі створіть новий простий том."
            Write-Host "4. Призначте йому літеру '$($TempPartitionLetter):', відформатуйте в NTFS з міткою '$($TempPartitionLabel)'."
            Write-Host "5. Після цього запустіть цей скрипт знову."
            exit
        }
    }

    #================================================================================
    # Модуль 3: Завантаження та розгортання образу
    #================================================================================
    Write-Host "`n=== Модуль 3: Завантаження та розгортання образу ===" -ForegroundColor Yellow
    $isoPath = Join-Path $WorkingDir "Win10_x64.iso"
    if ((Test-Path "${TempPartitionLetter}:\sources\install.wim") -or (Test-Path "${TempPartitionLetter}:\sources\install.esd")) {
        Write-Host "Інсталяційні файли вже розгорнуто. Пропускаємо." -ForegroundColor Green
    } else {
        if (-not (Test-Path $WorkingDir)) { New-Item -Path $WorkingDir -ItemType Directory | Out-Null }
        if (-not (Test-Path $isoPath)) {
            Write-Warning "ISO-образ не знайдено."
            Write-Host "Для повної автоматизації потрібен офіційний ISO-образ Windows 10."
            Write-Host "Найпростіший спосіб його отримати - використати 'Media Creation Tool' від Microsoft."
            Write-Error "БУДЬ ЛАСКА, ЗАВАНТАЖТЕ ISO-ОБРАЗ ВРУЧНУ."
            Read-Host "Помістіть файл 'Win10_x64.iso' у папку '$WorkingDir' і натисніть Enter, щоб продовжити."
            if (-not (Test-Path $isoPath)) { throw "Файл ISO так і не було знайдено. Зупинка." }
        }
        
        Write-Host "Монтування ISO-образу..."
        $mountedImage = Mount-DiskImage -ImagePath $isoPath -PassThru
        $sourceDrive = ($mountedImage | Get-Volume).DriveLetter
        Write-Host "Копіювання інсталяційних файлів... (це може зайняти багато часу)"
        Copy-Item -Path "$($sourceDrive):\*" -Destination "${TempPartitionLetter}:\" -Recurse -Force
        Dismount-DiskImage -ImagePath $isoPath
        Write-Host "Розгортання образу успішно завершено." -ForegroundColor Green
    }

    #================================================================================
    # Модуль 4: Створення файлу автоматичної відповіді
    #================================================================================
    Write-Host "`n=== Модуль 4: Створення файлу autounattend.xml ===" -ForegroundColor Yellow
    $autounattendXmlPath = "${TempPartitionLetter}:\autounattend.xml"
    if (Test-Path $autounattendXmlPath) {
        Write-Host "Файл '$autounattendXmlPath' вже існує. Пропускаємо." -ForegroundColor Green
    } else {
        $NewUserName = $Credential.UserName
        $NewUserPassword = $Credential.GetNetworkCredential().Password
        
        $installFromBlock = ""
        if ($SystemInfo.EditionID) {
            try {
                $imagePath = if (Test-Path "${TempPartitionLetter}:\sources\install.wim") { "${TempPartitionLetter}:\sources\install.wim" } else { "${TempPartitionLetter}:\sources\install.esd" }
                $imageIndex = (Get-WindowsImage -ImagePath $imagePath | Where-Object { $_.ImageName -eq $SystemInfo.EditionID }).ImageIndex[0]
                if ($imageIndex) {
                    $installFromBlock = "<InstallFrom><MetaData wcm:action=`"add`"><Key>/IMAGE/INDEX</Key><Value>$($imageIndex)</Value></MetaData></InstallFrom>"
                }
            } catch { Write-Warning "Не вдалося визначити індекс образу для '$($SystemInfo.EditionID)'. Інсталятор може показати меню вибору." }
        }
        
        $productKeyBlock = ""
        if ($SystemInfo.ProductKey) {
            $productKeyBlock = "<Key>$($SystemInfo.ProductKey)</Key>"
        }

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
                        <ModifyPartition wcm:action="add"><Order>1</Order><PartitionID>1</PartitionID><Format>NTFS</Format></ModifyPartition>
                        <ModifyPartition wcm:action="add"><Order>2</Order><PartitionID>2</PartitionID><Format>NTFS</Format></ModifyPartition>
                    </ModifyPartitions>
                </Disk>
            </DiskConfiguration>
            <ImageInstall>
                <OSImage>
                    $($installFromBlock)
                    <InstallTo><DiskID>0</DiskID><PartitionID>2</PartitionID></InstallTo>
                </OSImage>
            </ImageInstall>
            <UserData>
                <ProductKey>$($productKeyBlock)<WillShowUI>OnError</WillShowUI></ProductKey>
                <AcceptEula>true</AcceptEula>
            </UserData>
        </component>
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
        Write-Host "Файл autounattend.xml успішно створено." -ForegroundColor Green
    }

    #================================================================================
    # Модуль 5: Модифікація завантажувача
    #================================================================================
    Write-Host "`n=== Модуль 5: Модифікація завантажувача ===" -ForegroundColor Yellow
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
    Write-Error "Виникла критична помилка в основному скрипті: $($_.Exception.Message)"
    Read-Host "Натисніть Enter для виходу"
    exit 1
}
