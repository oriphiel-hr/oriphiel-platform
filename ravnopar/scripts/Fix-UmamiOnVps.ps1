# Ravnopar - automatski Umami fix na VPS (1x scp + 1x ssh)
#
#   powershell -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\ravnopar\scripts\Fix-UmamiOnVps.ps1

param(
  [string]$SshHost = "root@186.240.157.39",
  [string]$RemoteApp = "/var/www/Render/ravnopar",
  [int]$MaxRetries = 3
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path $PSScriptRoot -Parent
$localScript = Join-Path $PSScriptRoot "vps-fix-umami-analytics.sh"
$localUmami = Join-Path $repoRoot "backend\src\services\umami-service.js"
$localIndex = Join-Path $repoRoot "backend\src\index.js"

if (-not (Test-Path $localScript)) { throw "Nema $localScript" }

function Write-UnixTextFile {
  param([string]$Path, [string]$Content)
  $text = $Content -replace "`r`n", "`n" -replace "`r", "`n"
  [System.IO.File]::WriteAllText($Path, $text, (New-Object System.Text.UTF8Encoding $false))
}

function Copy-UnixTextFile {
  param([string]$Source, [string]$Dest)
  $bytes = [System.IO.File]::ReadAllBytes($Source)
  $text = [System.Text.Encoding]::UTF8.GetString($bytes)
  Write-UnixTextFile -Path $Dest -Content $text
}

function Invoke-ScpWithRetry {
  param([string[]]$Sources, [string]$RemoteDest)
  $sshOpts = @("-o", "ConnectTimeout=60", "-o", "ServerAliveInterval=15")
  for ($i = 1; $i -le $MaxRetries; $i++) {
    Write-Host "  scp pokusaj $i/$MaxRetries ($($Sources.Count) datoteka)..." -ForegroundColor Gray
    & scp @sshOpts @Sources "${SshHost}:${RemoteDest}"
    if ($LASTEXITCODE -eq 0) { return }
    if ($i -lt $MaxRetries) {
      Write-Host "  scp nije uspio, cekam 5s..." -ForegroundColor Yellow
      Start-Sleep -Seconds 5
    }
  }
  throw "scp nije uspio nakon $MaxRetries pokusaja."
}

function Invoke-SshWithRetry {
  param([string]$RemoteCmd)
  $sshOpts = @("-o", "ConnectTimeout=60", "-o", "ServerAliveInterval=15")
  for ($i = 1; $i -le $MaxRetries; $i++) {
    Write-Host "  ssh pokusaj $i/$MaxRetries..." -ForegroundColor Gray
    & ssh @sshOpts $SshHost $RemoteCmd
    if ($LASTEXITCODE -eq 0) { return }
    if ($i -lt $MaxRetries) {
      Write-Host "  ssh exit $LASTEXITCODE, cekam 5s..." -ForegroundColor Yellow
      Start-Sleep -Seconds 5
    }
  }
  throw "ssh nije uspio nakon $MaxRetries pokusaja (exit $LASTEXITCODE)."
}

Write-Host ""
Write-Host "=== Ravnopar Umami fix ===" -ForegroundColor Cyan
Write-Host "VPS: $SshHost  |  1x upload + 1x ssh" -ForegroundColor Gray
Write-Host ""

$umamiPass = Read-Host "Umami lozinka (admin)" -AsSecureString
$umamiPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
  [Runtime.InteropServices.Marshal]::SecureStringToBSTR($umamiPass)
)
if (-not $umamiPlain) { throw "Umami lozinka je prazna." }

$passB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($umamiPlain))

$runner = @"
#!/usr/bin/env bash
set -euo pipefail
APP='$RemoteApp'
UMAMI_PASS_B64=`$(tr -d '\r\n' </tmp/umami-pass.b64)
export RAVNOPAR_APP="`$APP" UMAMI_USER=admin UMAMI_PASS_B64
cp /tmp/umami-index.js "`$APP/backend/src/index.js"
cp /tmp/umami-service.js "`$APP/backend/src/services/umami-service.js"
install -m 755 /tmp/vps-fix-umami-analytics.sh "`$APP/scripts/vps-fix-umami-analytics.sh"
bash /tmp/vps-fix-umami-analytics.sh
rm -f /tmp/umami-pass.b64 /tmp/vps-fix-umami-analytics.sh /tmp/umami-index.js /tmp/umami-service.js /tmp/run-umami-fix.sh
"@

$tmpDir = Join-Path $env:TEMP ("ravnopar-umami-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tmpDir | Out-Null
try {
  Copy-UnixTextFile -Source $localScript -Dest (Join-Path $tmpDir "vps-fix-umami-analytics.sh")
  Copy-UnixTextFile -Source $localUmami -Dest (Join-Path $tmpDir "umami-service.js")
  Copy-UnixTextFile -Source $localIndex -Dest (Join-Path $tmpDir "umami-index.js")
  Write-UnixTextFile -Path (Join-Path $tmpDir "umami-pass.b64") -Content $passB64
  Write-UnixTextFile -Path (Join-Path $tmpDir "run-umami-fix.sh") -Content $runner

  $uploadFiles = @(
    (Join-Path $tmpDir "vps-fix-umami-analytics.sh"),
    (Join-Path $tmpDir "umami-service.js"),
    (Join-Path $tmpDir "umami-index.js"),
    (Join-Path $tmpDir "umami-pass.b64"),
    (Join-Path $tmpDir "run-umami-fix.sh")
  )

  Write-Host "1/2 Upload (1x SSH lozinka)..." -ForegroundColor Cyan
  Invoke-ScpWithRetry -Sources $uploadFiles -RemoteDest "/tmp/"

  Write-Host "2/2 Pokretanje fixa (1x SSH lozinka)..." -ForegroundColor Cyan
  Invoke-SshWithRetry -RemoteCmd "chmod +x /tmp/run-umami-fix.sh /tmp/vps-fix-umami-analytics.sh && bash /tmp/run-umami-fix.sh"

  Write-Host ""
  Write-Host "GOTOVO." -ForegroundColor Green
  Write-Host "Osvjezi https://ravnopar.com/admin (Ctrl+F5)" -ForegroundColor Green
  Write-Host ""
}
finally {
  Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}
