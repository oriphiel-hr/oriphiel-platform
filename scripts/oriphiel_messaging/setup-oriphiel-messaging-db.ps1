# Oriphiel messaging - Postgres baza "oriphiel"
# (channels_accounts + contacts + messages: mail, kasnije Facebook)
#
# Pokreni:
#   powershell -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\scripts\oriphiel_messaging\setup-oriphiel-messaging-db.ps1
#
# Prije produkcije: -DbPass "TvojaLozinka" ili promijeni default ispod.
# Sudreg: C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\setup-sudreg-db.ps1

[CmdletBinding()]
param(
  [string]$SshTarget = "root@186.240.157.80",
  [string]$DbName = "oriphiel",
  [string]$DbUser = "oriphiel",
  [string]$DbPass = "UpB7v7zU+i16"
)

$ErrorActionPreference = "Stop"

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$Sh = Join-Path $scriptDir "setup-oriphiel-messaging-db.sh"
$SchemaFile = Join-Path $scriptDir "sql\oriphiel-messaging-schema.sql"

if (-not (Test-Path -LiteralPath $Sh)) { throw "Nedostaje: $Sh" }
if (-not (Test-Path -LiteralPath $SchemaFile)) { throw "Nedostaje: $SchemaFile" }

function Write-UnixFile([string]$SourcePath, [string]$DestPath) {
  $raw = [System.IO.File]::ReadAllText($SourcePath)
  $raw = $raw -replace "`r`n", "`n" -replace "`r", "`n"
  $enc = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($DestPath, $raw, $enc)
}

Write-Host ("Baza: {0} (oriphiel_messaging - accounti / kontakti / poruke)" -f $DbName) -ForegroundColor Cyan

# Lokalno pretvori u LF prije scp (Windows CRLF lomi bash)
$tmpSh = Join-Path $env:TEMP "setup-oriphiel-messaging-db.sh"
$tmpSql = Join-Path $env:TEMP "oriphiel-messaging-schema.sql"
Write-UnixFile -SourcePath $Sh -DestPath $tmpSh
Write-UnixFile -SourcePath $SchemaFile -DestPath $tmpSql

Write-Host "1) Upload setup + schema ..."
ssh $SshTarget "mkdir -p /root/oriphiel-ai/oriphiel_messaging"
scp $tmpSh "${SshTarget}:/root/oriphiel-ai/oriphiel_messaging/setup-oriphiel-messaging-db.sh"
scp $tmpSql "${SshTarget}:/tmp/oriphiel-messaging-schema.sql"

Write-Host "2) Primjena na VPS ..."
# Jedna linija - PowerShell here-string inače šalje CRLF u remote bash
$cmd = "sed -i 's/\r`$//' /root/oriphiel-ai/oriphiel_messaging/setup-oriphiel-messaging-db.sh /tmp/oriphiel-messaging-schema.sql; chmod +x /root/oriphiel-ai/oriphiel_messaging/setup-oriphiel-messaging-db.sh; export DB_NAME='$DbName' DB_USER='$DbUser' DB_PASS='$DbPass' SCHEMA_FILE=/tmp/oriphiel-messaging-schema.sql; bash /root/oriphiel-ai/oriphiel_messaging/setup-oriphiel-messaging-db.sh"
ssh $SshTarget $cmd

Write-Host ""
Write-Host "Gotovo." -ForegroundColor Green
Write-Host "U n8n -> Credentials -> Postgres:"
Write-Host "  Host: 172.17.0.1"
Write-Host "  Port: 5432"
Write-Host "  Database: $DbName"
Write-Host "  User: $DbUser"
Write-Host "  Password: $DbPass"
Write-Host "  SSL: disable"
Write-Host ""
Write-Host "Promijeni DbPass (parametar -DbPass ili u skripti) prije pravog rada."