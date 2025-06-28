<#
.SYNOPSIS
    Надійний завантажувач для скрипта перевстановлення Windows (Версія 3.1).
.DESCRIPTION
    Ця версія додає примусове читання основного скрипта в кодуванні UTF-8 перед
    виконанням, щоб обійти проблеми середовища PowerShell.
.NOTES
    Версія: 3.1 - Force UTF-8 Execution
#>

$ErrorActionPreference = "Stop"
$releaseZipUrl = "https://github.com/MYMDO/rewin/releases/latest/download/release.zip"
$tempDir = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString())
$zipFilePath = Join-Path $tempDir "release.zip"
$mainScriptFileName = "reinstall.ps1"
$hashFileName = "hash.txt"

try {
    Write-Host "=== Крок 1: Підготовка середовища ===" -ForegroundColor Cyan
    if (-not (Test-Path $tempDir)) { New-Item -Path $tempDir -ItemType Directory | Out-Null }
    Write-Host "Створено тимчасову директорію: $tempDir"

    Write-Host "`n=== Крок 2: Надійне завантаження архіву релізу ===" -ForegroundColor Cyan
    $webClient = New-Object System.Net.WebClient
    $webClient.Headers.Add("Cache-Control", "no-cache, no-store, must-revalidate")
    $webClient.DownloadFile($releaseZipUrl, $zipFilePath)
    Write-Host "Архів успішно завантажено: $zipFilePath" -ForegroundColor Green

    Write-Host "`n=== Крок 3: Розпакування архіву ===" -ForegroundColor Cyan
    Expand-Archive -Path $zipFilePath -DestinationPath $tempDir -Force
    $mainScriptPath = Join-Path $tempDir $mainScriptFileName
    $hashFilePath = Join-Path $tempDir $hashFileName
    if (-not (Test-Path $mainScriptPath) -or -not (Test-Path $hashFilePath)) { throw "Архів не містить необхідних файлів." }
    Write-Host "Архів успішно розпаковано." -ForegroundColor Green

    Write-Host "`n=== Крок 4: Перевірка цілісності ===" -ForegroundColor Cyan
    $expectedHash = (Get-Content $hashFilePath).Trim().ToLower()
    if ([string]::IsNullOrWhiteSpace($expectedHash)) { throw "Файл з хеш-сумою порожній." }
    Write-Host "Очікуваний хеш (з архіву): $expectedHash"
    $downloadedHash = (Get-FileHash -Path $mainScriptPath -Algorithm SHA256).Hash.ToLower()
    Write-Host "Розрахований хеш (локальний): $downloadedHash"
    if ($downloadedHash -ne $expectedHash) { throw "ПЕРЕВІРКА ЦІЛІСНОСТІ ПРОВАЛЕНА!" }
    Write-Host "Перевірка цілісності пройдена. Файл автентичний." -ForegroundColor Green

    Write-Host "`n=== Крок 5: Запуск основного скрипта (з примусовим читанням в UTF-8) ===" -ForegroundColor Cyan
    $scriptContent = Get-Content -Path $mainScriptPath -Encoding UTF8 -Raw
    Invoke-Expression $scriptContent

} catch {
    Write-Error "Критична помилка під час роботи завантажувача: $($_.Exception.Message)"
    Read-Host "Натисніть Enter для виходу"
    exit 1
} finally {
    Write-Host "`n=== Завершення роботи завантажувача: Очищення ===" -ForegroundColor Cyan
    if (Test-Path $tempDir) { Remove-Item -Path $tempDir -Recurse -Force; Write-Host "Тимчасові файли видалено." }
    if ($webClient) { $webClient.Dispose() }
}
