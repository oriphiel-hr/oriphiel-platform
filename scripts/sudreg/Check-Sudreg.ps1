# Provjera Sudreg unosa: napredak + baza + data dir
#
#   # S Windowsa (SSH do VPS Postgres + lokalni progress ako postoji)
#   powershell -ExecutionPolicy Bypass -File .\Check-Sudreg.ps1
#
#   # Na VPS-u:
#   pwsh -File /opt/oriphiel-ai/scripts/sudreg/Check-Sudreg.ps1 -Local
#
#   # Samo status (isto kao Sudreg-Control -Status):
#   pwsh -File .\Check-Sudreg.ps1 -StatusOnly -Local
#
#   # Detaljna baza (top firme, sync_state, snapshoti):
#   pwsh -File .\Check-Sudreg.ps1 -DbDetail -Local

[CmdletBinding()]
param(
  [switch]$Local,
  [switch]$StatusOnly,
  [switch]$DbDetail,
  [switch]$RunUsefulSql,
  [switch]$AsJson,
  [string]$DataDir = "",
  [string]$SshTarget = "root@186.240.157.80",
  [string]$PgContainer = "oriphiel-postgres",
  [string]$PgDb = "sudreg",
  [string]$PgUser = "oriphiel"
)

$ErrorActionPreference = "Stop"
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
. (Join-Path $scriptDir "SudregPg.ps1")
. (Join-Path $scriptDir "SudregRun.ps1")

$Local = [bool](Test-SudregLocalMode -Local:$Local)
$repoRoot = Get-SudregRepoRoot -ScriptDir $scriptDir
if (-not $DataDir) { $DataDir = Get-SudregDataDir -RepoRoot $repoRoot }

Write-Host "=== Sudreg CHECK ===" -ForegroundColor Cyan
Write-Host ("mode={0} data={1} db={2}" -f ($(if ($Local) { "Local" } else { "SSH" }), $DataDir, $PgDb))
Write-Host ""

