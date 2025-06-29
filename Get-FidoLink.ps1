param(
   [switch]$GetUrl,
   [string]$Win = "Latest",
   [string]$Rel = "Latest",
   [string]$Ed,
   [string]$Lang,
   [string]$Arch
)

. "$PSScriptRoot\Fido.ps1"

$downloadLink = Get-FidoLink -Win $Win -Rel $Rel -Ed $Ed -Lang $Lang -Arch $Arch

if ($GetUrl) {
    Write-Output $downloadLink
} else {
    Start-Process $downloadLink  # відкриє браузер
}
