# Loader Script - v2.1
# This script uses modern HttpClient and a SHA256 hash check for maximum reliability
# when downloading and executing a remote script. It is designed to be robust against
# caching and encoding issues.

# Stop on the first error
$ErrorActionPreference = "Stop"

# URL of the main script to be downloaded and executed
$mainScriptUrl = "https://raw.githubusercontent.com/MYMDO/rewin/main/reinstall.ps1"

# The destination for the temporary local copy of the main script
$tempFile = "$env:TEMP\reinstall_main.ps1"

# SHA256 hash of the known-good reinstall.ps1 file.
# This is the primary integrity check to ensure the file is not corrupted or tampered with.
# This hash was provided by the user.
$expectedHash = "84A9D33625373F7B0E68867DCF976072CC6870154FA393A98B822B9C759B2626".ToLower()

# Initialize the HttpClient variable to be accessible in the 'finally' block
$httpClient = $null

try {
    # --- Step 1: Download the main script reliably ---
    Write-Host "Downloading main script using a reliable method..." -ForegroundColor Cyan
    
    # Using the modern System.Net.Http.HttpClient for more control over the request.
    # This is generally more robust than the older WebClient.
    $httpClient = New-Object System.Net.Http.HttpClient

    # Perform the GET request and wait for the response.
    # GetAwaiter().GetResult() is used to make the asynchronous call synchronous.
    $response = $httpClient.GetAsync($mainScriptUrl).GetAwaiter().GetResult()
    
    # Ensure the HTTP request was successful (e.g., status code 200 OK).
    if (-not $response.IsSuccessStatusCode) {
        throw "Failed to download the script. HTTP Status code: $($response.StatusCode)"
    }
    
    # Read the content of the response as a byte array to avoid any text encoding issues.
    $fileBytes = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
    
    # Write the downloaded bytes directly to a temporary file.
    [System.IO.File]::WriteAllBytes($tempFile, $fileBytes)

    Write-Host "Download complete." -ForegroundColor Green

    # --- Step 2: Verify the integrity of the downloaded file ---
    Write-Host "Verifying file integrity..." -ForegroundColor Cyan

    # Calculate the SHA256 hash of the newly downloaded file.
    $downloadedHash = (Get-FileHash -Path $tempFile -Algorithm SHA256).Hash.ToLower()
    
    # Compare the calculated hash with the expected hash.
    # This is the most critical step to ensure we are running the correct code.
    if ($downloadedHash -ne $expectedHash) {
        # If the hashes do not match, stop immediately and report the error.
        throw "FILE INTEGRITY CHECK FAILED! The downloaded file is corrupted or has been tampered with. Expected hash: $expectedHash, but got: $downloadedHash"
    }
    
    Write-Host "Integrity check passed. The file is authentic." -ForegroundColor Green


    # --- Step 3: Execute the verified script ---
    Write-Host "Executing main script..." -ForegroundColor Cyan
    
    # Use the call operator (&) to execute the script from the temporary file path.
    # This is the safest way to run a script whose path is stored in a variable.
    & $tempFile

} catch {
    # If any error occurs in the 'try' block, it will be caught here.
    Write-Error "A critical error occurred during the loading process: $($_.Exception.Message)"
} finally {
    # This block will always run, regardless of whether an error occurred or not.
    # It's used for cleanup.
    
    # Delete the temporary file to not leave any traces.
    if (Test-Path $tempFile) {
        Remove-Item $tempFile -Force
    }
    
    # Dispose of the HttpClient object to release system resources.
    if ($httpClient) {
        $httpClient.Dispose()
    }
}
