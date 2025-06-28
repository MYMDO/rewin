# Loader Script - v1.0
# This script reliably downloads the main script with correct UTF-8 encoding and executes it.

$ErrorActionPreference = "Stop"
$mainScriptUrl = "https://raw.githubusercontent.com/MYMDO/rewin/main/reinstall.ps1"
$tempFile = "$env:TEMP\reinstall_main.ps1"

try {
    Write-Host "Downloading main script with correct encoding..."
    
    # Use WebClient with explicit UTF-8 encoding to download the main script
    $webClient = New-Object System.Net.WebClient
    $webClient.Encoding = [System.Text.Encoding]::UTF8
    $webClient.Headers.Add("Cache-Control", "no-cache") # Bypass cache
    $webClient.DownloadFile($mainScriptUrl, $tempFile)

    Write-Host "Download complete. Executing main script..."
    
    # Execute the downloaded local file, which preserves encoding
    & $tempFile

} catch {
    Write-Error "Failed to download or execute the main script: $($_.Exception.Message)"
} finally {
    # Clean up the temporary file
    if (Test-Path $tempFile) {
        Remove-Item $tempFile -Force
    }
}
