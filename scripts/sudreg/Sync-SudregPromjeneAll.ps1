# Dohvati /promjene za SVE dostupne snapshotove -> data\sudreg\promjene-<id>.json
# + manifest data\sudreg\promjene-manifest.json
#
# Primjeri:
#   & C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Sync-SudregPromjeneAll.ps1
#   & C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Sync-SudregPromjeneAll.ps1 -SkipExisting
#   & C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Sync-SudregPromjeneAll.ps1 -MaxSnapshots 3 -ProbeOnly
#   & C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Sync-SudregPromjeneAll.ps1 -MbsOnly
#
# Nakon toga usporedi:
#   & C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Compare-SudregPromjene.ps1

[CmdletBinding()]
param(
  [string]$BaseUrl = "https://sudreg-data.gov.hr/api/javni",
  [string]$DataDir = "",
  [string]$TokenScript = "",
  [string]$SnapshotsScript = "",
  [string]$PromjeneScript = "",

  # Ne skidaj ako vec postoji promjene-<id>.json
  [switch]$SkipExisting,

  # Samo X-Total-Count po snapshotu (brzo)
  [switch]$ProbeOnly,

  # Spremi samo unique MBS liste (manji fajlovi)
  [switch]$MbsOnly,

  [ValidateRange(1, 10000)]
  [int]$Limit = 1000,

  # 0 = svi
  [int]$MaxSnapshots = 0,

  [string]$NoDataError = "0",
  [string]$OmitNulls = "1"
)

$ErrorActionPreference = "Stop"

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..\..")).Path
if (-not $DataDir) { $DataDir = Join-Path (Join-Path $repoRoot "data") "sudreg" }
if (-not $TokenScript) { $TokenScript = Join-Path $scriptDir "Get-SudregToken.ps1" }
if (-not $SnapshotsScript) { $SnapshotsScript = Join-Path $scriptDir "Get-SudregSnapshots.ps1" }
if (-not $PromjeneScript) { $PromjeneScript = Join-Path $scriptDir "Get-SudregPromjene.ps1" }

foreach ($p in @($TokenScript, $SnapshotsScript, $PromjeneScript)) {
  if (-not (Test-Path -LiteralPath $p)) { throw "Nedostaje skripta: $p" }
}

if (-not (Test-Path -LiteralPath $DataDir)) {
  New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
}

Write-Host "==> Lista snapshotova" -ForegroundColor Cyan
$snapJson = & $SnapshotsScript -ListOnly -AsJson -NoPrompt
$snapshots = @($snapJson | ConvertFrom-Json)
if ($snapshots.Count -eq 0) { throw "Nema dostupnih snapshotova." }

# Sort: najnoviji prvi (staleness ASC, timestamp DESC) - isto kao Get-SudregSnapshots
$snapshots = @(
  $snapshots | Sort-Object `
    @{ Expression = 'staleness'; Ascending = $true }, `
    @{ Expression = 'timestamp'; Descending = $true }
)

if ($MaxSnapshots -gt 0 -and $snapshots.Count -gt $MaxSnapshots) {
  $snapshots = @($snapshots | Select-Object -First $MaxSnapshots)
}

Write-Host ("Pronadeno snapshotova: {0}" -f $snapshots.Count) -ForegroundColor Green

$manifest = [pscustomobject]@{
  generated_at = (Get-Date).ToString("o")
  base_url     = $BaseUrl
  data_dir     = $DataDir
  probe_only   = [bool]$ProbeOnly
  mbs_only     = [bool]$MbsOnly
  limit        = $Limit
  snapshots    = New-Object System.Collections.Generic.List[object]
}

$ok = 0
$skipped = 0
$failed = 0

