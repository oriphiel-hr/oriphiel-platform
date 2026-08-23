# Deploy Sudreg na Ollama VPS s Windowsa (zahtijeva SSH kljuc)
#
# Primjer:
#   powershell -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Deploy-SudregToVps.ps1
#   powershell -ExecutionPolicy Bypass -File ...\Deploy-SudregToVps.ps1 -SshTarget root@186.240.157.80 -RunBootstrap

[CmdletBinding()]
param(
  [string]$SshTarget = "root@186.240.157.80",
  [string]$RemoteRoot = "/opt/oriphiel-ai",
  [switch]$RunInstall,
  [switch]$RunBootstrap,
  [switch]$SkipUpload
)

$ErrorActionPreference = "Stop"
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..\..")).Path

Write-Host "SSH test: $SshTarget" -ForegroundColor Cyan
ssh -o BatchMode=yes -o ConnectTimeout=15 $SshTarget "echo OK; docker ps --format '{{.Names}}' | head -5"

if (-not $SkipUpload) {
  Write-Host "Kreiram remote direktorije..." -ForegroundColor Cyan
  ssh $SshTarget "mkdir -p $RemoteRoot/scripts/sudreg/sql $RemoteRoot/data/sudreg/logs"

  Write-Host "Upload skripti..." -ForegroundColor Cyan
  $files = @(
    "SudregPg.ps1",
    "SudregRun.ps1",
    "Sudreg-Control.ps1",
    "Check-Sudreg.ps1",
    "Get-SudregToken.ps1",
    "Get-SudregSnapshots.ps1",
    "Get-SudregPromjene.ps1",
    "Get-SudregSubject.ps1",
    "Sync-SudregPromjeneAll.ps1",
    "Compare-SudregPromjene.ps1",
    "Sync-SudregToPostgres.ps1",
    "Update-Sudreg.ps1",
    "Run-SudregDaily.ps1",
    "setup-sudreg-db.ps1",
    "vps-install-sudreg.sh",
    "mbs-sample.txt"
  )
  foreach ($f in $files) {
    $src = Join-Path $scriptDir $f
    if (-not (Test-Path -LiteralPath $src)) { throw "Nedostaje lokalno: $src" }
    scp $src "${SshTarget}:$RemoteRoot/scripts/sudreg/$f" | Out-Null
    Write-Host "  + $f"
  }
  scp (Join-Path $scriptDir "sql\sudreg-schema.sql") "${SshTarget}:$RemoteRoot/scripts/sudreg/sql/sudreg-schema.sql" | Out-Null
  Write-Host "  + sql/sudreg-schema.sql"
  scp (Join-Path $scriptDir "sql\useful-selects.sql") "${SshTarget}:$RemoteRoot/scripts/sudreg/sql/useful-selects.sql" | Out-Null
  Write-Host "  + sql/useful-selects.sql"
}

if ($RunInstall -or $RunBootstrap) {
  Write-Host "Remote install..." -ForegroundColor Cyan
  ssh $SshTarget "sed -i 's/\r$//' $RemoteRoot/scripts/sudreg/vps-install-sudreg.sh; chmod +x $RemoteRoot/scripts/sudreg/vps-install-sudreg.sh; SUDREG_ROOT=$RemoteRoot bash $RemoteRoot/scripts/sudreg/vps-install-sudreg.sh"
}

if ($RunBootstrap) {
  Write-Host "Bootstrap Update-Sudreg (moze trajati satima)..." -ForegroundColor Yellow
  ssh $SshTarget "nohup $RemoteRoot/scripts/sudreg/run-sudreg-daily.sh >/dev/null 2>&1 & echo started_pid=\$!"
}

Write-Host ""
Write-Host "Deploy koraci gotovi." -ForegroundColor Green
Write-Host "Ako nisi koristio -RunInstall, na VPS-u pokreni:"
Write-Host "  bash $RemoteRoot/scripts/sudreg/vps-install-sudreg.sh"
