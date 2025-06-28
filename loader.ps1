<#
.SYNOPSIS
    Надійний завантажувач для скрипта перевстановлення Windows (Версія 3.0).
.DESCRIPTION
    Цей скрипт є промисловим стандартом для надійного розгортання. Він завантажує 
    ZIP-архів з останнього релізу на GitHub, який містить основний скрипт та його 
    хеш-суму. Це повністю вирішує проблеми кешування, кодування та цілісності файлів.
.NOTES
    Автор: Ваш досвідчений системний адміністратор
    Версія: 3.0 - GitHub Actions Release
#>

# Зупинятися при першій помилці для передбачуваної поведінки
$ErrorActionPreference = "Stop"

# --- [ Конфігурація ] ---

# URL для завантаження ZIP-архіву з останнього релізу.
# GitHub автоматично перенаправляє /latest/ на найновіший реліз.
$releaseZipUrl = "https://github.com/MYMDO/rewin/releases/latest/download/release.zip"

# Створюємо унікальний шлях у тимчасовій директорії для уникнення конфліктів
$tempDir = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString())
$zipFilePath = Join-Path $tempDir "release.zip"
$mainScriptFileName = "reinstall.ps1"
$hashFileName = "hash.txt"

# --- [ Основний блок виконання ] ---

# Використовуємо try/catch/finally для гарантованого виконання та очищення
try {
    # --- Крок 1: Підготовка середовища ---
    Write-Host "=== Крок 1: Підготовка середовища ===" -ForegroundColor Cyan
    
    # Створюємо тимчасову директорію
    if (-not (Test-Path $tempDir)) {
        New-Item -Path $tempDir -ItemType Directory | Out-Null
    }
    Write-Host "Створено тимчасову директорію: $tempDir"

    # --- Крок 2: Надійне завантаження архіву ---
    Write-Host "`n=== Крок 2: Надійне завантаження архіву релізу ===" -ForegroundColor Cyan

    # Використовуємо старий, але максимально сумісний WebClient, оскільки він гарантовано є в системі.
    # Завантаження бінарного файлу (ZIP) менш схильне до проблем з кодуванням, ніж текстового.
    $webClient = New-Object System.Net.WebClient
    
    # Додаємо заголовки для боротьби з агресивним кешуванням
    $webClient.Headers.Add("Cache-Control", "no-cache, no-store, must-revalidate")
    $webClient.Headers.Add("Pragma", "no-cache")
    $webClient.Headers.Add("Expires", "0")

    Write-Host "Завантаження архіву з: $releaseZipUrl"
    $webClient.DownloadFile($releaseZipUrl, $zipFilePath)
    
    if (-not (Test-Path $zipFilePath)) {
        throw "Не вдалося завантажити архів релізу."
    }
    Write-Host "Архів успішно завантажено: $zipFilePath" -ForegroundColor Green

    # --- Крок 3: Розпакування архіву ---
    Write-Host "`n=== Крок 3: Розпакування архіву ===" -ForegroundColor Cyan
    
    # Використовуємо вбудовану в PowerShell команду для розпакування
    Expand-Archive -Path $zipFilePath -DestinationPath $tempDir -Force
    
    $mainScriptPath = Join-Path $tempDir $mainScriptFileName
    $hashFilePath = Join-Path $tempDir $hashFileName
    
    if (-not (Test-Path $mainScriptPath) -or -not (Test-Path $hashFilePath)) {
        throw "Архів не містить необхідних файлів (reinstall.ps1 та hash.txt)."
    }
    Write-Host "Архів успішно розпаковано." -ForegroundColor Green

    # --- Крок 4: Перевірка цілісності файлу ---
    Write-Host "`n=== Крок 4: Перевірка цілісності (найважливіший етап) ===" -ForegroundColor Cyan
    
    # Читаємо очікуваний хеш з файлу hash.txt, який був створений GitHub Actions
    $expectedHash = (Get-Content $hashFilePath).Trim().ToLower()
    if ([string]::IsNullOrWhiteSpace($expectedHash)) {
        throw "Файл з хеш-сумою порожній або пошкоджений."
    }
    Write-Host "Очікуваний хеш (з архіву): $expectedHash"

    # Розраховуємо хеш для розпакованого основного скрипта
    $downloadedHash = (Get-FileHash -Path $mainScriptPath -Algorithm SHA256).Hash.ToLower()
    Write-Host "Розрахований хеш (локальний): $downloadedHash"

    # Порівнюємо хеші
    if ($downloadedHash -ne $expectedHash) {
        # Якщо хеші не збігаються, це означає, що архів або його вміст було пошкоджено.
        # Зупиняємо виконання негайно.
        throw "ПЕРЕВІРКА ЦІЛІСНОСТІ ПРОВАЛЕНА! Файл пошкоджено або модифіковано."
    }
    
    Write-Host "Перевірка цілісності пройдена. Файл автентичний." -ForegroundColor Green

    # --- Крок 5: Виконання основного скрипта ---
    Write-Host "`n=== Крок 5: Запуск основного скрипта ===" -ForegroundColor Cyan
    
    # Запускаємо перевірений локальний файл. Це найнадійніший спосіб.
    # Використовуємо powershell.exe -File для запуску в чистому середовищі,
    # що правильно обробляє кодування UTF-8 with BOM.
    powershell.exe -ExecutionPolicy Bypass -File $mainScriptPath

} catch {
    # Ловимо будь-яку помилку з блоку 'try' і виводимо її
    Write-Error "Критична помилка під час роботи завантажувача: $($_.Exception.Message)"
    # Зупиняємо скрипт з кодом помилки
    exit 1
} finally {
    # Цей блок виконується завжди, навіть якщо була помилка.
    # Він потрібен для очищення тимчасових файлів.
    Write-Host "`n=== Завершення роботи завантажувача: Очищення ===" -ForegroundColor Cyan
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force
        Write-Host "Тимчасові файли видалено."
    }
    if ($webClient) {
        $webClient.Dispose()
    }
}