foreach ($s in $snapshots) {
  $id = $null
  if ($null -ne $s.id) { $id = [int64]$s.id }
  elseif ($null -ne $s.snapshot_id) { $id = [int64]$s.snapshot_id }
  if ($null -eq $id) {
    Write-Host "Preskacem snapshot bez id: $($s | ConvertTo-Json -Compress)" -ForegroundColor Yellow
    continue
  }

  $suffix = if ($MbsOnly) { "mbs" } elseif ($ProbeOnly) { "probe" } else { "promjene" }
  $outFile = Join-Path $DataDir ("{0}-{1}.json" -f $suffix, $id)

  $entry = [pscustomobject]@{
    snapshot_id     = $id
    timestamp       = $s.timestamp
    available_until = $s.available_until
    staleness       = $s.staleness
    description     = $s.description
    out_file        = $outFile
    status          = "pending"
    total_count     = $null
    fetched_rows    = $null
    mbs_count       = $null
    error           = $null
  }

  if ($SkipExisting -and (Test-Path -LiteralPath $outFile) -and -not $ProbeOnly) {
    Write-Host ("SKIP snapshot {0} (postoji {1})" -f $id, (Split-Path -Leaf $outFile)) -ForegroundColor DarkGray
    $entry.status = "skipped_existing"
    try {
      $existing = Get-Content -LiteralPath $outFile -Raw -Encoding UTF8 | ConvertFrom-Json
      $entry.total_count = $existing.total_count
      $entry.fetched_rows = $existing.fetched_rows
      if ($null -ne $existing.mbs_count) { $entry.mbs_count = $existing.mbs_count }
      elseif ($existing.mbs) { $entry.mbs_count = @($existing.mbs).Count }
      elseif ($existing.rows) { $entry.mbs_count = @($existing.rows).Count }
    } catch {}
    [void]$manifest.snapshots.Add($entry)
    $skipped++
    continue
  }

  Write-Host ""
  Write-Host ("==> Snapshot {0}  staleness={1}  ts={2}" -f $id, $s.staleness, $s.timestamp) -ForegroundColor Cyan

  try {
    $args = @{
      SnapshotId  = $id
      Limit       = $Limit
      NoDataError = $NoDataError
      OmitNulls   = $OmitNulls
      OutFile     = $outFile
      DataDir     = $DataDir
      BaseUrl     = $BaseUrl
      TokenScript = $TokenScript
      SnapshotsScript = $SnapshotsScript
    }

    if ($ProbeOnly) {
      $result = & $PromjeneScript @args -ProbeOnly
    } elseif ($MbsOnly) {
      $result = & $PromjeneScript @args -AllPages -MbsOnly
    } else {
      $result = & $PromjeneScript @args -AllPages
    }

    # Ako skripta vrati objekt (ne samo file)
    if ($result -is [string]) {
      try { $result = $result | ConvertFrom-Json } catch {}
    }

    $entry.status = "ok"
    if ($null -ne $result.total_count) { $entry.total_count = $result.total_count }
    if ($null -ne $result.fetched_rows) { $entry.fetched_rows = $result.fetched_rows }
    if ($null -ne $result.mbs_count) { $entry.mbs_count = $result.mbs_count }
    elseif ($result.mbs) { $entry.mbs_count = @($result.mbs).Count }
    elseif ($result.rows) { $entry.fetched_rows = @($result.rows).Count; $entry.mbs_count = @($result.rows).Count }

    # Probe sprema OutFile samo ako smo ga zadali - Get-SudregPromjene za ProbeOnly ne mora zapisati; zapisemo mi
    if ($ProbeOnly -and -not (Test-Path -LiteralPath $outFile)) {
      ($result | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $outFile -Encoding UTF8
    }

    Write-Host ("OK snapshot {0}: total={1} fetched={2} file={3}" -f `
      $id, $entry.total_count, $entry.fetched_rows, (Split-Path -Leaf $outFile)) -ForegroundColor Green
    $ok++
  } catch {
    $entry.status = "error"
    $entry.error = $_.Exception.Message
    Write-Host ("FAIL snapshot {0}: {1}" -f $id, $entry.error) -ForegroundColor Red
    $failed++
  }

  [void]$manifest.snapshots.Add($entry)
}

$manifest | Add-Member -NotePropertyName summary -NotePropertyValue ([pscustomobject]@{
  ok      = $ok
  skipped = $skipped
  failed  = $failed
  total   = $manifest.snapshots.Count
}) -Force

$manifestFile = Join-Path $DataDir "promjene-manifest.json"
($manifest | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $manifestFile -Encoding UTF8

Write-Host ""
Write-Host ("GOTOVO - ok={0} skipped={1} failed={2}" -f $ok, $skipped, $failed) -ForegroundColor Cyan
Write-Host "Manifest: $manifestFile" -ForegroundColor DarkGray
Write-Host "Usporedi: & $scriptDir\Compare-SudregPromjene.ps1" -ForegroundColor Yellow

$manifest
