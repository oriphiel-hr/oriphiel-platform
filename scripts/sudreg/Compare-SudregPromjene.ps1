# Usporedi dvije /promjene datoteke.
#
# Default (-Mode Database):
#   Ako ima uvoza u bazi: OLD = last_imported, NEW = najnoviji JSON
#   Ako je baza prazna:   greska - pokreni Update-Sudreg.ps1 (scrape), ne diff
#   -AllowEmptyDiff:      ipak usporedi najraniji <-> najnoviji
# -Mode Manifest: zadnja dva JSON-a (po vremenu), ignorira bazu
#
# Primjeri:
#   & C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Update-Sudreg.ps1
#   & C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Compare-SudregPromjene.ps1
#   & C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Compare-SudregPromjene.ps1 -Mode Manifest
#   & C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Compare-SudregPromjene.ps1 -AllowEmptyDiff

[CmdletBinding()]
param(
  [string]$DataDir = "",

  # Database (default) | Manifest | Explicit (kad su zadani ID/file)
  [ValidateSet("Database", "Manifest")]
  [string]$Mode = "Database",

  # Kad je baza prazna, dozvoli EarliestLatest diff (inace baci gresku -> Update-Sudreg)
  [switch]$AllowEmptyDiff,

  [Nullable[int64]]$OldSnapshotId = $null,
  [Nullable[int64]]$NewSnapshotId = $null,

  [string]$OldFile = "",
  [string]$NewFile = "",

  # Preferiraj mbs-*.json ako postoji, inace promjene-*.json
  [switch]$PreferMbsFiles,

  [string]$OutFile = "",

  [switch]$AsJson,

  # Ispisi i prvih N primjera MBS
  [int]$SampleSize = 20,

  # Postgres (isti defaulti kao Sync-SudregToPostgres)
  [string]$SshTarget = "root@186.240.157.80",
  [string]$PgContainer = "oriphiel-postgres",
  [string]$PgDb = "sudreg",
  [string]$PgUser = "oriphiel",

  [switch]$Local
)

$ErrorActionPreference = "Stop"

$scriptDirEarly = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
. (Join-Path $scriptDirEarly "SudregPg.ps1")
$Local = [bool](Test-SudregLocalMode -Local:$Local)

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..\..")).Path
if (-not $DataDir) { $DataDir = Get-SudregDataDir -RepoRoot $repoRoot }

function Normalize-Mbs([string]$value) {
  if ([string]::IsNullOrWhiteSpace($value)) { return $null }
  $digits = ($value -replace '\D', '')
  if (-not $digits) { return $null }
  return $digits.PadLeft(9, '0')
}

function Resolve-PromjeneFile {
  param([int64]$SnapshotId)
  $candidates = @()
  if ($PreferMbsFiles) {
    $candidates += (Join-Path $DataDir ("mbs-{0}.json" -f $SnapshotId))
    $candidates += (Join-Path $DataDir ("promjene-{0}.json" -f $SnapshotId))
  } else {
    $candidates += (Join-Path $DataDir ("promjene-{0}.json" -f $SnapshotId))
    $candidates += (Join-Path $DataDir ("mbs-{0}.json" -f $SnapshotId))
  }
  foreach ($c in $candidates) {
    if (Test-Path -LiteralPath $c) { return $c }
  }
  throw "Nema datoteke za snapshot $SnapshotId u $DataDir (trazeno: promjene-/mbs-). Pokreni Sync-SudregPromjeneAll.ps1"
}

function Get-MbsSetFromFile {
  param([string]$Path)

  $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
  $set = New-Object 'System.Collections.Generic.HashSet[string]'
  $meta = [pscustomobject]@{
    snapshot_id   = $raw.snapshot_id
    x_snapshot_id = $raw.x_snapshot_id
    x_timestamp   = $raw.x_timestamp
    total_count   = $raw.total_count
    fetched_rows  = $raw.fetched_rows
    source_file   = $Path
  }

  if ($raw.mbs) {
    foreach ($m in @($raw.mbs)) {
      $n = Normalize-Mbs ([string]$m)
      if ($n) { [void]$set.Add($n) }
    }
  } elseif ($raw.rows) {
    foreach ($r in @($raw.rows)) {
      $n = Normalize-Mbs ([string]$r.mbs)
      if ($n) { [void]$set.Add($n) }
    }
  } else {
    throw "Datoteka nema .mbs ni .rows: $Path"
  }

  return [pscustomobject]@{
    meta = $meta
    set  = $set
  }
}

