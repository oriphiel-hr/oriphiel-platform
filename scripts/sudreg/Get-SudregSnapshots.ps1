# Sudreg API: GET /snapshots + odabir snapshot_id
# Base: https://sudreg-data.gov.hr/api/javni
#
# Primjeri:
#   & C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Get-SudregSnapshots.ps1
#   & C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Get-SudregSnapshots.ps1 -Latest
#   & C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Get-SudregSnapshots.ps1 -SnapshotId 12345
#   & C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Get-SudregSnapshots.ps1 -ListOnly -AsJson
#
# Sprema se u:
#   C:\GIT_PROJEKTI\oriphiel-platform\data\sudreg\snapshot-<id>.json
#   C:\GIT_PROJEKTI\oriphiel-platform\data\sudreg\current-snapshot.json  (pokazivac na zadnji odabir)

[CmdletBinding()]
param(
  [string]$BaseUrl = "https://sudreg-data.gov.hr/api/javni",

  [string]$TokenScript = "",

  # Direktorij za Sudreg podatke
  [string]$DataDir = "",

  # Direktno zadaj snapshot (preskace upit)
  [Nullable[int64]]$SnapshotId = $null,

  # Uzmi najsvjeziji (staleness=1 ili najnoviji timestamp)
  [switch]$Latest,

  # Samo ispisi listu, bez odabira
  [switch]$ListOnly,

  # Ne pitaj interaktivno (ako nije -Latest/-SnapshotId, baci gresku ako ima vise)
  [switch]$NoPrompt,

  [switch]$AsJson,

  # Vrati samo id (broj/string) umjesto objekta
  [switch]$IdOnly,

  [string]$NoDataError = "0",
  [string]$OmitNulls = "1"
)

$ErrorActionPreference = "Stop"

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
# scripts\sudreg -> project root
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..\..")).Path
if (-not $TokenScript) { $TokenScript = Join-Path $scriptDir "Get-SudregToken.ps1" }
if (-not $DataDir) { $DataDir = Join-Path (Join-Path $repoRoot "data") "sudreg" }

if (-not (Test-Path -LiteralPath $TokenScript)) {
  throw "Nedostaje token skripta: $TokenScript"
}

Write-Host "Dohvacam OAuth token..." -ForegroundColor DarkGray
$token = & $TokenScript
if ([string]::IsNullOrWhiteSpace($token)) {
  throw "Prazan access_token iz Get-SudregToken.ps1"
}

$uri = "$BaseUrl/snapshots?no_data_error=$NoDataError&omit_nulls=$OmitNulls"
$headers = @{
  Authorization    = "Bearer $token"
  Accept           = "application/json"
  "Content-Type"   = "application/json"
}

Write-Host "GET $uri" -ForegroundColor DarkGray
try {
  $resp = Invoke-WebRequest -Method Get -Uri $uri -Headers $headers -UseBasicParsing -TimeoutSec 120
} catch {
  $msg = $_.Exception.Message
  if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $msg = "$msg | $($_.ErrorDetails.Message)" }
  throw "snapshots API error: $msg"
}

$snapshots = @()
if ($resp.Content) {
  $parsed = $resp.Content | ConvertFrom-Json
  if ($parsed -is [System.Array]) {
    $snapshots = @($parsed)
  } elseif ($parsed) {
    $snapshots = @($parsed)
  }
}

if ($snapshots.Count -eq 0) {
  throw "API nije vratio nijedan snapshot."
}

# Normaliziraj polja (id / snapshot_id)
$rows = foreach ($s in $snapshots) {
  $id = $null
  if ($null -ne $s.id) { $id = [int64]$s.id }
  elseif ($null -ne $s.snapshot_id) { $id = [int64]$s.snapshot_id }

  [pscustomobject]@{
    id              = $id
    timestamp       = $s.timestamp
    available_until = $s.available_until
    staleness       = $s.staleness
    description     = $s.description
  }
}

# Sort: staleness ASC (1 = najnoviji), pa timestamp DESC
$rows = @($rows | Sort-Object @{ Expression = 'staleness'; Ascending = $true }, @{ Expression = 'timestamp'; Descending = $true })

