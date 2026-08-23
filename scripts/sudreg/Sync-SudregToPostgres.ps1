# Sync Sudreg -> Postgres baza "sudreg" (ODVOJENA od oriphiel)
# Tablice: snapshots, companies, company_people, company_activities, ...
#
# Prvo jednom:
#   powershell -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\setup-sudreg-db.ps1
#
# Test (rucni niz MBS-ova - MaxMbs je lose jer MBS redoslijed nije vezan uz vaznost promjena):
#   & ...\Sync-SudregToPostgres.ps1 -SnapshotId 1292 -MbsFile C:\temp\test-mbs.txt
#
# Puni:
#   & C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Sync-SudregToPostgres.ps1 -LatestSnapshot
#   # ili bolje: Update-Sudreg.ps1

[CmdletBinding()]
param(
  [Nullable[int64]]$SnapshotId = $null,
  [switch]$LatestSnapshot,

  [string]$DataDir = "",
  [string]$PromjeneScript = "",
  [string]$SubjectScript = "",
  [string]$SnapshotsScript = "",

  [string]$MbsFile = "",

  # ZASTARJELO / nepouzdano: prvih N iz liste nije reprezentativan uzorak (MBS nije poredan po vaznosti).
  # Preferiraj -MbsFile s eksplicitnom listom. Ostaje samo za ad-hoc debug.
  [int]$MaxMbs = 0,

  [ValidateRange(1, 100)]
  [int]$BatchSize = 10,

  [double]$MinDelaySec = 0.3,
  [double]$MaxDelaySec = 0.7,

  [switch]$SkipExisting,

  [string]$SshTarget = "root@186.240.157.80",
  [string]$PgContainer = "oriphiel-postgres",
  [string]$PgDb = "sudreg",
  [string]$PgUser = "oriphiel",

  # Na VPS-u: lokalni docker (bez ssh). Auto na Linuxu / SUDREG_LOCAL=1
  [switch]$Local,

  # Parent (Update-Sudreg) vec drzi lock
  [switch]$NoLock,

  [switch]$EnsureSchemaOnly
)

$ErrorActionPreference = "Stop"

# $PSScriptRoot je prazan u default param() vrijednostima
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
. (Join-Path $scriptDir "SudregPg.ps1")
. (Join-Path $scriptDir "SudregRun.ps1")
$Local = [bool](Test-SudregLocalMode -Local:$Local)

# scripts\sudreg -> project root
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..\..")).Path
if (-not $DataDir) { $DataDir = Get-SudregDataDir -RepoRoot $repoRoot }
if (-not $PromjeneScript) { $PromjeneScript = Join-Path $scriptDir "Get-SudregPromjene.ps1" }
if (-not $SubjectScript) { $SubjectScript = Join-Path $scriptDir "Get-SudregSubject.ps1" }
if (-not $SnapshotsScript) { $SnapshotsScript = Join-Path $scriptDir "Get-SudregSnapshots.ps1" }
$SchemaFile = Get-SudregSchemaFile -ScriptDir $scriptDir

function Ensure-DataDir {
  if (-not (Test-Path -LiteralPath $DataDir)) {
    New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
  }
}

function Invoke-VpsPsql {
  param([string]$Sql, [string]$Database = $PgDb)
  Invoke-SudregPsql -Sql $Sql -Database $Database -PgUser $PgUser -PgContainer $PgContainer -SshTarget $SshTarget -Local:$Local
}

function Ensure-SudregDbAndSchema {
  Write-Host "Provjeravam bazu '$PgDb' + shemu... (Local=$Local)" -ForegroundColor Cyan
  $createDb = @"
SELECT 'CREATE DATABASE $PgDb OWNER $PgUser'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$PgDb')\gexec
"@
  Invoke-VpsPsql -Sql $createDb -Database "postgres"
  if (-not (Test-Path -LiteralPath $SchemaFile)) { throw "Nedostaje $SchemaFile" }
  $schema = Get-Content -LiteralPath $SchemaFile -Raw -Encoding UTF8
  Invoke-VpsPsql -Sql $schema -Database $PgDb
}

function Sql-Lit([string]$s) {
  if ($null -eq $s -or $s -eq "") { return "NULL" }
  return ("'" + ($s -replace "'", "''") + "'")
}

