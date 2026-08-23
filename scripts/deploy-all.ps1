# Oriphiel AI — puni deploy: branding + tools OFF
# Pokreni: powershell -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\scripts\deploy-all.ps1
$ErrorActionPreference = "Stop"
& (Join-Path $PSScriptRoot "upload-branding.ps1")
