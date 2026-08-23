# Sudreg OAuth token (client_credentials)
# Ekvivalent PHP TokenModel.
#
# Primjeri:
#   & C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Get-SudregToken.ps1
#   $token = & C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Get-SudregToken.ps1
#   & C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Get-SudregToken.ps1 -AsJson
#   & C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Get-SudregToken.ps1 -ForceRefresh
#
# Druga skripta:
#   $token = & C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Get-SudregToken.ps1
#   Invoke-RestMethod -Headers @{ Authorization = "Bearer $token" } ...

[CmdletBinding()]
param(
  [string]$ClientId = "",

  [string]$ClientSecret = "",

  [string]$TokenUrl = "https://sudreg-data.gov.hr/api/oauth/token",

  # Cache u projektnom data/sudreg (ne u user home)
  [string]$CachePath = "",

  # Sekundi buffer prije isteka (kao u PHP: expires_in - 60)
  [int]$ExpiryBufferSec = 60,

  # Forsiraj novi token
  [switch]$ForceRefresh,

  # Vrati cijeli objekt umjesto samo access_token stringa
  [switch]$AsObject,

  [switch]$AsJson
)

$ErrorActionPreference = "Stop"

if (-not $ClientId) {
  $ClientId = if ($env:SUDREG_CLIENT_ID) { $env:SUDREG_CLIENT_ID } else { "UcfrGwvRv3uGkqvYnUMxIA.." }
}
if (-not $ClientSecret) {
  $ClientSecret = if ($env:SUDREG_CLIENT_SECRET) { $env:SUDREG_CLIENT_SECRET } else { "-TX-7q_UfffSEaRmGIP4bA.." }
}

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
# scripts/sudreg -> project root
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..\..")).Path
if (-not $CachePath) {
  $CachePath = Join-Path (Join-Path (Join-Path $repoRoot "data") "sudreg") "token-cache.json"
}

function Read-TokenCache([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  try {
    return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
  } catch {
    return $null
  }
}

function Write-TokenCache([string]$path, $data) {
  $dir = Split-Path -Parent $path
  if ($dir -and -not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
  ($data | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $path -Encoding UTF8
}

function Get-SudregAccessToken {
  if (-not $ForceRefresh) {
    $cached = Read-TokenCache $CachePath
    if ($cached -and $cached.access_token -and $cached.token_expires_at) {
      $expiresAt = [int64]$cached.token_expires_at
      $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
      if ($expiresAt -gt $now) {
        return [pscustomobject]@{
          access_token      = [string]$cached.access_token
          token_type        = $cached.token_type
          expires_in        = $cached.expires_in
          token_expires_at  = $expiresAt
          from_cache        = $true
          cache_path        = $CachePath
        }
      }
    }
  }

  $pair = "{0}:{1}" -f $ClientId, $ClientSecret
  $basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))

  $headers = @{
    Authorization  = "Basic $basic"
    "Content-Type" = "application/x-www-form-urlencoded"
    Accept         = "application/json"
  }

  try {
    $resp = Invoke-RestMethod -Method Post -Uri $TokenUrl -Headers $headers -Body "grant_type=client_credentials"
  } catch {
    $msg = $_.Exception.Message
    if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
      $msg = "$msg | $($_.ErrorDetails.Message)"
    }
    throw "Sudreg token API error: $msg"
  }

  if (-not $resp.access_token) {
    throw "No access_token in response: $($resp | ConvertTo-Json -Compress)"
  }

  $expiresIn = 3600
  if ($resp.expires_in) { $expiresIn = [int]$resp.expires_in }

  $expiresAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + $expiresIn - $ExpiryBufferSec

  $out = [pscustomobject]@{
    access_token     = [string]$resp.access_token
    token_type       = $(if ($resp.token_type) { [string]$resp.token_type } else { "Bearer" })
    expires_in       = $expiresIn
    token_expires_at = $expiresAt
    from_cache       = $false
    cache_path       = $CachePath
  }

  Write-TokenCache -path $CachePath -data ([pscustomobject]@{
      access_token     = $out.access_token
      token_type       = $out.token_type
      expires_in       = $out.expires_in
      token_expires_at = $out.token_expires_at
      saved_at         = (Get-Date).ToString("o")
    })

  return $out
}

$result = Get-SudregAccessToken

if ($AsJson) {
  $result | ConvertTo-Json -Depth 5
} elseif ($AsObject) {
  $result
} else {
  # default: samo token string (za $token = & script.ps1)
  $result.access_token
}