function Sql-JsonArray($obj) {
  if ($null -eq $obj) { return "'[]'::jsonb" }
  $json = ($obj | ConvertTo-Json -Depth 8 -Compress)
  if ([string]::IsNullOrWhiteSpace($json)) { return "'[]'::jsonb" }
  $tag = "a" + [guid]::NewGuid().ToString("N").Substring(0, 8)
  return ('$' + $tag + '$' + $json + '$' + $tag + '$::jsonb')
}

function Upsert-SnapshotRow([int64]$SnapId) {
  $metaPath = Join-Path $DataDir ("snapshot-{0}.json" -f $SnapId)
  $current = Join-Path $DataDir "current-snapshot.json"
  $meta = $null
  if (Test-Path -LiteralPath $metaPath) {
    $meta = Get-Content $metaPath -Raw | ConvertFrom-Json
  } elseif (Test-Path -LiteralPath $current) {
    $meta = Get-Content $current -Raw | ConvertFrom-Json
  }

  $ts = "NULL"
  $au = "NULL"
  $st = "NULL"
  $desc = "NULL"
  $sel = "NOW()"
  if ($null -ne $meta) {
    if ($meta.timestamp) { $ts = "$(Sql-Lit ([string]$meta.timestamp))::timestamptz" }
    if ($meta.available_until) { $au = "$(Sql-Lit ([string]$meta.available_until))::timestamptz" }
    if ($null -ne $meta.staleness -and "$($meta.staleness)" -ne "") { $st = [string][int]$meta.staleness }
    if ($meta.description) { $desc = Sql-Lit ([string]$meta.description) }
    if ($meta.selected_at) { $sel = "$(Sql-Lit ([string]$meta.selected_at))::timestamptz" }
  }

  $sql = @"
INSERT INTO snapshots (id, timestamp, available_until, staleness, description, selected_at, imported_at)
VALUES ($SnapId, $ts, $au, $st, $desc, $sel, NOW())
ON CONFLICT (id) DO UPDATE SET
  timestamp = COALESCE(EXCLUDED.timestamp, snapshots.timestamp),
  available_until = COALESCE(EXCLUDED.available_until, snapshots.available_until),
  staleness = COALESCE(EXCLUDED.staleness, snapshots.staleness),
  description = COALESCE(EXCLUDED.description, snapshots.description),
  selected_at = COALESCE(EXCLUDED.selected_at, snapshots.selected_at),
  imported_at = NOW();
"@
  Invoke-VpsPsql -Sql $sql
}

