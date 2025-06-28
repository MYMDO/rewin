<#
.SYNOPSIS
    Універсальний скрипт для автоматичного перевстановлення Windows 10 (Версія 5.3).
.DESCRIPTION
    Версія 5.3 додає паузу в кінці скрипта у випадку помилки, щоб дозволити
    прочитати повідомлення про помилку перед закриттям вікна.
.NOTES
    Версія: 5.3 - Debug Pause
#>

$ErrorActionPreference = "Stop"
function Get-ValueOrDefault($value, $default = "N/A") { if ($value -and (-not [string]::IsNullOrWhiteSpace($value))) { return $value } else { return $default } }

function Get-System-Information {
    Write-Host "=== Модуль 1: Перевірка середовища та збір інформації ===" -ForegroundColor Yellow
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw "Помилка: Скрипт необхідно запустити від імені Адміністратора." }
    $sysInfoObject = [PSCustomObject]@{
        OSArchitecture  = (Get-CimInstance Win32_OperatingSystem).OSArchitecture
        FirmwareType    = $env:firmware_type
        SystemPartition = Get-Partition -DriveLetter C
        Disk            = Get-Disk -Number (Get-Partition -DriveLetter C).DiskNumber
    }
    try { $sysInfoObject | Add-Member -MemberType NoteProperty -Name "EditionID" -Value ((Get-CimInstance -ClassName Win32_OperatingSystem).Caption -replace "Microsoft Windows 10 ", "") } catch { $sysInfoObject | Add-Member -MemberType NoteProperty -Name "EditionID" -Value $null }
    try { $sysInfoObject | Add-Member -MemberType NoteProperty -Name "ProductKey" -Value (Get-WmiObject -query 'select * from SoftwareLicensingService').OA3xOriginalProductKey } catch { $sysInfoObject | Add-Member -MemberType NoteProperty -Name "ProductKey" -Value $null }
    return $sysInfoObject
}

function Start-DiskPreparation {
    param([Parameter(Mandatory=$true)] [PSCustomObject]$SystemInfo, [Parameter(Mandatory=$true)] [string]$TempPartitionLetter, [Parameter(Mandatory=$true)] [string]$TempPartitionLabel, [Parameter(Mandatory=$true)] [int]$RequiredSpaceGB)
    Write-Host "`n=== Модуль 2: Підготовка дискового простору ===" -ForegroundColor Yellow
    $tempVolume = Get-Volume -DriveLetter $TempPartitionLetter -ErrorAction SilentlyContinue
    if ($tempVolume -and $tempVolume.FileSystemLabel -eq $TempPartitionLabel) {
        Write-Host "Тимчасовий розділ '$($TempPartitionLabel)' ($($TempPartitionLetter):) вже існує. Пропускаємо." -ForegroundColor Green
        return $TempPartitionLetter
    }
    Write-Host "Тимчасовий розділ не знайдено. Спроба автоматичної підготовки..."
    try {
        if ($SystemInfo.Disk.PartitionStyle -eq "MBR") {
            $PrimaryPartitions = Get-Partition -DiskNumber $SystemInfo.Disk.Number | Where-Object { $_.Type -in 'IFS', 'FAT32', 'FAT16', 'NTFS', 'Primary' }
            if ($PrimaryPartitions.Count -ge 4) { throw "Ваш диск MBR вже має 4 первинних розділи. Видаліть зайвий розділ вручну." }
        }
        $PartitionToResize = $SystemInfo.SystemPartition
        $unallocatedSpace = Get-Disk -Number $PartitionToResize.DiskNumber | Get-Partition | Where-Object { $_.Type -eq 'Unused' } | Measure-Object -Property Size -Sum | Select-Object -ExpandProperty Sum
        if ($unallocatedSpace -lt ($RequiredSpaceGB * 1GB)) {
            Resize-Partition -DiskNumber $PartitionToResize.DiskNumber -PartitionNumber $PartitionToResize.PartitionNumber -Size ($PartitionToResize.Size - ($RequiredSpaceGB * 1GB))
        }
        Update-Disk -DiskNumber $PartitionToResize.DiskNumber
        $NewPartition = New-Partition -DiskNumber $PartitionToResize.DiskNumber -UseMaximumSize -AssignDriveLetter
        $newDriveLetter = $NewPartition.DriveLetter
        Format-Volume -DriveLetter $newDriveLetter -FileSystem NTFS -NewFileSystemLabel $TempPartitionLabel -Confirm:$false -Force
        if ($SystemInfo.FirmwareType -ne "UEFI") {
            $DiskPartScript = "select disk $($SystemInfo.Disk.Number)`nselect partition $($NewPartition.PartitionNumber)`nactive`nexit"
            $DiskPartScript | diskpart
        }
        Write-Host "Автоматична підготовка диска успішно завершена." -ForegroundColor Green
        return $newDriveLetter
    } catch {
        Write-Error "Автоматична підготовка диска не вдалася: $($_.Exception.Message)"
        Write-Error "БУДЬ ЛАСКА, ВИКОНАЙТЕ ЦІ КРОКИ ВРУЧНУ..."
        exit
    }
}

