# Sudreg API: GET /promjene (zadnje promjene nad subjektima)
# https://sudreg-data.gov.hr/api/javni/promjene
#
# Napomena o paging-u (OpenAPI):
#   - offset = 0-based indeks prvog retka (0, 1000, 2000, ...)
#   - limit  = velicina stranice (broj redaka u odgovoru), default API-ja = 1000
#   - ukupan broj redaka = header X-Total-Count
#
# Primjeri:
#   & C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Get-SudregPromjene.ps1 -LatestSnapshot
#   & C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Get-SudregPromjene.ps1 -SnapshotId 12345 -AllPages -AsJson
#   & C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Get-SudregPromjene.ps1 -ProbeOnly
#   & C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Get-SudregPromjene.ps1 -SnapshotId 12345 -Offset 0 -Limit 1000

[CmdletBinding()]
param(
  [string]$BaseUrl = "https://sudreg-data.gov.hr/api/javni",

  [string]$TokenScript = "",

  [string]$SnapshotsScript = "",

  [string]$DataDir = "",

  # Ako nije zadan, cita se iz data\sudreg\current-snapshot.json
  [Nullable[int64]]$SnapshotId = $null,

  [switch]$LatestSnapshot,

  # Prvi poziv samo da procita X-Total-Count (limit=1), bez skidanja svih redova
  [switch]$ProbeOnly,

  # Skini SVE stranice (offset petlja do X-Total-Count)
  [switch]$AllPages,

  # Jedna stranica
  [int]$Offset = 0,

  # Velicina stranice (NIJE 0-based indeks - to je offset)
  [ValidateRange(1, 10000)]
  [int]$Limit = 1000,

  [string]$NoDataError = "0",
  [string]$OmitNulls = "1",

  # Ako prazno i -AllPages/-MbsOnly: automatski data\sudreg\promjene-<snapshot_id>.json
  [string]$OutFile = "",

  [switch]$AsJson,

  # Vrati samo listu MBS (unique)
  [switch]$MbsOnly
)

$ErrorActionPreference = "Stop"

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
# scripts\sudreg -> project root
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..\..")).Path
if (-not $TokenScript) { $TokenScript = Join-Path $scriptDir "Get-SudregToken.ps1" }
if (-not $SnapshotsScript) { $SnapshotsScript = Join-Path $scriptDir "Get-SudregSnapshots.ps1" }
if (-not $DataDir) { $DataDir = Join-Path (Join-Path $repoRoot "data") "sudreg" }

function Get-SudregBearerToken {
  if (-not (Test-Path -LiteralPath $TokenScript)) {
    throw "Nedostaje token skripta: $TokenScript"
  }
  $token = & $TokenScript
  if ([string]::IsNullOrWhiteSpace($token)) {
    throw "Prazan access_token"
  }
  return [string]$token
}

function Resolve-SnapshotId {
  if ($null -ne $SnapshotId) {
    return [int64]$SnapshotId
  }
  if ($LatestSnapshot) {
    if (-not (Test-Path -LiteralPath $SnapshotsScript)) {
      throw "Nedostaje snapshots skripta: $SnapshotsScript"
    }
    $id = & $SnapshotsScript -Latest -IdOnly -NoPrompt
    if (-not $id) { throw "Nije moguce odabrati Latest snapshot_id" }
    return [int64]$id
  }
  $currentFile = Join-Path $DataDir "current-snapshot.json"
  if (Test-Path -LiteralPath $currentFile) {
    try {
      $cached = Get-Content -LiteralPath $currentFile -Raw -Encoding UTF8 | ConvertFrom-Json
      if ($null -ne $cached.snapshot_id) {
        return [int64]$cached.snapshot_id
      }
    } catch {}
  }
  throw "Nema snapshot_id. Koristi -SnapshotId, -LatestSnapshot ili prvo Get-SudregSnapshots.ps1 (sprema u $DataDir)"
}

