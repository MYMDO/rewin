# Loader Script - v2.2
# Maximum Compatibility Version. Uses the legacy WebClient but retains the
# SHA256 hash check for reliability. This should work on very old PowerShell versions.

$ErrorActionPreference = "Stop"
$mainScriptUrl = "https://raw.githubusercontent.com/MYMDO/rewin/main/reinstall.ps1"
$tempFile = "$env:TEMP\reinstall_main.ps1"

# SHA256 hash of the known-good reinstall.ps1 file.
$expectedHash = "84A9D33625373F7B0E68867DCF976072CC6870154FA393A98B822B9C759B2626".ToLower()

# Initialize the WebClient variable to be accessible in the 'finally' block
$webClient = $null

try {
    # --- Step 1: Download the main script reliably ---
    Write-Host "Downloading main script using a compatible method..." -ForegroundColor Cyan
    
    # Using the legacy System.Net.WebClient, which is available on all systems.
    $webClient = New-Object System.Net.WebClient
    
    # Add headers to bypass cache, just in case.
    $webClient.Headers.Add("Cache-Control", "no-cache")
    $webClient.Headers.Add("Pragma", "no-cache")

    # Download the file to the temporary location.
    $webClient.DownloadFile($mainScriptUrl, $tempFile)

    Write-Host "Download complete." -ForegroundColor Green

    # --- Step 2: Verify the integrity of the downloaded file ---
    Write-Host "Verifying file integrity..." -ForegroundColor Cyan

    # Calculate the SHA256 hash of the newly downloaded file.
    $downloadedHash = (Get-FileHash -Path $tempFile -Algorithm SHA256).Hash.ToLower()
    
    # Compare the calculated hash with the expected hash.
    if ($downloadedHash -ne $expectedHash) {
        throw "FILE INTEGRITY CHECK FAILED! The downloaded file is corrupted. Expected: $expectedHash, Got: $downloadedHash"
    }
    
    Write-Host "Integrity check passed. The file is authentic." -ForegroundColor Green

    # --- Step 3: Execute the verified script ---
    Write-Host "Executing main script..." -ForegroundColor Cyan
    
    # Use the call operator (&) to execute the script from the temporary file path.
    # We must use powershell.exe -File to ensure the script runs in a clean scope
    # and handles encoding correctly, especially if the main script has UTF-8 with BOM.
    powershell.exe -ExecutionPolicy Bypass -File $tempFile

} catch {
    Write-Error "A critical error occurred during the loading process: $($_.Exception.Message)"
} finally {
    if (Test-Path $tempFile) {
        Remove-Item $tempFile -Force
    }
    if ($webClient) {
        $webClient.Dispose()
    }
}