function Start-ImageDeployment {
    param([Parameter(Mandatory=$true)] [string]$TempPartitionLetter, [Parameter(Mandatory=$true)] [string]$WorkingDir)
    Write-Host "`n=== Модуль 3: Завантаження та розгортання образу ===" -ForegroundColor Yellow
    $isoPath = Join-Path $WorkingDir "Win10_x64.iso"
    if ((Test-Path "${TempPartitionLetter}:\sources\install.wim") -or (Test-Path "${TempPartitionLetter}:\sources\install.esd")) { Write-Host "Інсталяційні файли вже розгорнуто. Пропускаємо." -ForegroundColor Green; return }
    if (-not (Test-Path $WorkingDir)) { New-Item -Path $WorkingDir -ItemType Directory | Out-Null }
    if (-not (Test-Path $isoPath)) { Read-Host "ISO-образ не знайдено. Помістіть 'Win10_x64.iso' у '$WorkingDir' і натисніть Enter"; if (-not (Test-Path $isoPath)) { throw "Файл ISO так і не було знайдено." } }
    $mountedImage = Mount-DiskImage -ImagePath $isoPath -PassThru
    $sourceDrive = ($mountedImage | Get-Volume).DriveLetter
    Copy-Item -Path "$($sourceDrive):\*" -Destination "${TempPartitionLetter}:\" -Recurse -Force
    Dismount-DiskImage -ImagePath $isoPath
    Write-Host "Розгортання образу успішно завершено." -ForegroundColor Green
}

