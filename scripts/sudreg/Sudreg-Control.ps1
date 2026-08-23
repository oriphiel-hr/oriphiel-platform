# Kontrola Sudreg unosa: status / stop / wipe
#
# Status (dokle je doslo, je li zavrsilo):
#   pwsh -File .../Sudreg-Control.ps1 -Status
#   pwsh -File .../Sudreg-Control.ps1 -Status -AsJson
#
# Nasilni prekid (graceful - zavrsi trenutni batch):
#   pwsh -File .../Sudreg-Control.ps1 -Stop
# Odmah ubij proces:
#   pwsh -File .../Sudreg-Control.ps1 -Stop -ForceKill
#
# Potpuno obrisi sudreg bazu (+ ponovo kreiraj praznu shemu):
#   pwsh -File .../Sudreg-Control.ps1 -Wipe -Force
#   pwsh -File .../Sudreg-Control.ps1 -Wipe -Force -AlsoClearJsonCache
#
# Ukloni zastarjeli lock (ako je PID mrtav):
#   pwsh -File .../Sudreg-Control.ps1 -ClearStaleLock

[CmdletBinding()]
param(
  [switch]$Status,
  [switch]$Stop,
  [switch]$ForceKill,
  [int]$WaitSec = 120,
  [switch]$Wipe,
  [switch]$Force,
  [switch]$AlsoClearJsonCache,
  [switch]$ClearStaleLock,
  [switch]$AsJson,

  [string]$DataDir = "",
  [string]$SshTarget = "root@186.240.157.80",
  [string]$PgContainer = "oriphiel-postgres",
  [string]$PgDb = "sudreg",
  [string]$PgUser = "oriphiel",
  [switch]$Local
)

$ErrorActionPreference = "Stop"
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
. (Join-Path $scriptDir "SudregPg.ps1")
. (Join-Path $scriptDir "SudregRun.ps1")

$Local = [bool](Test-SudregLocalMode -Local:$Local)
$repoRoot = Get-SudregRepoRoot -ScriptDir $scriptDir
if (-not $DataDir) { $DataDir = Get-SudregDataDir -RepoRoot $repoRoot }
$SchemaFile = Get-SudregSchemaFile -ScriptDir $scriptDir

$modeCount = @($Status, $Stop, $Wipe, $ClearStaleLock) | Where-Object { $_ } | Measure-Object | Select-Object -ExpandProperty Count
if ($modeCount -eq 0) { $Status = $true }
if ($modeCount -gt 1) { throw "Odaberi samo jednu naredbu: -Status | -Stop | -Wipe | -ClearStaleLock" }

if ($ClearStaleLock) {
  $info = Get-SudregLockInfo -DataDir $DataDir
  if (-not $info.Present) {
    Write-Host "Nema lock datoteke." -ForegroundColor Green
    return
  }
  if ($info.Alive -and -not $Force) {
    throw "Lock PID $($info.Lock.pid) jos zivi. Koristi -Stop -ForceKill ili -ClearStaleLock -Force"
  }
  Remove-Item -LiteralPath (Get-SudregLockPath -DataDir $DataDir) -Force
  Remove-Item -LiteralPath (Get-SudregAbortPath -DataDir $DataDir) -Force -ErrorAction SilentlyContinue
  Write-Host "Lock uklonjen." -ForegroundColor Green
  return
}

if ($Stop) {
  $r = Stop-SudregRun -DataDir $DataDir -ForceKill:$ForceKill -WaitSec $WaitSec
  if ($AsJson) { $r | ConvertTo-Json -Depth 6 } else { $r | Format-List }
  return
}

if ($Wipe) {
  Clear-SudregDatabase -DataDir $DataDir -SchemaFile $SchemaFile -PgDb $PgDb -PgUser $PgUser `
    -PgContainer $PgContainer -SshTarget $SshTarget -Local:$Local -Force:$Force -AlsoClearJsonCache:$AlsoClearJsonCache
  return
}

# Status (default)
$report = Get-SudregStatusReport -DataDir $DataDir -PgDb $PgDb -PgUser $PgUser `
  -PgContainer $PgContainer -SshTarget $SshTarget -Local:$Local

if ($AsJson) {
  $report | ConvertTo-Json -Depth 8
  return
}

Write-Host "=== Sudreg status ===" -ForegroundColor Cyan
Write-Host ("checked_at: {0}" -f $report.checked_at)
if ($report.running) {
  Write-Host "STANJE: RADI (unos u tijeku)" -ForegroundColor Yellow
} elseif ($report.finished) {
  Write-Host "STANJE: ZAVRSENO (zadnji run completed)" -ForegroundColor Green
} elseif ($report.progress -and $report.progress.status -eq "aborted") {
  Write-Host "STANJE: PREKINUTO" -ForegroundColor Red
} elseif ($report.progress -and $report.progress.status -eq "failed") {
  Write-Host "STANJE: NEUSPJEH" -ForegroundColor Red
} elseif ($report.progress -and $report.progress.status -eq "idle") {
  Write-Host "STANJE: MIRUJE (nema aktivnog unosa)" -ForegroundColor DarkGray
} else {
  Write-Host "STANJE: NEMA AKTIVNOG UNOSA" -ForegroundColor DarkGray
}

if ($report.abort_requested) {
  Write-Host "abort_requested: DA (ceka kraj batcha ili ForceKill)" -ForegroundColor Magenta
}

if ($report.lock.Present) {
  $l = $report.lock.Lock
  Write-Host ""
  Write-Host "-- lock --" -ForegroundColor DarkCyan
  Write-Host ("  pid={0} alive={1} stale={2}" -f $l.pid, $report.lock.Alive, $report.lock.Stale)
  Write-Host ("  script={0} mode={1}" -f $l.script, $l.mode)
  Write-Host ("  started_at={0} host={1}" -f $l.started_at, $l.host)
}

if ($report.progress) {
  $p = $report.progress
  Write-Host ""
  Write-Host "-- progress --" -ForegroundColor DarkCyan
  Write-Host ("  status={0} phase={1}" -f $p.status, $p.phase)
  Write-Host ("  message={0}" -f $p.message)
  if ($null -ne $p.snapshot_id) { Write-Host ("  snapshot_id={0}" -f $p.snapshot_id) }
  if ($null -ne $p.total) {
    Write-Host ("  done={0}/{1} ({2}%)  ok={3} err={4}" -f $p.done, $p.total, $p.pct, $p.ok, $p.err)
  }
  Write-Host ("  updated_at={0}" -f $p.updated_at)
  if ($p.started_at) { Write-Host ("  started_at={0}" -f $p.started_at) }
  if ($p.finished_at) { Write-Host ("  finished_at={0}" -f $p.finished_at) }
  if ($p.error) { Write-Host ("  error={0}" -f $p.error) -ForegroundColor Red }
}

Write-Host ""
Write-Host "-- baza ($PgDb) --" -ForegroundColor DarkCyan
$db = $report.database
if ($db.error) {
  Write-Host ("  ERROR: {0}" -f $db.error) -ForegroundColor Red
} else {
  Write-Host ("  companies={0} people={1} activities={2} snapshots={3}" -f $db.companies, $db.people, $db.activities, $db.snapshots)
  Write-Host ("  last_imported_snapshot_id={0}" -f $db.last_imported)
  Write-Host ("  max_company_snapshot={0}" -f $db.max_company_snapshot)
  Write-Host ("  last_import ok={0} err={1}" -f $db.last_ok, $db.last_err)
}

Write-Host ""
Write-Host "Naredbe: -Stop | -Stop -ForceKill | -Wipe -Force | -ClearStaleLock" -ForegroundColor DarkGray