function Get-AvailableSnapshotFiles {
  $manifestPath = Join-Path $DataDir "promjene-manifest.json"
  $files = @()

  if (Test-Path -LiteralPath $manifestPath) {
    $man = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $ok = @(
      $man.snapshots |
        Where-Object { $_.status -in @('ok', 'skipped_existing') } |
        Sort-Object @{ Expression = 'staleness'; Ascending = $true }, @{ Expression = 'timestamp'; Descending = $true }
    )
    foreach ($e in $ok) {
      $f = $e.out_file
      if (-not $f) { continue }
      if (-not (Test-Path -LiteralPath $f)) {
        try { $f = Resolve-PromjeneFile -SnapshotId ([int64]$e.snapshot_id) } catch { continue }
      }
      $leaf = Split-Path -Leaf $f
      if ($leaf -like 'probe-*') { continue }
      $files += [pscustomobject]@{ id = [int64]$e.snapshot_id; file = $f; timestamp = $e.timestamp; staleness = $e.staleness }
    }
  }

  if ($files.Count -eq 0) {
    $disk = @()
    Get-ChildItem -LiteralPath $DataDir -Filter "promjene-*.json" -ErrorAction SilentlyContinue | ForEach-Object {
      if ($_.Name -match '^promjene-(\d+)\.json$') {
        $disk += [pscustomobject]@{ id = [int64]$Matches[1]; file = $_.FullName; timestamp = $_.LastWriteTime; staleness = 99 }
      }
    }
    if ($PreferMbsFiles -or $disk.Count -eq 0) {
      Get-ChildItem -LiteralPath $DataDir -Filter "mbs-*.json" -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Name -match '^mbs-(\d+)\.json$') {
          $disk += [pscustomobject]@{ id = [int64]$Matches[1]; file = $_.FullName; timestamp = $_.LastWriteTime; staleness = 99 }
        }
      }
    }
    $files = @($disk | Sort-Object id -Descending)
  }

  return @($files | Sort-Object @{ Expression = 'staleness'; Ascending = $true }, @{ Expression = 'id'; Descending = $true })
}

function Pick-EarliestAndLatest {
  $orderedNewestFirst = @(Get-AvailableSnapshotFiles)
  if ($orderedNewestFirst.Count -lt 2) {
    throw "Treba najmanje 2 promjene/mbs datoteke u $DataDir. Pokreni Sync-SudregPromjeneAll.ps1"
  }

  # Najnoviji = najmanji staleness / najveci id; najraniji = obrnuto
  $byIdAsc = @($orderedNewestFirst | Sort-Object id)
  $earliest = $byIdAsc[0]
  $latest = $byIdAsc[-1]

  if ([int64]$earliest.id -eq [int64]$latest.id) {
    throw "Samo jedan jedinstveni snapshot id u datotekama."
  }

  return @{
    New = $latest
    Old = $earliest
    Mode = "EarliestLatest"
  }
}

function Pick-LatestTwoFromManifest {
  $ordered = @(Get-AvailableSnapshotFiles)
  if ($ordered.Count -lt 2) {
    throw "Treba najmanje 2 promjene/mbs datoteke u $DataDir. Pokreni Sync-SudregPromjeneAll.ps1"
  }
  return @{
    New = $ordered[0]
    Old = $ordered[1]
    Mode = "Manifest"
  }
}