function Get-ResponseHeaderValue {
  param($Headers, [string]$Name)
  if ($null -eq $Headers) { return $null }
  $v = $Headers[$Name]
  if ($null -eq $v) {
    # neki hostovi drugacije capitaliziraju
    foreach ($k in $Headers.Keys) {
      if ([string]$k -ieq $Name) { $v = $Headers[$k]; break }
    }
  }
  if ($null -eq $v) { return $null }
  # VAZNO: ako je string, NE koristiti [0] (to je prvi CHAR, ASCII npr. 49)
  if ($v -is [System.Array]) {
    if ($v.Length -eq 0) { return $null }
    return [string]$v[0]
  }
  return [string]$v
}

function Invoke-SudregPromjenePage {
  param(
    [string]$Token,
    [int64]$SnapId,
    [int]$PageOffset,
    [int]$PageLimit
  )

  $qs = @(
    "snapshot_id=$SnapId"
    "offset=$PageOffset"
    "limit=$PageLimit"
    "no_data_error=$NoDataError"
    "omit_nulls=$OmitNulls"
  ) -join "&"

  $uri = "$BaseUrl/promjene?$qs"
  $headers = @{
    Authorization  = "Bearer $Token"
    Accept         = "application/json"
    "Content-Type" = "application/json"
  }

  Write-Host "GET promjene snapshot_id=$SnapId offset=$PageOffset limit=$PageLimit" -ForegroundColor DarkGray

  $resp = Invoke-WebRequest -Method Get -Uri $uri -Headers $headers -UseBasicParsing -TimeoutSec 180

  $rows = @()
  if ($resp.Content) {
    $parsed = $resp.Content | ConvertFrom-Json
    if ($null -eq $parsed) {
      $rows = @()
    } elseif ($parsed -is [System.Array]) {
      $rows = @($parsed)
    } else {
      $rows = @($parsed)
    }
  }

  $totalRaw = Get-ResponseHeaderValue $resp.Headers "X-Total-Count"
  $returnedRaw = Get-ResponseHeaderValue $resp.Headers "X-Rows-Returned"
  $usedSnapRaw = Get-ResponseHeaderValue $resp.Headers "X-Snapshot-Id"
  $tsRaw = Get-ResponseHeaderValue $resp.Headers "X-Timestamp"

  $total = $null
  if ($totalRaw -match '^\d+$') { $total = [int64]$totalRaw }
  $returned = $null
  if ($returnedRaw -match '^\d+$') { $returned = [int64]$returnedRaw }
  $usedSnap = $null
  if ($usedSnapRaw -match '^\d+$') { $usedSnap = [int64]$usedSnapRaw }

  return [pscustomobject]@{
    rows            = $rows
    total_count     = $total
    rows_returned   = $(if ($null -ne $returned) { $returned } else { $rows.Count })
    x_snapshot_id   = $usedSnap
    x_timestamp     = $tsRaw
    offset          = $PageOffset
    limit           = $PageLimit
    request_url     = $uri
    raw_headers     = [pscustomobject]@{
      "X-Total-Count"   = $totalRaw
      "X-Rows-Returned" = $returnedRaw
      "X-Snapshot-Id"   = $usedSnapRaw
      "X-Timestamp"     = $tsRaw
    }
  }
}

$token = Get-SudregBearerToken
$snapId = Resolve-SnapshotId
Write-Host "Koristim snapshot_id=$snapId" -ForegroundColor Cyan

# 1) Probe: mali limit da saznamo X-Total-Count
$probeLimit = 1
if ($ProbeOnly -or $AllPages) {
  $probe = Invoke-SudregPromjenePage -Token $token -SnapId $snapId -PageOffset 0 -PageLimit $probeLimit
  $totalCount = $probe.total_count
  if ($null -eq $totalCount) {
    throw "API nije vratio X-Total-Count header. Ne mogu izracunati paging."
  }

  Write-Host "X-Total-Count = $totalCount" -ForegroundColor Green
  Write-Host "X-Snapshot-Id = $($probe.x_snapshot_id)  X-Timestamp = $($probe.x_timestamp)" -ForegroundColor DarkGray
  Write-Host "Raw headers: $($probe.raw_headers | ConvertTo-Json -Compress)" -ForegroundColor DarkGray

  if ($ProbeOnly) {
    $probeOut = [pscustomobject]@{
      snapshot_id    = $snapId
      total_count    = $totalCount
      x_snapshot_id  = $probe.x_snapshot_id
      x_timestamp    = $probe.x_timestamp
      raw_headers    = $probe.raw_headers
      page_size_hint = $Limit
      pages_needed   = [Math]::Ceiling($totalCount / [double]$Limit)
      note           = "promjene = subjekti koji IMAJU zabiljezenu promjenu (delta), NE svih ~300k firmi. offset 0-based; limit = page size. Za sve retke ove tablice: -AllPages"
    }
    if ($AsJson) { $probeOut | ConvertTo-Json -Depth 5 } else { $probeOut }
    return
  }
}

