# Zajednicki Postgres pristup za Sudreg skripte.
# -Local  = docker exec na istom stroju (VPS)
# default = ssh/scp s Windowsa na VPS

function Get-SudregRepoRoot {
  param([string]$ScriptDir)
  return (Resolve-Path (Join-Path $ScriptDir "..\..")).Path
}

function Get-SudregDataDir {
  param([string]$RepoRoot)
  # Cross-platform (Windows + Linux pwsh): avoid "data\sudreg" literal
  return (Join-Path (Join-Path $RepoRoot "data") "sudreg")
}

function Get-SudregSchemaFile {
  param([string]$ScriptDir)
  return (Join-Path (Join-Path $ScriptDir "sql") "sudreg-schema.sql")
}

function Test-SudregLocalMode {
  param([switch]$Local)
  if ($Local) { return $true }
  if ($env:SUDREG_LOCAL -eq "1") { return $true }
  if ($IsLinux -or $IsMacOS) { return $true }
  return $false
}

function Invoke-SudregPsql {
  param(
    [Parameter(Mandatory = $true)][string]$Sql,
    [string]$Database = "sudreg",
    [string]$PgUser = "oriphiel",
    [string]$PgContainer = "oriphiel-postgres",
    [string]$SshTarget = "root@186.240.157.80",
    [switch]$Local,
    [switch]$Quiet
  )

  $useLocal = Test-SudregLocalMode -Local:$Local
  $tmpLocal = Join-Path ([System.IO.Path]::GetTempPath()) ("sudreg-sql-{0}.sql" -f [guid]::NewGuid().ToString("N"))
  try {
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($tmpLocal, $Sql, $utf8)

    if ($useLocal) {
      if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw "docker nije u PATH (Local mode)."
      }
      Get-Content -LiteralPath $tmpLocal -Raw -Encoding UTF8 |
        docker exec -i $PgContainer psql -U $PgUser -d $Database -v ON_ERROR_STOP=1
    } else {
      $remote = "/tmp/sudreg-sync.sql"
      scp $tmpLocal "${SshTarget}:$remote" | Out-Null
      ssh $SshTarget "cat $remote | docker exec -i $PgContainer psql -U $PgUser -d $Database -v ON_ERROR_STOP=1"
    }
  } finally {
    Remove-Item -LiteralPath $tmpLocal -Force -ErrorAction SilentlyContinue
  }
}

function Invoke-SudregPsqlScalar {
  param(
    [Parameter(Mandatory = $true)][string]$Sql,
    [string]$Database = "sudreg",
    [string]$PgUser = "oriphiel",
    [string]$PgContainer = "oriphiel-postgres",
    [string]$SshTarget = "root@186.240.157.80",
    [switch]$Local
  )

  $useLocal = Test-SudregLocalMode -Local:$Local
  if ($useLocal) {
    $out = docker exec -i $PgContainer psql -U $PgUser -d $Database -Atc $Sql 2>$null
  } else {
    $escaped = $Sql -replace '"', '\"'
    $out = ssh -o BatchMode=yes -o ConnectTimeout=8 $SshTarget "docker exec -i $PgContainer psql -U $PgUser -d $Database -Atc `"$escaped`"" 2>$null
  }
  return ("$out").Trim()
}

function Get-SudregExistingMbsSet {
  param(
    [string]$PgUser = "oriphiel",
    [string]$PgDb = "sudreg",
    [string]$PgContainer = "oriphiel-postgres",
    [string]$SshTarget = "root@186.240.157.80",
    [switch]$Local
  )

  $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("sudreg-mbs-{0}.txt" -f [guid]::NewGuid().ToString("N"))
  $useLocal = Test-SudregLocalMode -Local:$Local
  try {
    if ($useLocal) {
      docker exec -i $PgContainer psql -U $PgUser -d $PgDb -Atc "SELECT mbs FROM companies" |
        Set-Content -LiteralPath $tmp -Encoding UTF8
    } else {
      ssh $SshTarget "docker exec -i $PgContainer psql -U $PgUser -d $PgDb -Atc `"SELECT mbs FROM companies`"" |
        Set-Content -LiteralPath $tmp -Encoding UTF8
    }
    $set = @{}
    Get-Content $tmp | ForEach-Object {
      $m = ("$_").Trim()
      if ($m) { $set[$m] = $true }
    }
    return $set
  } finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  }
}
