## REWIN ;)

---

```
powershell.exe -ExecutionPolicy Bypass -Command "Invoke-Expression (New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/MYMDO/rewin/main/loader.ps1')"
```

```
powershell.exe -ExecutionPolicy Bypass -Command "Invoke-Expression (Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/MYMDO/rewin/main/reinstall.ps1' -UseBasicParsing -DisableKeepAlive -Headers @{'Cache-Control'='no-cache'})"
```

```
bcdedit /set {25e59fcf-3112-11f0-9bf0-bc85974cd5b0} path \Windows\system32\boot\winload.exe
```
