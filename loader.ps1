<#
.SYNOPSIS
    Ультра-надійний завантажувач. Завантажує основний скрипт, перевіряє його
    цілісність за допомогою хеш-суми і запускає його найбезпечнішим способом.
.DESCRIPTION
    Цей скрипт розроблено для роботи в найскладніших середовищах з проблемами
    кешування та кодування.
.NOTES
    Версія: 5.0 - Back to Basics
#>
$ErrorActionPreference = "Stop"

# --- Конфігурація ---
$mainScriptUrl = "https://raw.githubusercontent.com/MYMDO/rewin/main/reinstall.ps1"
$tempFile = "$env:TEMP\reinstall_main.ps1"

# Хеш-сума SHA256 для останньої версії reinstall.ps1
# Цей хеш ви розрахували і надали: 84A9D...2626
$expectedHash = "84A9D33625373F7B0E68867DCF976072CC6870154FA393A98B822B9C759B2626".ToLower()

# --- Основний блок ---
$webClient = $null
try {
    Write-Host "Attempting to download the main script..." -ForegroundColor Cyan
    
    # Використовуємо старий, але надійний WebClient
    $webClient = New-Object System.Net.WebClient
    
    # Агресивно боремося з кешем
    $webClient.Headers.Add("Cache-Control", "no-cache, no-store, must-revalidate")
    $webClient.Headers.Add("Pragma", "no-cache")
    $webClient.Headers.Add("Expires", "0")
    
    # Завантажуємо файл
    $webClient.DownloadFile($mainScriptUrl, $tempFile)
    
    Write-Host "Download complete. Verifying integrity..." -ForegroundColor Green
    
    # Перевіряємо хеш
    $downloadedHash = (Get-FileHash -Path $tempFile -Algorithm SHA256).Hash.ToLower()
    
    if ($downloadedHash -ne $expectedHash) {
        throw "INTEGRITY CHECK FAILED! The downloaded file is corrupted or outdated. Expected hash: $expectedHash, but got: $downloadedHash"
    }
    
    Write-Host "Integrity check passed. Executing..." -ForegroundColor Green
    
    # ЗАПУСКАЄМО НАЙНАДІЙНІШИМ СПОСОБОМ
    # Створюємо новий процес PowerShell, який виконає наш локальний, перевірений файл.
    # Це ізолює виконання і гарантує правильну обробку кодування.
    $process = Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$tempFile`"" -PassThru -Wait
    
    # Перевіряємо, чи успішно завершився процес
    if ($process.ExitCode -ne 0) {
        throw "The main script finished with an error. Exit code: $($process.ExitCode)"
    }

} catch {
    Write-Error "A critical error occurred: $($_.Exception.Message)"
    # Пауза, щоб користувач встиг прочитати помилку
    Read-Host "Press Enter to exit"
    exit 1
} finally {
    if (Test-Path $tempFile) {
        Remove-Item $tempFile -Force
    }
    if ($webClient) {
        $webClient.Dispose()
    }
}
