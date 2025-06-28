<#
.SYNOPSIS
    Надійний завантажувач для скрипта перевстановлення Windows (Версія 3.2).
.DESCRIPTION
    Ця версія замінює ненадійний Invoke-Expression на запуск через Start-Process,
    що створює повноцінний новий процес PowerShell і гарантує правильне
    завантаження всіх необхідних системних модулів, таких як 'Storage'.
.NOTES
    Автор: Ваш досвідчений системний адміністратор
    Версія: 3.2 - Start-Process Execution
#>

# Зупинятися при першій помилці для передбачуваної поведінки
$ErrorActionPreference = "Stop"

# --- [ Конфігурація ] ---

# URL для завантаження ZIP-архіву з останнього релізу.
$releaseZipUrl = "https://github.com/MYMDO/rewin/releases/latest/download/release.zip"

# Створюємо унікальний шлях у тимчасовій директорії
$tempDir = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString())
$zipFilePath = Join-Path $tempDir "release.zip"
$mainScriptFileName = "reinstall.ps1"
$hashFileName = "hash.txt"

# --- [ Основний блок виконання ] ---

# Використовуємо try/catch/finally для гарантованого виконання та очищення
try {
    # --- Крок 1: Підготовка середовища ---
    Write-Host "=== Крок 1: Підготовка середовища ===" -ForegroundColor Cyan
    
    if (-not (Test-Path $tempDir)) {
        New-Item -Path $tempDir -ItemType Directory | Out-Null
    }
    Write-Host "Створено тимчасову директорію: $tempDir"

    # --- Крок 2: Надійне завантаження архіву ---
    Write-Host "`n=== Крок 2: Надійне завантаження архіву релізу ===" -ForegroundColor Cyan

    $webClient = New-Object System.Net.WebClient
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
    
    Expand-Archive -Path $zipFilePath -DestinationPath $tempDir -Force
    
    $mainScriptPath = Join-Path $tempDir $mainScriptFileName
    $hashFilePath = Join-Path $tempDir $hashFileName
    
    if (-not (Test-Path $mainScriptPath) -or -not (Test-Path $hashFilePath)) {
        throw "Архів не містить необхідних файлів (reinstall.ps1 та hash.txt)."
    }
    Write-Host "Архів успішно розпаковано." -ForegroundColor Green

    # --- Крок 4: Перевірка цілісності файлу ---
    Write-Host "`n=== Крок 4: Перевірка цілісності ===" -ForegroundColor Cyan
    
    $expectedHash = (Get-Content $hashFilePath).Trim().ToLower()
    if ([string]::IsNullOrWhiteSpace($expectedHash)) {
        throw "Файл з хеш-сумою порожній або пошкоджений."
    }
    Write-Host "Очікуваний хеш (з архіву): $expectedHash"

    $downloadedHash = (Get-FileHash -Path $mainScriptPath -Algorithm SHA256).Hash.ToLower()
    Write-Host "Розрахований хеш (локальний): $downloadedHash"

    if ($downloadedHash -ne $expectedHash) {
        throw "ПЕРЕВІРКА ЦІЛІСНОСТІ ПРОВАЛЕНА! Файл пошкоджено або модифіковано."
    }
    
    Write-Host "Перевірка цілісності пройдена. Файл автентичний." -ForegroundColor Green

    # --- Крок 5: Запуск основного скрипта (найнадійнішим способом) ---
    Write-Host "`n=== Крок 5: Запуск основного скрипта через новий процес ===" -ForegroundColor Cyan
    
    # Формуємо аргументи для нового процесу PowerShell
    # `"$mainScriptPath`" - лапки всередині рядка необхідні, якщо шлях містить пробіли
    $processArgs = "-ExecutionPolicy Bypass -File `"$mainScriptPath`""
    
    # Запускаємо новий, ізольований процес powershell.exe
    # -Wait: чекаємо, поки процес завершиться
    # -PassThru: повертає об'єкт процесу, щоб ми могли перевірити код виходу
    # -Verb RunAs: запускає процес з підвищеними правами (від імені Адміністратора)
    $process = Start-Process powershell.exe -ArgumentList $processArgs -Wait -PassThru -Verb RunAs
    
    # Перевіряємо, чи успішно завершився основний скрипт
    if ($process.ExitCode -ne 0) {
        # Якщо код виходу не 0, значить, в основному скрипті сталася помилка
        throw "Основний скрипт завершився з помилкою. Код виходу: $($process.ExitCode)"
    }
    
    Write-Host "Основний скрипт успішно завершив роботу." -ForegroundColor Green

} catch {
    # Ловимо будь-яку помилку з блоку 'try' і виводимо її
    Write-Error "Критична помилка під час роботи завантажувача: $($_.Exception.Message)"
    Read-Host "Натисніть Enter для виходу"
    exit 1
} finally {
    # Цей блок виконується завжди для очищення
    Write-Host "`n=== Завершення роботи завантажувача: Очищення ===" -ForegroundColor Cyan
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force
        Write-Host "Тимчасові файли видалено."
    }
    if ($webClient) {
        $webClient.Dispose()
    }
}