$allRows = New-Object System.Collections.Generic.List[object]
$meta = $null

if ($AllPages) {
  $totalCount = $probe.total_count
  $pages = [Math]::Ceiling($totalCount / [double]$Limit)
  if ($pages -lt 1) { $pages = 1 }

  for ($p = 0; $p -lt $pages; $p++) {
    $off = $p * $Limit
    if ($off -ge $totalCount -and $totalCount -gt 0) { break }

    $page = Invoke-SudregPromjenePage -Token $token -SnapId $snapId -PageOffset $off -PageLimit $Limit
    $meta = $page
    foreach ($r in @($page.rows)) {
      [void]$allRows.Add($r)
    }

    # safety: ako API vrati manje od limit i nismo na kraju po totalu, ipak nastavi dok ne skupimo total ili prazno
    if ($page.rows.Count -eq 0) { break }
  }
} else {
  $page = Invoke-SudregPromjenePage -Token $token -SnapId $snapId -PageOffset $Offset -PageLimit $Limit
  $meta = $page
  foreach ($r in @($page.rows)) {
    [void]$allRows.Add($r)
  }
  if ($null -ne $page.total_count) {
    Write-Host "X-Total-Count = $($page.total_count) (ova stranica: offset=$Offset limit=$Limit, rows=$($page.rows.Count))" -ForegroundColor DarkGray
    Write-Host "Za sve retke dodaj -AllPages" -ForegroundColor Yellow
  }
}

$resultRows = @($allRows.ToArray())

if ($MbsOnly) {
  $mbsList = @(
    $resultRows |
      ForEach-Object { $_.mbs } |
      Where-Object { $null -ne $_ } |
      ForEach-Object { "$_".PadLeft(9, '0') } |
      Select-Object -Unique
  )
  $out = [pscustomobject]@{
    snapshot_id   = $snapId
    x_snapshot_id = $meta.x_snapshot_id
    x_timestamp   = $meta.x_timestamp
    total_count   = $meta.total_count
    fetched_rows  = $resultRows.Count
    mbs_count     = $mbsList.Count
    mbs           = $mbsList
  }
} else {
  $out = [pscustomobject]@{
    snapshot_id   = $snapId
    x_snapshot_id = $meta.x_snapshot_id
    x_timestamp   = $meta.x_timestamp
    total_count   = $meta.total_count
    fetched_rows  = $resultRows.Count
    offset        = $(if ($AllPages) { 0 } else { $Offset })
    limit         = $Limit
    all_pages     = [bool]$AllPages
    rows          = $resultRows
  }
}

# Default OutFile s brojem snapshota
if (-not $OutFile -and ($AllPages -or $MbsOnly)) {
  if (-not (Test-Path -LiteralPath $DataDir)) {
    New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
  }
  $suffix = if ($MbsOnly) { "mbs" } else { "promjene" }
  $OutFile = Join-Path $DataDir ("{0}-{1}.json" -f $suffix, $snapId)
}

if ($OutFile) {
  $dir = Split-Path -Parent $OutFile
  if ($dir -and -not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
  ($out | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $OutFile -Encoding UTF8
  Write-Host "Spremljeno: $OutFile" -ForegroundColor Green
}

if ($AsJson) {
  $out | ConvertTo-Json -Depth 8
} else {
  $out
}
