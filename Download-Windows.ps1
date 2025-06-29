# Шлях, куди буде збережено ISO-образ
$DownloadFolder = "C:\ISO"

# Перевірка та створення папки, якщо її не існує
if (-not (Test-Path -Path $DownloadFolder)) {
    New-Item -ItemType Directory -Path $DownloadFolder | Out-Null
}

# Шлях до скрипту Fido.ps1
$FidoScriptPath = ".\Fido.ps1"

# --- Параметри для завантаження ---
# Вкажіть бажану версію Windows: "Windows 11" або "Windows 10"
$WindowsVersion = "Windows 11"

# Виклик скрипта Fido для отримання посилання на завантаження
# Скрипт автоматично вибере останню доступну збірку (наприклад, 23H2)
Write-Host "Отримання посилання для завантаження $WindowsVersion..."
$DownloadURL = . $FidoScriptPath -Win $WindowsVersion -GetUrl

if ($DownloadURL) {
    # Визначення імені файлу з URL
    $FileName = [System.IO.Path]::GetFileName($DownloadURL.Split('?')[0])
    $DestinationPath = Join-Path -Path $DownloadFolder -ChildPath $FileName

    Write-Host "Початок завантаження: $FileName"
    Write-Host "Збереження до: $DestinationPath"

    # Завантаження файлу
    Invoke-WebRequest -Uri $DownloadURL -OutFile $DestinationPath

    Write-Host "Завантаження завершено успішно!"
}
else {
    Write-Host "Не вдалося отримати посилання для завантаження." -ForegroundColor Red
}
