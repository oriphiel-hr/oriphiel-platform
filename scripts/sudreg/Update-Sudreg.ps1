# Glavni tok Sudreg ažuriranja (dnevni model)
#
# PRVI PUT (baza prazna):
#   1) Scrape SVE MBS-ove iz NAJSTARIJEG snapshota (/promjene AllPages - cijela lista)
#   2) Scrape RAZLIKE između najnovijeg i najstarijeg (added MBS)
#   3) Zapamti last_imported = najnoviji
#
# SVAKI DAN (baza ima podatke):
#   1) (opcionalno) skini nove /promjene
#   2) Compare last_imported <-> najnoviji
#   3) Scrape samo RAZLIKU (added MBS)
#   4) last_imported = najnoviji
#
# Primjeri:
#   # prvi put / dnevno (preporuceno)
#   & C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Update-Sudreg.ps1 -FetchPromjeneFirst -SkipExistingPromjene
#
#   # status / stop / wipe:
#   & ...\Sudreg-Control.ps1 -Status
#   & ...\Sudreg-Control.ps1 -Stop
#   & ...\Sudreg-Control.ps1 -Stop -ForceKill
#   & ...\Sudreg-Control.ps1 -Wipe -Force
#
#   # Task Scheduler (svaki dan npr. 6:00):
#   powershell -NoProfile -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Update-Sudreg.ps1 -FetchPromjeneFirst -SkipExistingPromjene
#
[CmdletBinding()]
param(
  [string]$DataDir = "",

  [Nullable[int64]]$SnapshotId = $null,

  [switch]$FetchPromjeneFirst,
  [int]$MaxSnapshots = 0,
  [switch]$SkipExistingPromjene,

  [switch]$CompareOnly,

  [ValidateRange(1, 100)]
  [int]$BatchSize = 10,
  [double]$MinDelaySec = 0.3,
  [double]$MaxDelaySec = 0.7,
  [switch]$SkipExistingCompanies,

  [string]$SshTarget = "root@186.240.157.80",
  [string]$PgContainer = "oriphiel-postgres",
  [string]$PgDb = "sudreg",
  [string]$PgUser = "oriphiel",

  [switch]$Local,

  # Kad Sync zove Update (child) - ne uzimaj drugi lock
  [switch]$NoLock
)

$ErrorActionPreference = "Stop"

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
. (Join-Path $scriptDir "SudregPg.ps1")
. (Join-Path $scriptDir "SudregRun.ps1")
$Local = [bool](Test-SudregLocalMode -Local:$Local)
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..\..")).Path
if (-not $DataDir) { $DataDir = Get-SudregDataDir -RepoRoot $repoRoot }

$SyncAll = Join-Path $scriptDir "Sync-SudregPromjeneAll.ps1"
$Compare = Join-Path $scriptDir "Compare-SudregPromjene.ps1"
$SyncPg = Join-Path $scriptDir "Sync-SudregToPostgres.ps1"
$SnapshotsScript = Join-Path $scriptDir "Get-SudregSnapshots.ps1"

foreach ($p in @($SyncAll, $Compare, $SyncPg, $SnapshotsScript)) {
  if (-not (Test-Path -LiteralPath $p)) { throw "Nedostaje: $p" }
}

if (-not (Test-Path -LiteralPath $DataDir)) {
  New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
}

