# Kreira zasebnu Postgres bazu "sudreg" + shemu
# Windows (SSH):
#   powershell -ExecutionPolicy Bypass -File ...\setup-sudreg-db.ps1
# VPS (lokalni docker):
#   pwsh -File /opt/oriphiel-ai/scripts/sudreg/setup-sudreg-db.ps1 -Local

[CmdletBinding()]
param(
  [string]$SshTarget = "root@186.240.157.80",
  [string]$PgContainer = "oriphiel-postgres",
  [string]$PgSuperUser = "oriphiel",
  [string]$PgDb = "sudreg",
  [string]$SchemaFile = "",
  [switch]$Local
)

$ErrorActionPreference = "Stop"

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
. (Join-Path $scriptDir "SudregPg.ps1")
$Local = [bool](Test-SudregLocalMode -Local:$Local)

if (-not $SchemaFile) {
  $SchemaFile = Get-SudregSchemaFile -ScriptDir $scriptDir
}

if (-not (Test-Path -LiteralPath $SchemaFile)) {
  throw "Nedostaje schema: $SchemaFile"
}

Write-Host "1) CREATE DATABASE $PgDb (ako ne postoji)... Local=$Local" -ForegroundColor Cyan
$createDb = @"
SELECT 'CREATE DATABASE $PgDb OWNER $PgSuperUser'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$PgDb')\gexec
"@
Invoke-SudregPsql -Sql $createDb -Database "postgres" -PgUser $PgSuperUser -PgContainer $PgContainer -SshTarget $SshTarget -Local:$Local

Write-Host "2) Primjena sheme na bazu $PgDb ..." -ForegroundColor Cyan
$schema = Get-Content -LiteralPath $SchemaFile -Raw -Encoding UTF8
Invoke-SudregPsql -Sql $schema -Database $PgDb -PgUser $PgSuperUser -PgContainer $PgContainer -SshTarget $SshTarget -Local:$Local

Write-Host "3) Tablice:" -ForegroundColor Cyan
if ($Local) {
  docker exec -i $PgContainer psql -U $PgSuperUser -d $PgDb -c '\dt'
} else {
  ssh $SshTarget "docker exec -i $PgContainer psql -U $PgSuperUser -d $PgDb -c '\dt'"
}

Write-Host ""
Write-Host "GOTOVO. Baza: $PgDb (odvojena od oriphiel)" -ForegroundColor Green
Write-Host "Tablice: snapshots, companies, company_people, company_activities,"
Write-Host "         company_legal_relations, company_financial_reports, promjene, sync_state"
