# Popravi Umami analitiku na Ravnopar VPS (186.240.157.39)
#
#   powershell -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\ravnopar\scripts\Fix-UmamiOnVps.ps1

param(
  [string]$SshHost = "root@186.240.157.39",
  [string]$RemoteApp = "/var/www/Render/ravnopar"
)

$ErrorActionPreference = "Stop"
$localScript = Join-Path $PSScriptRoot "vps-fix-umami-analytics.sh"
$localUmami = Join-Path (Split-Path $PSScriptRoot -Parent) "backend\src\services\umami-service.js"
$localIndex = Join-Path (Split-Path $PSScriptRoot -Parent) "backend\src\index.js"

if (-not (Test-Path $localScript)) { throw "Nema $localScript" }

function Send-UnixTextFile {
  param([string]$LocalPath, [string]$RemoteDest)
  $bytes = [System.IO.File]::ReadAllBytes($LocalPath)
  $text = [System.Text.Encoding]::UTF8.GetString($bytes)
  $text = $text -replace "`r`n", "`n" -replace "`r", "`n"
  $tmp = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.IO.Path]::GetRandomFileName())
  [System.IO.File]::WriteAllText($tmp, $text, (New-Object System.Text.UTF8Encoding $false))
  try {
    scp $tmp "${SshHost}:${RemoteDest}"
  } finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  }
}

Write-Host "Ravnopar Umami fix -> $SshHost" -ForegroundColor Cyan
Write-Host "Trebat ce: (1) SSH root lozinka  (2) Umami admin lozinka" -ForegroundColor Yellow

$umamiPass = Read-Host "Umami lozinka (korisnik admin)" -AsSecureString
$umamiPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
  [Runtime.InteropServices.Marshal]::SecureStringToBSTR($umamiPass)
)
if (-not $umamiPlain) { throw "Umami lozinka je prazna." }

# bash single-quoted escape
$escaped = $umamiPlain -replace "'", "'\\''"

Write-Host "Upload (LF) skripte + backend fix..." -ForegroundColor Cyan
Send-UnixTextFile -LocalPath $localScript -RemoteDest "/tmp/vps-fix-umami-analytics.sh"
if (Test-Path $localUmami) {
  Send-UnixTextFile -LocalPath $localUmami -RemoteDest "${RemoteApp}/backend/src/services/umami-service.js"
}
if (Test-Path $localIndex) {
  Send-UnixTextFile -LocalPath $localIndex -RemoteDest "${RemoteApp}/backend/src/index.js"
}

$remoteCmd = "chmod +x /tmp/vps-fix-umami-analytics.sh && UMAMI_USER=admin UMAMI_PASS='$escaped' bash /tmp/vps-fix-umami-analytics.sh && rm -f /tmp/vps-fix-umami-analytics.sh"

Write-Host "Pokrecem fix na VPS-u (SSH lozinka slijedi)..." -ForegroundColor Cyan
ssh $SshHost $remoteCmd
if ($LASTEXITCODE -ne 0) { throw "SSH fix nije uspio (exit $LASTEXITCODE)." }

Write-Host ""
Write-Host "Gotovo. Osvjezi https://ravnopar.com/admin" -ForegroundColor Green