function Get-LastImportedSnapshotId {
  $v = Invoke-SudregPsqlScalar -Sql "SELECT value FROM sync_state WHERE key = 'last_imported_snapshot_id' LIMIT 1;" `
    -Database $PgDb -PgUser $PgUser -PgContainer $PgContainer -SshTarget $SshTarget -Local:$Local
  if ($v -match '^\d+$') { return [int64]$v }

  $v = Invoke-SudregPsqlScalar -Sql "SELECT MAX(snapshot_id) FROM companies WHERE snapshot_id IS NOT NULL;" `
    -Database $PgDb -PgUser $PgUser -PgContainer $PgContainer -SshTarget $SshTarget -Local:$Local
  if ($v -match '^\d+$') { return [int64]$v }

  $v = Invoke-SudregPsqlScalar -Sql "SELECT COUNT(*) FROM companies;" `
    -Database $PgDb -PgUser $PgUser -PgContainer $PgContainer -SshTarget $SshTarget -Local:$Local
  if ($v -eq "0" -or $v -eq "") { return $null }
  if ($v -match '^\d+$' -and [int64]$v -gt 0) { return -1 }
  return $null
}

function Get-DiskSnapshotIds {
  $ids = New-Object System.Collections.Generic.HashSet[int64]
  Get-ChildItem -LiteralPath $DataDir -Filter "promjene-*.json" -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Name -match '^promjene-(\d+)\.json$') { [void]$ids.Add([int64]$Matches[1]) }
  }
  Get-ChildItem -LiteralPath $DataDir -Filter "mbs-*.json" -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Name -match '^mbs-(\d+)\.json$' -and $_.Name -notlike 'mbs-delta-*') {
      [void]$ids.Add([int64]$Matches[1])
    }
  }
  return @($ids | Sort-Object)
}

function Set-LastImported([int64]$SnapId) {
  $stateSql = @"
INSERT INTO sync_state (key, value, updated_at)
VALUES ('last_imported_snapshot_id', '$SnapId', NOW())
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW();
"@
  Invoke-SudregPsql -Sql $stateSql -Database $PgDb -PgUser $PgUser -PgContainer $PgContainer -SshTarget $SshTarget -Local:$Local | Out-Null
}

function Normalize-MbsList {
  param([string[]]$Raw)
  return @(
    $Raw |
      ForEach-Object { ("$_").Trim() } |
      Where-Object { $_ -match '\d' } |
      ForEach-Object { ($_ -replace '\D', '').PadLeft(9, '0') } |
      Select-Object -Unique
  )
}

function Get-PromjeneScript {
  return (Join-Path $scriptDir "Get-SudregPromjene.ps1")
}

<#
  Kad je baza prazna, baseline MORA koristiti SVE MBS-ove najstarijeg snapshota
  (/promjene AllPages), ne probe.
#>
function Ensure-FullMbsFileForSnapshot {
  param(
    [int64]$SnapId,
    [string]$Label = "baseline"
  )

  $promjeneJson = Join-Path $DataDir ("promjene-{0}.json" -f $SnapId)
  $mbsJson = Join-Path $DataDir ("mbs-{0}.json" -f $SnapId)
  $outTxt = Join-Path $DataDir ("mbs-{0}-{1}-all.txt" -f $SnapId, $Label)
  $promjeneScript = Get-PromjeneScript

  $mbsList = @()

  # 1) puni promjene-<id>.json (rows)
  if (Test-Path -LiteralPath $promjeneJson) {
    $obj = Get-Content -LiteralPath $promjeneJson -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($obj.rows -and @($obj.rows).Count -gt 0) {
      $mbsList = Normalize-MbsList @($obj.rows | ForEach-Object { $_.mbs })
      Write-Host ("MBS iz {0}: {1}" -f (Split-Path -Leaf $promjeneJson), $mbsList.Count) -ForegroundColor DarkGray
    } elseif ($obj.mbs) {
      $mbsList = Normalize-MbsList @($obj.mbs)
    }
  }

  # 2) mbs-<id>.json
  if ($mbsList.Count -eq 0 -and (Test-Path -LiteralPath $mbsJson)) {
    $obj = Get-Content -LiteralPath $mbsJson -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($obj.mbs) {
      $mbsList = Normalize-MbsList @($obj.mbs)
      Write-Host ("MBS iz {0}: {1}" -f (Split-Path -Leaf $mbsJson), $mbsList.Count) -ForegroundColor DarkGray
    }
  }

  # 3) nema potpune liste - skini AllPages
  if ($mbsList.Count -eq 0) {
    Write-Host ("Nema potpune MBS liste za snapshot {0} - skidam /promjene -AllPages -MbsOnly..." -f $SnapId) -ForegroundColor Yellow
    & $promjeneScript -SnapshotId $SnapId -AllPages -MbsOnly -OutFile $mbsJson -DataDir $DataDir | Out-Null
    $obj = Get-Content -LiteralPath $mbsJson -Raw -Encoding UTF8 | ConvertFrom-Json
    $mbsList = Normalize-MbsList @($obj.mbs)
  }

  # Ako JSON postoji ali izgleda kao probe (total_count >> fetched) - ponovo skini
  if ((Test-Path -LiteralPath $promjeneJson) -or (Test-Path -LiteralPath $mbsJson)) {
    $checkPath = if (Test-Path $mbsJson) { $mbsJson } else { $promjeneJson }
    $chk = Get-Content $checkPath -Raw | ConvertFrom-Json
    $total = $chk.total_count
    $have = $mbsList.Count
    if ($null -ne $total -and $total -gt 0 -and $have -gt 0 -and $have -lt ([int64]$total) -and ($have -lt ([Math]::Min([int64]$total, 50)))) {
      Write-Host ("Lista izgleda nepotpuna ({0}/{1}) - ponovno AllPages..." -f $have, $total) -ForegroundColor Yellow
      & $promjeneScript -SnapshotId $SnapId -AllPages -MbsOnly -OutFile $mbsJson -DataDir $DataDir | Out-Null
      $obj = Get-Content -LiteralPath $mbsJson -Raw -Encoding UTF8 | ConvertFrom-Json
      $mbsList = Normalize-MbsList @($obj.mbs)
    }
  }

  if ($mbsList.Count -eq 0) {
    throw "Snapshot ${SnapId}: nema nijednog MBS-a nakon /promjene AllPages."
  }

  $mbsList | Set-Content -LiteralPath $outTxt -Encoding UTF8
  Write-Host ("OK: SVI MBS-ovi snapshota {0}: {1} -> {2}" -f $SnapId, $mbsList.Count, $outTxt) -ForegroundColor Green
  return $outTxt
}

function Invoke-CompanyScrape {
  param(
    [int64]$SnapId,
    [string]$MbsFilePath = ""
  )
  $syncArgs = @{
    SnapshotId  = $SnapId
    DataDir     = $DataDir
    BatchSize   = $BatchSize
    MinDelaySec = $MinDelaySec
    MaxDelaySec = $MaxDelaySec
    SshTarget   = $SshTarget
    PgContainer = $PgContainer
    PgDb        = $PgDb
    PgUser      = $PgUser
    Local       = $Local
  }
  if ($MbsFilePath) { $syncArgs.MbsFile = $MbsFilePath }
  if ($SkipExistingCompanies) { $syncArgs.SkipExisting = $true }
  # Child sync dijeli parent lock + progress
  $syncArgs.NoLock = $true
  & $SyncPg @syncArgs
}

function Invoke-DeltaScrape {
  param(
    [int64]$OldId,
    [int64]$NewId,
    $DiffObject
  )

  $added = @($DiffObject.added_mbs)
  if ($null -eq $added) { $added = @() }

  if ($added.Count -eq 0) {
    Write-Host "Nema added MBS - oznacavam snapshot $NewId kao uvezen." -ForegroundColor Green
    Set-LastImported -SnapId $NewId
    return [pscustomobject]@{
      action      = "no_delta"
      snapshot_id = $NewId
      added_count = 0
      diff        = $DiffObject
    }
  }

  $list = @($added)

  $mbsPath = Join-Path $DataDir ("mbs-delta-{0}-from-{1}.txt" -f $NewId, $OldId)
  $list | Set-Content -LiteralPath $mbsPath -Encoding UTF8
  Write-Host ("Delta scrape: {0} MBS (snapshot {1}) -> {2}" -f $list.Count, $NewId, $mbsPath) -ForegroundColor Cyan

  Invoke-CompanyScrape -SnapId $NewId -MbsFilePath $mbsPath

  return [pscustomobject]@{
    action      = "delta_scrape"
    snapshot_id = $NewId
    from_id     = $OldId
    added_count = $list.Count
    mbs_file    = $mbsPath
    diff        = $DiffObject
  }
}

Write-Host "==> Sudreg Update" -ForegroundColor Cyan

$ownsLock = $false
if (-not $CompareOnly -and -not $NoLock) {
  Enter-SudregRunLock -DataDir $DataDir -ScriptName "Update-Sudreg" -Mode "update" | Out-Null
  $ownsLock = $true
}

try {
if ($FetchPromjeneFirst) {
  if (Test-SudregAbortRequested -DataDir $DataDir) { throw "ABORT: prekid zatrazen prije fetch promjena" }
  Set-SudregProgress -DataDir $DataDir -Status "running" -Phase "fetch_promjene" -Message "Skidam /promjene snapshotove"
  Write-Host "Skidam /promjene za dostupne snapshotove..." -ForegroundColor Cyan
  $fetchArgs = @{ DataDir = $DataDir; SkipExisting = $SkipExistingPromjene }
  if ($MaxSnapshots -gt 0) { $fetchArgs.MaxSnapshots = $MaxSnapshots }
  & $SyncAll @fetchArgs | Out-Null
}

$imported = Get-LastImportedSnapshotId
$diskIds = @(Get-DiskSnapshotIds)

if ($diskIds.Count -eq 0 -and -not $FetchPromjeneFirst) {
  Write-Host "Nema lokalnih promjene/mbs JSON-a - skidam..." -ForegroundColor Yellow
  Set-SudregProgress -DataDir $DataDir -Status "running" -Phase "fetch_promjene" -Message "Nema lokalnih JSON - skidam promjene"
  $fetchArgs = @{ DataDir = $DataDir; SkipExisting = $true }
  if ($MaxSnapshots -gt 0) { $fetchArgs.MaxSnapshots = $MaxSnapshots }
  & $SyncAll @fetchArgs | Out-Null
  $diskIds = @(Get-DiskSnapshotIds)
}

if ($diskIds.Count -eq 0) {
  throw "Nema dostupnih promjene/mbs datoteka u $DataDir. Pokreni Sync-SudregPromjeneAll.ps1"
}

$earliestId = [int64]$diskIds[0]
$latestId = if ($null -ne $SnapshotId) { [int64]$SnapshotId } else { [int64]$diskIds[-1] }
Write-Host ("Disk snapshoti: earliest={0} latest={1} (n={2})" -f $earliestId, $latestId, $diskIds.Count) -ForegroundColor DarkGray

# ========== BAZA PRAZNA: baseline scrape + scrape razlike ==========
if ($null -eq $imported) {
  Write-Host "Baza je prazna - PRVI PUT: scrape svega (najraniji) + scrape razlike (do najnovijeg)." -ForegroundColor Yellow

  if ($CompareOnly) {
    return [pscustomobject]@{
      action  = "bootstrap_needed"
      message = "Baza prazna - pokreni Update-Sudreg.ps1 bez -CompareOnly"
      earliest = $earliestId
      latest   = $latestId
    }
  }

  if (Test-SudregAbortRequested -DataDir $DataDir) { throw "ABORT: prekid zatrazen" }
  Write-Host ("1/2 Scrape SVEGA - SVI MBS-ovi najstarijeg snapshota {0}..." -f $earliestId) -ForegroundColor Cyan
  Set-SudregProgress -DataDir $DataDir -Status "running" -Phase "bootstrap_baseline" `
    -Message ("Scrape SVIH MBS najstarijeg snapshota {0}" -f $earliestId) -SnapshotId $earliestId
  $baselineMbsFile = Ensure-FullMbsFileForSnapshot -SnapId $earliestId -Label "baseline"
  Invoke-CompanyScrape -SnapId $earliestId -MbsFilePath $baselineMbsFile

  if ($earliestId -eq $latestId) {
    Write-Host "Samo jedan snapshot - nema delte. Sutra ce dnevni run raditi razliku." -ForegroundColor Green
    $result = [pscustomobject]@{
      action            = "bootstrap_scrape_only"
      baseline_snapshot = $earliestId
      message           = "Baseline scrape; jedan snapshot - iduci dan = razlika"
    }
    if ($ownsLock) {
      Exit-SudregRunLock -DataDir $DataDir -FinalStatus "completed" -Message "Bootstrap baseline gotov (jedan snapshot)" `
        -Extra @{ finished_at = (Get-Date).ToString("o"); action = $result.action }
    }
    return $result
  }

  if (Test-SudregAbortRequested -DataDir $DataDir) { throw "ABORT: prekid zatrazen nakon baseline" }
  Write-Host ("2/2 Scrape RAZLIKE najnoviji({0}) vs najraniji({1})..." -f $latestId, $earliestId) -ForegroundColor Cyan
  Set-SudregProgress -DataDir $DataDir -Status "running" -Phase "bootstrap_delta" `
    -Message ("Scrape delte {0} -> {1}" -f $earliestId, $latestId) -SnapshotId $latestId
  $diff = & $Compare -OldSnapshotId $earliestId -NewSnapshotId $latestId -DataDir $DataDir
  if ($diff -is [string]) { try { $diff = $diff | ConvertFrom-Json } catch {} }

  $delta = Invoke-DeltaScrape -OldId $earliestId -NewId $latestId -DiffObject $diff

  $result = [pscustomobject]@{
    action            = "bootstrap_then_delta"
    baseline_snapshot = $earliestId
    latest_snapshot   = $latestId
    delta             = $delta
    message           = "Prvi put: scrape svega (najraniji) + scrape razlike do najnovijeg. Iduci danovi: samo razlika."
  }
  if ($ownsLock) {
    Exit-SudregRunLock -DataDir $DataDir -FinalStatus "completed" -Message "Bootstrap + delta gotov" `
      -Extra @{ finished_at = (Get-Date).ToString("o"); action = $result.action; latest_snapshot = $latestId }
  }
  return $result
}

# ========== BAZA IMA PODATKE: dnevni scrape razlike ==========
Write-Host ("Dnevni run (last_imported={0}) - scrape samo razlike do najnovijeg" -f $imported) -ForegroundColor Green
Set-SudregProgress -DataDir $DataDir -Status "running" -Phase "daily_compare" `
  -Message ("Compare last_imported={0} -> latest" -f $imported)

$diff = & $Compare -Mode Database -DataDir $DataDir -SshTarget $SshTarget -PgContainer $PgContainer -PgDb $PgDb -PgUser $PgUser -Local:$Local
if ($diff -is [string]) { try { $diff = $diff | ConvertFrom-Json } catch {} }

if ($CompareOnly) { return $diff }

$newId = $latestId
if ($diff.new -and $diff.new.snapshot_id) { $newId = [int64]$diff.new.snapshot_id }
$oldId = $imported
if ($diff.old -and $diff.old.snapshot_id) { $oldId = [int64]$diff.old.snapshot_id }

if ($diff.already_imported -eq $true -or ([int64]$imported -eq [int64]$newId)) {
  Write-Host "Najnoviji snapshot je vec u bazi - nema scrapea razlike." -ForegroundColor Green
  $result = [pscustomobject]@{
    action      = "up_to_date"
    snapshot_id = $newId
    diff        = $diff
  }
  if ($ownsLock) {
    Exit-SudregRunLock -DataDir $DataDir -FinalStatus "completed" -Message "Vec azurirano - nema posla" `
      -Extra @{ finished_at = (Get-Date).ToString("o"); action = $result.action; snapshot_id = $newId }
  }
  return $result
}

if (Test-SudregAbortRequested -DataDir $DataDir) { throw "ABORT: prekid zatrazen prije delte" }
Set-SudregProgress -DataDir $DataDir -Status "running" -Phase "daily_delta" `
  -Message ("Scrape delte {0} -> {1}" -f $oldId, $newId) -SnapshotId $newId
$delta = Invoke-DeltaScrape -OldId $oldId -NewId $newId -DiffObject $diff
$result = [pscustomobject]@{
  action = "delta_after_existing"
  delta  = $delta
}
if ($ownsLock) {
  Exit-SudregRunLock -DataDir $DataDir -FinalStatus "completed" -Message "Dnevna delta gotova" `
    -Extra @{ finished_at = (Get-Date).ToString("o"); action = $result.action; snapshot_id = $newId }
}
return $result

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