function Create-AutoUnattendFile {
    param([Parameter(Mandatory=$true)] [PSCustomObject]$SystemInfo, [Parameter(Mandatory=$true)] [string]$TempPartitionLetter, [Parameter(Mandatory=$true)] [PSCredential]$Credential)
    Write-Host "`n=== Модуль 4: Створення файлу autounattend.xml ===" -ForegroundColor Yellow
    $autounattendXmlPath = "${TempPartitionLetter}:\autounattend.xml"
    if (Test-Path $autounattendXmlPath) { Write-Host "Файл '$autounattendXmlPath' вже існує. Пропускаємо." -ForegroundColor Green; return }
    $NewUserName = $Credential.UserName
    $NewUserPassword = $Credential.GetNetworkCredential().Password
    $installFromBlock = ""; if ($SystemInfo.EditionID) { try { $imagePath = if (Test-Path "${TempPartitionLetter}:\sources\install.wim") { "${TempPartitionLetter}:\sources\install.wim" } else { "${TempPartitionLetter}:\sources\install.esd" }; $imageIndex = (Get-WindowsImage -ImagePath $imagePath | Where-Object { $_.ImageName -eq $SystemInfo.EditionID }).ImageIndex[0]; if ($imageIndex) { $installFromBlock = "<InstallFrom><MetaData wcm:action=`"add`"><Key>/IMAGE/INDEX</Key><Value>$($imageIndex)</Value></MetaData></InstallFrom>" } } catch { Write-Warning "Не вдалося визначити індекс образу для '$($SystemInfo.EditionID)'." } }
    $productKeyBlock = ""; if ($SystemInfo.ProductKey) { $productKeyBlock = "<Key>$($SystemInfo.ProductKey)</Key>" }
    $xmlContent = "<?xml version=`"1.0`" encoding=`"utf-8`"?><unattend xmlns=`"urn:schemas-microsoft-com:unattend`"><settings pass=`"windowsPE`"><component name=`"Microsoft-Windows-Setup`" processorArchitecture=`"amd64`" publicKeyToken=`"31bf3856ad364e35`" language=`"neutral`" versionScope=`"nonSxS`"><DiskConfiguration><Disk wcm:action=`"add`"><DiskID>$($SystemInfo.Disk.Number)</DiskID><WillWipeDisk>false</WillWipeDisk><ModifyPartitions><ModifyPartition wcm:action=`"add`"><Order>1</Order><PartitionID>1</PartitionID><Format>NTFS</Format></ModifyPartition><ModifyPartition wcm:action=`"add`"><Order>2</Order><PartitionID>2</PartitionID><Format>NTFS</Format></ModifyPartition></ModifyPartitions></Disk></DiskConfiguration><ImageInstall><OSImage>$($installFromBlock)<InstallTo><DiskID>$($SystemInfo.Disk.Number)</DiskID><PartitionID>2</PartitionID></InstallTo></OSImage></ImageInstall><UserData><ProductKey>$($productKeyBlock)<WillShowUI>OnError</WillShowUI></ProductKey><AcceptEula>true</AcceptEula></UserData></component></settings><settings pass=`"oobeSystem`"><component name=`"Microsoft-Windows-Shell-Setup`" processorArchitecture=`"amd64`" publicKeyToken=`"31bf3856ad364e35`" language=`"neutral`" versionScope=`"nonSxS`"><OOBE><HideEULAPage>true</HideEULAPage><HideOEMRegistrationScreen>true</HideOEMRegistrationScreen><HideOnlineAccountScreens>true</HideOnlineAccountScreens><HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE><NetworkLocation>Work</NetworkLocation><ProtectYourPC>1</ProtectYourPC></OOBE><UserAccounts><LocalAccounts><LocalAccount wcm:action=`"add`"><Password><Value>$($NewUserPassword)</Value><PlainText>true</PlainText></Password><Description>Local Administrator Account</Description><DisplayName>$($NewUserName)</DisplayName><Group>Administrators</Group><Name>$($NewUserName)</Name></LocalAccount></LocalAccounts></UserAccounts></component></settings></unattend>"
    $xmlContent | Out-File -FilePath $autounattendXmlPath -Encoding utf8
    Write-Host "Файл autounattend.xml успішно створено." -ForegroundColor Green
}

function Start-BootloaderModification {
    param([Parameter(Mandatory=$true)] [PSCustomObject]$SystemInfo, [Parameter(Mandatory=$true)] [string]$TempPartitionLetter)
    Write-Host "`n=== Модуль 5: Модифікація завантажувача ===" -ForegroundColor Yellow
    bcdboot "${TempPartitionLetter}:\Windows" /s "${TempPartitionLetter}:" /f $SystemInfo.FirmwareType
    $BcdOutput = bcdedit /create /d "Windows Reinstall (Temp)" /application osloader
    $Guid = ($BcdOutput -split '[\{\}]')[1]; $Guid = "{${Guid}}"
    if (-not $Guid) { throw "Не вдалося створити запис BCD." }
    bcdedit /set $Guid device "partition=${TempPartitionLetter}:"; bcdedit /set $Guid osdevice "partition=${TempPartitionLetter}:"
    if ($SystemInfo.FirmwareType -eq "UEFI") { bcdedit /set $Guid path \EFI\Microsoft\Boot\bootmgfw.efi } else { bcdedit /set $Guid path \Windows\system32\winload.exe }
    bcdedit /set $Guid systemroot \Windows; bcdedit /bootsequence $Guid
    Write-Host "Завантажувач успішно налаштовано." -ForegroundColor Green
}

try {
    $WorkingDir = "C:\Temp-Win-Reinstall"; $TempPartitionLetter = "W"; $TempPartitionLabel = "WinInstall"; $RequiredSpaceGB = 12
    $SysInfo = Get-System-Information
    if (-not (Get-Volume -DriveLetter $TempPartitionLetter -ErrorAction SilentlyContinue)) {
        Write-Host "`n--- Зібрана системна інформація ---" -ForegroundColor Cyan
        Write-Host "Архітектура ОС: $($SysInfo.OSArchitecture)"; Write-Host "Редакція Windows: $(Get-ValueOrDefault $SysInfo.EditionID 'Не визначено')"; Write-Host "Режим прошивки: $($SysInfo.FirmwareType)"; Write-Host "Тип розмітки диска: $($SysInfo.Disk.PartitionStyle)"
        if ($SysInfo.ProductKey) { Write-Host "Знайдений ключ продукту (OEM): $($SysInfo.ProductKey)" } else { Write-Warning "Ключ продукту не знайдено."}
        Write-Warning "`nУВАГА! НАСТУПНИЙ КРОК РОЗПОЧНЕ НЕЗВОРОТНІ ЗМІНИ НА ВАШОМУ ДИСКУ!"
        $Confirmation = Read-Host "Для продовження введіть слово 'ТАК' і натисніть Enter"
        if ($Confirmation -ne 'ТАК') { Write-Host "Операцію скасовано користувачем."; exit }
    }
    $Credential = Get-Credential -UserName "Admin" -Message "Введіть логін та пароль для нового облікового запису адміністратора"
    $ActualTempDriveLetter = Start-DiskPreparation -SystemInfo $SysInfo -TempPartitionLetter $TempPartitionLetter -TempPartitionLabel $TempPartitionLabel -RequiredSpaceGB $RequiredSpaceGB
    Start-ImageDeployment -TempPartitionLetter $ActualTempDriveLetter -WorkingDir $WorkingDir
    Create-AutoUnattendFile -SystemInfo $SysInfo -TempPartitionLetter $ActualTempDriveLetter -Credential $Credential
    Start-BootloaderModification -SystemInfo $SysInfo -TempPartitionLetter $ActualTempDriveLetter
    Write-Host "`n--- ПІДГОТОВКА ЗАВЕРШЕНА ---" -ForegroundColor Magenta
    Write-Host "Комп'ютер буде перезавантажено через 15 секунд."
    Start-Sleep -Seconds 15
    Restart-Computer -Force
} catch {
    Write-Error "Виникла критична помилка в основному скрипті: $($_.Exception.Message)"
    Read-Host "Натисніть Enter, щоб закрити вікно"
    exit 1
}
