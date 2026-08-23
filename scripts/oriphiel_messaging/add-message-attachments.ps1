# Dodaje tablicu message_attachments u bazu oriphiel
# Pokreni:
#   powershell -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\scripts\oriphiel_messaging\add-message-attachments.ps1

[CmdletBinding()]
param(
  [string]$SshTarget = "root@186.240.157.80",
  [string]$PgContainer = "oriphiel-postgres",
  [string]$DbName = "oriphiel",
  [string]$DbUser = "oriphiel",
  [string]$SchemaFile = ""
)

$ErrorActionPreference = "Stop"

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $SchemaFile) {
  $SchemaFile = Join-Path $scriptDir "sql\message-attachments.sql"
}
if (-not (Test-Path -LiteralPath $SchemaFile)) {
  throw "Nedostaje: $SchemaFile"
}

$raw = [System.IO.File]::ReadAllText($SchemaFile)
$raw = $raw -replace "`r`n", "`n" -replace "`r", "`n"
$tmp = Join-Path $env:TEMP "message-attachments.sql"
[System.IO.File]::WriteAllText($tmp, $raw, (New-Object System.Text.UTF8Encoding $false))

Write-Host "1) Upload SQL ..." -ForegroundColor Cyan
scp $tmp "${SshTarget}:/tmp/message-attachments.sql"

Write-Host "2) Primjena na bazu $DbName ..." -ForegroundColor Cyan
ssh $SshTarget "sed -i 's/\r`$//' /tmp/message-attachments.sql; cat /tmp/message-attachments.sql | docker exec -i $PgContainer psql -U $DbUser -d $DbName -v ON_ERROR_STOP=1"

Write-Host "3) Provjera:" -ForegroundColor Cyan
ssh $SshTarget "docker exec -i $PgContainer psql -U $DbUser -d $DbName -c '\d message_attachments'"

Write-Host ""
Write-Host "GOTOVO. Tablica: message_attachments" -ForegroundColor Green
Write-Host "Datoteke spremaj na disk/S3; u bazu ide samo storage_path + metadata."