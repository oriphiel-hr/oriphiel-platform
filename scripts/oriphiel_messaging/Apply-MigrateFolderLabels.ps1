# Migracija: folder / labels / deleted_at
#   powershell -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\scripts\oriphiel_messaging\Apply-MigrateFolderLabels.ps1

[CmdletBinding()]
param(
  [string]$SshTarget = "root@186.240.157.80",
  [string]$PgContainer = "oriphiel-postgres",
  [string]$DbName = "oriphiel",
  [string]$DbUser = "oriphiel"
)

$ErrorActionPreference = "Stop"

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$SchemaFile = Join-Path $scriptDir "sql\migrate-messages-folder-labels.sql"
if (-not (Test-Path -LiteralPath $SchemaFile)) {
  throw "Nedostaje: $SchemaFile"
}

$raw = [System.IO.File]::ReadAllText($SchemaFile)
$raw = $raw -replace "`r`n", "`n" -replace "`r", "`n"
$tmp = Join-Path $env:TEMP "migrate-messages-folder-labels.sql"
[System.IO.File]::WriteAllText($tmp, $raw, (New-Object System.Text.UTF8Encoding $false))

Write-Host "1) Upload SQL ..." -ForegroundColor Cyan
scp $tmp "${SshTarget}:/tmp/migrate-messages-folder-labels.sql"

Write-Host "2) Primjena na bazu $DbName ..." -ForegroundColor Cyan
ssh $SshTarget "sed -i 's/\r`$//' /tmp/migrate-messages-folder-labels.sql; cat /tmp/migrate-messages-folder-labels.sql | docker exec -i $PgContainer psql -U $DbUser -d $DbName -v ON_ERROR_STOP=1"

Write-Host "3) Provjera:" -ForegroundColor Cyan
ssh $SshTarget "docker exec -i $PgContainer psql -U $DbUser -d $DbName -c '\d messages'"

Write-Host ""
Write-Host "GOTOVO: folder, imap_uid, labels, deleted_at" -ForegroundColor Green