function New-CompanyBundleSql {
  param($Row, [int64]$SnapId)

  $mbs = [string]$Row.mbs
  $mbsLit = Sql-Lit $mbs
  $deleted = if ($Row.deleted -eq $true) { "TRUE" } elseif ($Row.deleted -eq $false) { "FALSE" } else { "FALSE" }
  $ok = if ($Row.ok -eq $false) { "FALSE" } else { "TRUE" }
  $fetched = if ($Row.fetchedAt) { Sql-Lit ([string]$Row.fetchedAt) + "::timestamptz" } else { "NOW()" }

  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine(@"
INSERT INTO companies (
  mbs, oib, euid, status, deleted, deleted_note, nadlezni_sud,
  naziv, naziv_kraci, adresa, email, temeljni_kapital, pravni_oblik, pretezita_djelatnost,
  snapshot_id, source_url, scrape_ok, scrape_error, fetched_at, updated_at
) VALUES (
  $mbsLit,
  $(Sql-Lit $Row.oib),
  $(Sql-Lit $Row.euid),
  $(Sql-Lit $Row.status),
  $deleted,
  $(Sql-Lit $Row.deletedNote),
  $(Sql-Lit $Row.nadlezniSud),
  $(Sql-Lit $Row.naziv),
  $(Sql-Lit $Row.nazivKraci),
  $(Sql-Lit $Row.adresa),
  $(Sql-Lit $Row.email),
  $(Sql-Lit $Row.temeljniKapital),
  $(Sql-Lit $Row.pravniOblik),
  $(Sql-Lit $Row.pretezitaDjelatnost),
  $SnapId,
  $(Sql-Lit $Row.sourceUrl),
  $ok,
  $(Sql-Lit $Row.error),
  $fetched,
  NOW()
)
ON CONFLICT (mbs) DO UPDATE SET
  oib = EXCLUDED.oib,
  euid = EXCLUDED.euid,
  status = EXCLUDED.status,
  deleted = EXCLUDED.deleted,
  deleted_note = EXCLUDED.deleted_note,
  nadlezni_sud = EXCLUDED.nadlezni_sud,
  naziv = EXCLUDED.naziv,
  naziv_kraci = EXCLUDED.naziv_kraci,
  adresa = EXCLUDED.adresa,
  email = EXCLUDED.email,
  temeljni_kapital = EXCLUDED.temeljni_kapital,
  pravni_oblik = EXCLUDED.pravni_oblik,
  pretezita_djelatnost = EXCLUDED.pretezita_djelatnost,
  snapshot_id = EXCLUDED.snapshot_id,
  source_url = EXCLUDED.source_url,
  scrape_ok = EXCLUDED.scrape_ok,
  scrape_error = EXCLUDED.scrape_error,
  fetched_at = EXCLUDED.fetched_at,
  updated_at = NOW();

DELETE FROM company_people WHERE mbs = $mbsLit;
DELETE FROM company_activities WHERE mbs = $mbsLit;
DELETE FROM company_legal_relations WHERE mbs = $mbsLit;
DELETE FROM company_financial_reports WHERE mbs = $mbsLit;
"@)

  $ord = 0
  foreach ($p in @($Row.clanovi)) {
    if ($null -eq $p) { continue }
    $uloge = Sql-JsonArray $p.uloge
    [void]$sb.AppendLine(@"
INSERT INTO company_people (mbs, person_type, ime, oib, tekst, uloge, sort_order)
VALUES ($mbsLit, 'clan', $(Sql-Lit $p.ime), $(Sql-Lit $p.oib), $(Sql-Lit $p.tekst), $uloge, $ord);
"@)
    $ord++
  }
  $ord = 0
  foreach ($p in @($Row.zastupnici)) {
    if ($null -eq $p) { continue }
    $uloge = Sql-JsonArray $p.uloge
    [void]$sb.AppendLine(@"
INSERT INTO company_people (mbs, person_type, ime, oib, tekst, uloge, sort_order)
VALUES ($mbsLit, 'zastupnik', $(Sql-Lit $p.ime), $(Sql-Lit $p.oib), $(Sql-Lit $p.tekst), $uloge, $ord);
"@)
    $ord++
  }

  $ord = 0
  $pret = [string]$Row.pretezitaDjelatnost
  foreach ($a in @($Row.djelatnosti)) {
    if ([string]::IsNullOrWhiteSpace($a)) { continue }
    $isPrimary = if ($pret -and ([string]$a -eq $pret)) { "TRUE" } else { "FALSE" }
    [void]$sb.AppendLine(@"
INSERT INTO company_activities (mbs, activity, is_primary, sort_order)
VALUES ($mbsLit, $(Sql-Lit ([string]$a)), $isPrimary, $ord);
"@)
    $ord++
  }
  if ($pret -and $ord -eq 0) {
    [void]$sb.AppendLine(@"
INSERT INTO company_activities (mbs, activity, is_primary, sort_order)
VALUES ($mbsLit, $(Sql-Lit $pret), TRUE, 0);
"@)
  }

  $ord = 0
  foreach ($t in @($Row.pravniOdnosi)) {
    if ([string]::IsNullOrWhiteSpace($t)) { continue }
    [void]$sb.AppendLine(@"
INSERT INTO company_legal_relations (mbs, tekst, sort_order)
VALUES ($mbsLit, $(Sql-Lit ([string]$t)), $ord);
"@)
    $ord++
  }

  # financijska: headeri pa podaci u ravnom nizu - spremi raw komade kao redove po 4
  $fin = @($Row.financijskaIzvjesca)
  if ($fin.Count -gt 4) {
    $data = @($fin | Where-Object { $_ -notmatch '^(Datum predaje|Godina|Obračunsko|Vrsta izvje|Pregledaj)' })
    for ($i = 0; $i + 3 -lt $data.Count; $i += 4) {
      [void]$sb.AppendLine(@"
INSERT INTO company_financial_reports (mbs, datum_predaje, godina, obracunsko_razdoblje, vrsta_izvjestaja, sort_order)
VALUES ($mbsLit, $(Sql-Lit ([string]$data[$i])), $(Sql-Lit ([string]$data[$i+1])), $(Sql-Lit ([string]$data[$i+2])), $(Sql-Lit ([string]$data[$i+3])), $($i/4));
"@)
    }
  }

  return $sb.ToString()
}

function Get-ExistingMbsSet {
  return Get-SudregExistingMbsSet -PgUser $PgUser -PgDb $PgDb -PgContainer $PgContainer -SshTarget $SshTarget -Local:$Local
}

function Resolve-SnapId {
  if ($null -ne $SnapshotId) { return [int64]$SnapshotId }
  if ($LatestSnapshot) {
    return [int64](& $SnapshotsScript -Latest -IdOnly -NoPrompt)
  }
  $current = Join-Path $DataDir "current-snapshot.json"
  if (Test-Path -LiteralPath $current) {
    $c = Get-Content $current -Raw | ConvertFrom-Json
    if ($null -ne $c.snapshot_id) { return [int64]$c.snapshot_id }
  }
  throw "Zadaj -SnapshotId ili -LatestSnapshot."
}

# --- main ---
Ensure-DataDir
Ensure-SudregDbAndSchema
if ($EnsureSchemaOnly) {
  Write-Host "Schema OK (baza $PgDb)." -ForegroundColor Green
  return
}

$ownsLock = $false
if (-not $NoLock) {
  Enter-SudregRunLock -DataDir $DataDir -ScriptName "Sync-SudregToPostgres" -Mode "sync" | Out-Null
  $ownsLock = $true
}

try {

$snapId = Resolve-SnapId
Write-Host "snapshot_id=$snapId  db=$PgDb" -ForegroundColor Cyan
Set-SudregProgress -DataDir $DataDir -Status "running" -Phase "sync_prepare" `
  -Message ("Priprema MBS liste za snapshot {0}" -f $snapId) -SnapshotId $snapId
Upsert-SnapshotRow -SnapId $snapId

$mbsPath = $MbsFile
if (-not $mbsPath) { $mbsPath = Join-Path $DataDir ("mbs-{0}.txt" -f $snapId) }

if (-not (Test-Path -LiteralPath $mbsPath)) {
  if (Test-SudregAbortRequested -DataDir $DataDir) { throw "ABORT: prekid zatrazen" }
  Write-Host "Dohvacam /promjene -> MBS lista..." -ForegroundColor Cyan
  $mbsJson = Join-Path $DataDir ("mbs-{0}.json" -f $snapId)
  & $PromjeneScript -SnapshotId $snapId -AllPages -MbsOnly -OutFile $mbsJson | Out-Null
  $obj = Get-Content $mbsJson -Raw -Encoding UTF8 | ConvertFrom-Json
  @($obj.mbs) | Set-Content -LiteralPath $mbsPath -Encoding UTF8
  Write-Host "MBS: $(@($obj.mbs).Count) -> $mbsPath" -ForegroundColor Green
} else {
  Write-Host "MBS file: $mbsPath" -ForegroundColor DarkGray
}

$allMbs = @(
  Get-Content $mbsPath |
    ForEach-Object { ("$_").Trim() } |
    Where-Object { $_ -match '\d' } |
    ForEach-Object { ($_ -replace '\D', '').PadLeft(9, '0') } |
    Select-Object -Unique
)

if ($MaxMbs -gt 0 -and $allMbs.Count -gt $MaxMbs) {
  Write-Host "UPOZORENJE: -MaxMbs=$MaxMbs uzima prvih N MBS-ova - to NIJE reprezentativan uzorak (redoslijed nije po vaznosti / postojece izmjene)." -ForegroundColor Red
  $allMbs = @($allMbs | Select-Object -First $MaxMbs)
}

if ($SkipExisting) {
  $existing = Get-ExistingMbsSet
  $before = $allMbs.Count
  $allMbs = @($allMbs | Where-Object { -not $existing.ContainsKey($_) })
  Write-Host "SkipExisting: $before -> $($allMbs.Count)" -ForegroundColor Yellow
}

if ($allMbs.Count -eq 0) {
  Write-Host "Nema MBS-ova za obradu." -ForegroundColor Green
  $stateSql = @"
INSERT INTO sync_state (key, value, updated_at)
VALUES ('last_imported_snapshot_id', '$snapId', NOW())
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW();
"@
  Invoke-VpsPsql -Sql $stateSql
  Write-Host "sync_state.last_imported_snapshot_id=$snapId (prazan sync)" -ForegroundColor DarkGray
  Set-SudregProgress -DataDir $DataDir -Status "running" -Phase "sync_empty" `
    -Message "Nema MBS za obradu" -SnapshotId $snapId -Done 0 -Total 0 -Ok 0 -Err 0
  if ($ownsLock) {
    Exit-SudregRunLock -DataDir $DataDir -FinalStatus "completed" -Message "Prazan sync" `
      -Extra @{ finished_at = (Get-Date).ToString("o"); snapshot_id = $snapId }
  }
  return
}

Write-Host "Scrape+UPSERT: $($allMbs.Count) (batch=$BatchSize)" -ForegroundColor Cyan
$okCount = 0; $errCount = 0; $done = 0; $total = $allMbs.Count
Set-SudregProgress -DataDir $DataDir -Status "running" -Phase "sync_scrape" `
  -Message ("Scrape+UPSERT {0} MBS" -f $total) -SnapshotId $snapId -Done 0 -Total $total -Ok 0 -Err 0

for ($i = 0; $i -lt $total; $i += $BatchSize) {
  if (Test-SudregAbortRequested -DataDir $DataDir) {
    Set-SudregProgress -DataDir $DataDir -Status "stopping" -Phase "sync_abort" `
      -Message ("Abort nakon {0}/{1}" -f $done, $total) -SnapshotId $snapId -Done $done -Total $total -Ok $okCount -Err $errCount
    throw ("ABORT: prekinuto na {0}/{1} (ok={2} err={3})" -f $done, $total, $okCount, $errCount)
  }

  $batch = @($allMbs[$i..([Math]::Min($i + $BatchSize - 1, $total - 1))])
  Write-Host ("[{0}/{1}] scrape..." -f ($i + 1), $total) -ForegroundColor DarkGray
  $results = @(& $SubjectScript -Mbs $batch -MinDelaySec $MinDelaySec -MaxDelaySec $MaxDelaySec)
  if ($null -eq $results) { $results = @() }
  if ($results -isnot [Array]) { $results = @($results) }

  $sql = New-Object System.Text.StringBuilder
  [void]$sql.AppendLine("BEGIN;")
  foreach ($r in $results) {
    [void]$sql.AppendLine((New-CompanyBundleSql -Row $r -SnapId $snapId))
    if ($r.ok -eq $false) { $errCount++ } else { $okCount++ }
    $done++
  }
  [void]$sql.AppendLine("COMMIT;")
  Write-Host ("[{0}/{1}] UPSERT ($PgDb)..." -f $done, $total) -ForegroundColor DarkGray
  Invoke-VpsPsql -Sql ($sql.ToString())

  Set-SudregProgress -DataDir $DataDir -Status "running" -Phase "sync_scrape" `
    -Message ("Scrape+UPSERT {0}/{1}" -f $done, $total) -SnapshotId $snapId -Done $done -Total $total -Ok $okCount -Err $errCount
}

# Zapamti zadnji uspjesno uvezeni snapshot (za Compare-SudregPromjene -Mode Database)
$stateSql = @"
INSERT INTO sync_state (key, value, updated_at)
VALUES ('last_imported_snapshot_id', '$snapId', NOW())
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW();
INSERT INTO sync_state (key, value, updated_at)
VALUES ('last_import_ok_count', '$okCount', NOW())
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW();
INSERT INTO sync_state (key, value, updated_at)
VALUES ('last_import_err_count', '$errCount', NOW())
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW();
"@
Invoke-VpsPsql -Sql $stateSql

Write-Host ""
Write-Host "GOTOVO db=$PgDb snapshot_id=$snapId ok=$okCount err=$errCount total=$done" -ForegroundColor Green
Write-Host "sync_state.last_imported_snapshot_id=$snapId" -ForegroundColor DarkGray
Write-Host "Tablice: companies + company_people + company_activities + ..."
Write-Host "Diff vs baza: & $scriptDir\Compare-SudregPromjene.ps1"

if ($ownsLock) {
  Exit-SudregRunLock -DataDir $DataDir -FinalStatus "completed" `
    -Message ("GOTOVO snapshot={0} ok={1} err={2}" -f $snapId, $okCount, $errCount) `
    -Extra @{
      finished_at = (Get-Date).ToString("o")
      snapshot_id = $snapId
      done        = $done
      total       = $total
      ok          = $okCount
      err         = $errCount
    }
}

} catch {
  $msg = $_.Exception.Message
  $isAbort = $msg -like "ABORT:*"
  if ($ownsLock) {
    $st = if ($isAbort) { "aborted" } else { "failed" }
    Exit-SudregRunLock -DataDir $DataDir -FinalStatus $st -Message $msg `
      -Extra @{ finished_at = (Get-Date).ToString("o"); error = $msg }
  }
  throw
}