Write-Host ""
Write-Host ("{0,-12} {1,-22} {2,-22} {3,-10} {4}" -f "id", "timestamp", "available_until", "staleness", "description") -ForegroundColor Cyan
Write-Host ("-" * 90) -ForegroundColor DarkGray
$i = 0
foreach ($r in $rows) {
  $i++
  Write-Host ("{0,-12} {1,-22} {2,-22} {3,-10} {4}" -f $r.id, $r.timestamp, $r.available_until, $r.staleness, $r.description)
}

if ($ListOnly) {
  if ($AsJson) {
    $rows | ConvertTo-Json -Depth 6
  } else {
    $rows
  }
  return
}

$selected = $null

if ($null -ne $SnapshotId) {
  $selected = $rows | Where-Object { $_.id -eq [int64]$SnapshotId } | Select-Object -First 1
  if (-not $selected) { throw "SnapshotId $SnapshotId nije u listi." }
}
elseif ($Latest) {
  $selected = $rows | Where-Object { $_.staleness -eq 1 } | Select-Object -First 1
  if (-not $selected) { $selected = $rows | Select-Object -First 1 }
}
elseif ($rows.Count -eq 1) {
  $selected = $rows[0]
}
elseif ($NoPrompt) {
  throw "Vise snapshotova dostupno. Koristi -Latest, -SnapshotId <id> ili pokreni bez -NoPrompt za odabir."
}
else {
  Write-Host ""
  Write-Host "Odaberi snapshot:" -ForegroundColor Yellow
  for ($n = 0; $n -lt $rows.Count; $n++) {
    $r = $rows[$n]
    $mark = ""
    if ($r.staleness -eq 1) { $mark = " (najnoviji)" }
    Write-Host ("  [{0}] id={1}  timestamp={2}  staleness={3}{4}" -f ($n + 1), $r.id, $r.timestamp, $r.staleness, $mark)
  }
  Write-Host "  [Enter] = najnoviji (staleness=1)" -ForegroundColor DarkGray

  $choice = Read-Host "Broj"
  if ([string]::IsNullOrWhiteSpace($choice)) {
    $selected = $rows | Where-Object { $_.staleness -eq 1 } | Select-Object -First 1
    if (-not $selected) { $selected = $rows[0] }
  } else {
    $idx = 0
    if (-not [int]::TryParse($choice, [ref]$idx)) { throw "Neispravan odabir: $choice" }
    if ($idx -lt 1 -or $idx -gt $rows.Count) { throw "Odabir izvan raspona: $idx" }
    $selected = $rows[$idx - 1]
  }
}

$out = [pscustomobject]@{
  snapshot_id     = $selected.id
  timestamp       = $selected.timestamp
  available_until = $selected.available_until
  staleness       = $selected.staleness
  description     = $selected.description
  selected_at     = (Get-Date).ToString("o")
  base_url        = $BaseUrl
  x_total_count   = $resp.Headers["X-Total-Count"]
  x_rows_returned = $resp.Headers["X-Rows-Returned"]
}

# Spremi odabir: snapshot-<id>.json + current-snapshot.json
if (-not (Test-Path -LiteralPath $DataDir)) {
  New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
}

$snapshotFile = Join-Path $DataDir ("snapshot-{0}.json" -f $out.snapshot_id)
$currentFile = Join-Path $DataDir "current-snapshot.json"
$json = ($out | ConvertTo-Json -Depth 5)
$json | Set-Content -LiteralPath $snapshotFile -Encoding UTF8
$json | Set-Content -LiteralPath $currentFile -Encoding UTF8

Write-Host ""
Write-Host "Odabran snapshot_id=$($out.snapshot_id)" -ForegroundColor Green
Write-Host "  $snapshotFile" -ForegroundColor DarkGray
Write-Host "  $currentFile" -ForegroundColor DarkGray

if ($IdOnly) {
  $out.snapshot_id
} elseif ($AsJson) {
  $out | ConvertTo-Json -Depth 5
} else {
  $out
}