function Get-LastImportedSnapshotId {
  $v = Invoke-SudregPsqlScalar -Sql "SELECT value FROM sync_state WHERE key = 'last_imported_snapshot_id' LIMIT 1;" `
    -Database $PgDb -PgUser $PgUser -PgContainer $PgContainer -SshTarget $SshTarget -Local:$Local
  if ($v -match '^\d+$') { return [int64]$v }

  $v = Invoke-SudregPsqlScalar -Sql "SELECT MAX(snapshot_id) FROM companies WHERE snapshot_id IS NOT NULL;" `
    -Database $PgDb -PgUser $PgUser -PgContainer $PgContainer -SshTarget $SshTarget -Local:$Local
  if ($v -match '^\d+$') { return [int64]$v }

  $v = Invoke-SudregPsqlScalar -Sql "SELECT id FROM snapshots WHERE imported_at IS NOT NULL ORDER BY imported_at DESC NULLS LAST, id DESC LIMIT 1;" `
    -Database $PgDb -PgUser $PgUser -PgContainer $PgContainer -SshTarget $SshTarget -Local:$Local
  if ($v -match '^\d+$') { return [int64]$v }

  return $null
}

function Pick-FromDatabase {
  $available = @(Get-AvailableSnapshotFiles)
  if ($available.Count -lt 1) {
    throw "Nema skinutih promjene/mbs datoteka u $DataDir. Pokreni Sync-SudregPromjeneAll.ps1"
  }

  $newSnap = $available[0]
  $importedId = Get-LastImportedSnapshotId

  if ($null -eq $importedId) {
    if (-not $AllowEmptyDiff) {
      $updateScript = Join-Path $scriptDir "Update-Sudreg.ps1"
      throw @"
Baza sudreg je prazna - nema smisla usporedivati snapshotove.
Pokreni scrape koji je vec pripremljen:

  & $updateScript
  # ili:
  & $(Join-Path $scriptDir 'Sync-SudregToPostgres.ps1') -LatestSnapshot

Za informativni diff najraniji<->najnoviji bez baze: -AllowEmptyDiff
"@
    }
    Write-Host "Baza prazna + AllowEmptyDiff - usporedujem NAJRANIJI i NAJNOVIJI snapshot." -ForegroundColor Yellow
    return Pick-EarliestAndLatest
  }

  if ([int64]$newSnap.id -eq [int64]$importedId) {
    Write-Host ("NEW snapshot {0} je vec u bazi - nema novog za usporedbu." -f $newSnap.id) -ForegroundColor Green
    # Ipak usporedi s prethodnim skinutim ako postoji (informativno)
    if ($available.Count -ge 2) {
      return @{ New = $available[0]; Old = $available[1]; AlreadyImported = $true; Mode = "Database" }
    }
    throw "Snapshot $($newSnap.id) je vec uvezen; nema drugog JSON-a za diff."
  }

  $oldFile = $null
  try {
    $oldFile = Resolve-PromjeneFile -SnapshotId $importedId
  } catch {
    throw ("Zadnji uvezeni snapshot u bazi je {0}, ali nema lokalnog promjene/mbs JSON-a. Skinite ga: Sync-SudregPromjeneAll.ps1 ili Get-SudregPromjene.ps1 -SnapshotId {0} -AllPages" -f $importedId)
  }

  return @{
    New = $newSnap
    Old = [pscustomobject]@{ id = $importedId; file = $oldFile; timestamp = $null; staleness = $null }
    AlreadyImported = $false
    Mode = "Database"
  }
}

# Resolve files
$compareMode = $Mode
$alreadyImported = $false

if ($OldFile -and $NewFile) {
  if (-not (Test-Path -LiteralPath $OldFile)) { throw "OldFile ne postoji: $OldFile" }
  if (-not (Test-Path -LiteralPath $NewFile)) { throw "NewFile ne postoji: $NewFile" }
  $compareMode = "Explicit"
} elseif ($null -ne $OldSnapshotId -and $null -ne $NewSnapshotId) {
  $OldFile = Resolve-PromjeneFile -SnapshotId ([int64]$OldSnapshotId)
  $NewFile = Resolve-PromjeneFile -SnapshotId ([int64]$NewSnapshotId)
  $compareMode = "Explicit"
} elseif ($Mode -eq "Manifest") {
  $pair = Pick-LatestTwoFromManifest
  $NewFile = $pair.New.file
  $OldFile = $pair.Old.file
  Write-Host ("Mode=Manifest: NEW={0}  OLD={1}" -f $pair.New.id, $pair.Old.id) -ForegroundColor Cyan
} else {
  $pair = Pick-FromDatabase
  $NewFile = $pair.New.file
  $OldFile = $pair.Old.file
  if ($pair.AlreadyImported) { $alreadyImported = $true }
  $compareMode = if ($pair.Mode) { $pair.Mode } else { "Database" }
  Write-Host ("Mode={0}: NEW={1}  OLD={2}" -f $compareMode, $pair.New.id, $pair.Old.id) -ForegroundColor Cyan
  if ($compareMode -eq "EarliestLatest") {
    Write-Host "Baza prazna: OLD=najraniji skinuti snapshot, NEW=najnoviji." -ForegroundColor DarkGray
  } elseif ($compareMode -eq "Database") {
    Write-Host "OLD = zadnji uvezen u DB." -ForegroundColor DarkGray
  }
  if ($alreadyImported) {
    Write-Host "Napomena: NEW je vec uvezen - diff je informativan, nema pending synca." -ForegroundColor Yellow
  }
}

Write-Host "OLD: $OldFile" -ForegroundColor DarkGray
Write-Host "NEW: $NewFile" -ForegroundColor DarkGray

$old = Get-MbsSetFromFile -Path $OldFile
$new = Get-MbsSetFromFile -Path $NewFile

$added = New-Object System.Collections.Generic.List[string]
$removed = New-Object System.Collections.Generic.List[string]
$common = New-Object System.Collections.Generic.List[string]

foreach ($m in $new.set) {
  if ($old.set.Contains($m)) { [void]$common.Add($m) }
  else { [void]$added.Add($m) }
}
foreach ($m in $old.set) {
  if (-not $new.set.Contains($m)) { [void]$removed.Add($m) }
}

$addedSorted = @($added | Sort-Object)
$removedSorted = @($removed | Sort-Object)
$commonSorted = @($common | Sort-Object)

$result = [pscustomobject]@{
  compared_at       = (Get-Date).ToString("o")
  mode              = $compareMode
  already_imported  = $alreadyImported
  old               = $old.meta
  new               = $new.meta
  counts            = [pscustomobject]@{
    old_mbs     = $old.set.Count
    new_mbs     = $new.set.Count
    added       = $addedSorted.Count
    removed     = $removedSorted.Count
    common      = $commonSorted.Count
  }
  added_mbs         = $addedSorted
  removed_mbs       = $removedSorted
  common_mbs_sample = @($commonSorted | Select-Object -First $SampleSize)
  note              = "Database: OLD=zadnji uvezeni snapshot. EarliestLatest (prazna baza): OLD=najmanji id, NEW=najveci id. Manifest: zadnja 2 po vremenu. added = u NEW a ne u OLD."
}

# Default OutFile
if (-not $OutFile) {
  $oldId = if ($old.meta.snapshot_id) { $old.meta.snapshot_id } else { "old" }
  $newId = if ($new.meta.snapshot_id) { $new.meta.snapshot_id } else { "new" }
  $OutFile = Join-Path $DataDir ("diff-promjene-{0}-to-{1}.json" -f $oldId, $newId)
}

($result | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $OutFile -Encoding UTF8

Write-Host ""
Write-Host ("OLD MBS: {0}   NEW MBS: {1}" -f $result.counts.old_mbs, $result.counts.new_mbs) -ForegroundColor Cyan
Write-Host ("+ added:   {0}" -f $result.counts.added) -ForegroundColor Green
Write-Host ("- removed: {0}" -f $result.counts.removed) -ForegroundColor Yellow
Write-Host ("= common:  {0}" -f $result.counts.common) -ForegroundColor DarkGray
Write-Host "Spremljeno: $OutFile" -ForegroundColor Green

if ($SampleSize -gt 0) {
  if ($addedSorted.Count -gt 0) {
    Write-Host ("Primjeri added ({0}): {1}" -f ([Math]::Min($SampleSize, $addedSorted.Count)), (($addedSorted | Select-Object -First $SampleSize) -join ', ')) -ForegroundColor DarkGray
  }
  if ($removedSorted.Count -gt 0) {
    Write-Host ("Primjeri removed ({0}): {1}" -f ([Math]::Min($SampleSize, $removedSorted.Count)), (($removedSorted | Select-Object -First $SampleSize) -join ', ')) -ForegroundColor DarkGray
  }
}

if ($AsJson) {
  $result | ConvertTo-Json -Depth 6
} else {
  $result
}