# 1) Status / napredak (isto kao Control)
& (Join-Path $scriptDir "Sudreg-Control.ps1") -Status -Local:$Local -DataDir $DataDir `
  -SshTarget $SshTarget -PgContainer $PgContainer -PgDb $PgDb -PgUser $PgUser -AsJson:$AsJson

if ($AsJson -or $StatusOnly) { return }

Write-Host ""
Write-Host "=== PROGRESS FILE (sirovo) ===" -ForegroundColor DarkCyan
$progPath = Get-SudregProgressPath -DataDir $DataDir
$lockPath = Get-SudregLockPath -DataDir $DataDir
$abortPath = Get-SudregAbortPath -DataDir $DataDir
Write-Host ("progress.json: {0}" -f $progPath)
if (Test-Path -LiteralPath $progPath) {
  Get-Content -LiteralPath $progPath -Raw
} else {
  Write-Host "(nema progress.json)"
}
Write-Host ("lock.json: {0}  exists={1}" -f $lockPath, (Test-Path -LiteralPath $lockPath))
Write-Host ("abort: {0}  exists={1}" -f $abortPath, (Test-Path -LiteralPath $abortPath))

Write-Host ""
Write-Host "=== DATA DIR ===" -ForegroundColor DarkCyan
if (Test-Path -LiteralPath $DataDir) {
  $jsonCount = @(Get-ChildItem -LiteralPath $DataDir -Recurse -File -Filter "*.json" -ErrorAction SilentlyContinue).Count
  Write-Host ("data_dir={0}" -f $DataDir)
  Write-Host ("json_files={0}" -f $jsonCount)
  $runDir = Join-Path $DataDir "run"
  $logsDir = Join-Path $DataDir "logs"
  if (Test-Path -LiteralPath $logsDir) {
    $latestLog = Get-ChildItem -LiteralPath $logsDir -File -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending | Select-Object -First 3
    Write-Host "zadnji logovi:"
    foreach ($f in $latestLog) {
      Write-Host ("  {0}  {1:u}  {2} bytes" -f $f.Name, $f.LastWriteTimeUtc, $f.Length)
    }
  }
  if (Test-Path -LiteralPath $runDir) {
    Get-ChildItem -LiteralPath $runDir -File -ErrorAction SilentlyContinue |
      ForEach-Object { Write-Host ("  run/{0}  {1:u}" -f $_.Name, $_.LastWriteTimeUtc) }
  }
} else {
  Write-Host ("(nema data dir: {0})" -f $DataDir)
}

Write-Host ""
Write-Host "=== BAZA — sync_state ===" -ForegroundColor DarkCyan
Invoke-SudregPsql -Local:$Local -SshTarget $SshTarget -PgContainer $PgContainer -PgUser $PgUser -Database $PgDb -Sql @"
SELECT key, left(value, 80) AS value, updated_at
FROM sync_state
ORDER BY key;
"@

Write-Host ""
Write-Host "=== BAZA — snapshoti ===" -ForegroundColor DarkCyan
Invoke-SudregPsql -Local:$Local -SshTarget $SshTarget -PgContainer $PgContainer -PgUser $PgUser -Database $PgDb -Sql @"
SELECT id, timestamp, available_until, imported_at
FROM snapshots
ORDER BY id DESC
LIMIT 10;
"@

if (-not $DbDetail -and -not $RunUsefulSql) {
  Write-Host ""
  Write-Host "Za vise detalja: Check-Sudreg.ps1 -DbDetail -Local" -ForegroundColor DarkGray
  Write-Host "Svi korisni SELECT-ovi: Check-Sudreg.ps1 -RunUsefulSql -Local" -ForegroundColor DarkGray
  Write-Host "Kontrola: Sudreg-Control.ps1 -Status | -Stop | -Wipe -Force" -ForegroundColor DarkGray
  return
}

if ($RunUsefulSql) {
  Write-Host ""
  Write-Host "=== sql/useful-selects.sql ===" -ForegroundColor DarkCyan
  $sqlFile = Join-Path (Join-Path $scriptDir "sql") "useful-selects.sql"
  if (-not (Test-Path -LiteralPath $sqlFile)) { throw "Nedostaje: $sqlFile" }
  $sqlText = Get-Content -LiteralPath $sqlFile -Raw -Encoding UTF8
  # Skip block comments /* ... */ for safer batch run — file has one at end
  Invoke-SudregPsql -Local:$Local -SshTarget $SshTarget -PgContainer $PgContainer -PgUser $PgUser -Database $PgDb -Sql $sqlText
  Write-Host "Gotovo (useful-selects)." -ForegroundColor Green
  if (-not $DbDetail) { return }
}

Write-Host ""
Write-Host "=== BAZA — brojevi po statusu firmi ===" -ForegroundColor DarkCyan
Invoke-SudregPsql -Local:$Local -SshTarget $SshTarget -PgContainer $PgContainer -PgUser $PgUser -Database $PgDb -Sql @"
SELECT coalesce(status,'(null)') AS status, count(*) AS n
FROM companies
GROUP BY status
ORDER BY n DESC
LIMIT 20;
"@

Write-Host ""
Write-Host "=== BAZA — scrape ok/err ===" -ForegroundColor DarkCyan
Invoke-SudregPsql -Local:$Local -SshTarget $SshTarget -PgContainer $PgContainer -PgUser $PgUser -Database $PgDb -Sql @"
SELECT
  count(*) AS companies,
  count(*) FILTER (WHERE scrape_ok IS TRUE) AS scrape_ok,
  count(*) FILTER (WHERE scrape_ok IS FALSE) AS scrape_fail,
  count(*) FILTER (WHERE scrape_ok IS NULL) AS scrape_null,
  count(*) FILTER (WHERE deleted) AS deleted
FROM companies;
"@

Write-Host ""
Write-Host "=== BAZA — zadnje azurirane firme ===" -ForegroundColor DarkCyan
Invoke-SudregPsql -Local:$Local -SshTarget $SshTarget -PgContainer $PgContainer -PgUser $PgUser -Database $PgDb -Sql @"
SELECT mbs, left(coalesce(naziv,''), 40) AS naziv, oib, status, snapshot_id, updated_at
FROM companies
ORDER BY updated_at DESC NULLS LAST
LIMIT 15;
"@

Write-Host ""
Write-Host "=== BAZA — people / activities ===" -ForegroundColor DarkCyan
Invoke-SudregPsql -Local:$Local -SshTarget $SshTarget -PgContainer $PgContainer -PgUser $PgUser -Database $PgDb -Sql @"
SELECT 'company_people' AS what, count(*)::text AS n FROM company_people
UNION ALL SELECT 'company_activities', count(*)::text FROM company_activities
UNION ALL SELECT 'companies', count(*)::text FROM companies
UNION ALL SELECT 'snapshots', count(*)::text FROM snapshots
UNION ALL SELECT 'promjene', count(*)::text FROM promjene;
"@

Write-Host ""
Write-Host "=== BAZA — scrape greške (zadnjih 15) ===" -ForegroundColor DarkCyan
Invoke-SudregPsql -Local:$Local -SshTarget $SshTarget -PgContainer $PgContainer -PgUser $PgUser -Database $PgDb -Sql @"
SELECT mbs, left(coalesce(naziv,''), 35) AS naziv,
       left(coalesce(scrape_error,''), 60) AS scrape_error, updated_at
FROM companies
WHERE scrape_ok IS FALSE
ORDER BY updated_at DESC NULLS LAST
LIMIT 15;
"@

Write-Host ""
Write-Host "=== BAZA — sync_state (ponovno, kratko) ===" -ForegroundColor DarkCyan
Invoke-SudregPsql -Local:$Local -SshTarget $SshTarget -PgContainer $PgContainer -PgUser $PgUser -Database $PgDb -Sql @"
SELECT key, left(value, 60) AS value FROM sync_state ORDER BY key;
"@

Write-Host ""
Write-Host "Vise SQL-ova: sql/useful-selects.sql" -ForegroundColor DarkGray
Write-Host "  docker exec -i oriphiel-postgres psql -U oriphiel -d sudreg -f - < sql/useful-selects.sql" -ForegroundColor DarkGray
Write-Host "Gotovo." -ForegroundColor Green
