# Lock / progress / abort za Sudreg unos.
# Datoteke u data/sudreg/run/:
#   lock.json      - tko drzi unos
#   progress.json  - detaljan status
#   abort.flag     - nasilni prekid (provjerava se izmedu batcheva)

function Get-SudregRunDir {
  param([string]$DataDir)
  $d = Join-Path $DataDir "run"
  if (-not (Test-Path -LiteralPath $d)) {
    New-Item -ItemType Directory -Path $d -Force | Out-Null
  }
  return $d
}

function Get-SudregLockPath {
  param([string]$DataDir)
  Join-Path (Get-SudregRunDir -DataDir $DataDir) "lock.json"
}

function Get-SudregProgressPath {
  param([string]$DataDir)
  Join-Path (Get-SudregRunDir -DataDir $DataDir) "progress.json"
}

function Get-SudregAbortPath {
  param([string]$DataDir)
  Join-Path (Get-SudregRunDir -DataDir $DataDir) "abort.flag"
}

function Test-SudregProcessAlive {
  param([int]$ProcessId)
  if ($ProcessId -le 0) { return $false }
  try {
    $p = Get-Process -Id $ProcessId -ErrorAction Stop
    return ($null -ne $p)
  } catch {
    return $false
  }
}

function Read-SudregJsonFile {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  try {
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
  } catch {
    return $null
  }
}

function Write-SudregJsonFile {
  param([string]$Path, $Object)
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
  ($Object | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-SudregLockInfo {
  param([string]$DataDir)
  $lock = Read-SudregJsonFile -Path (Get-SudregLockPath -DataDir $DataDir)
  if (-not $lock) {
    return [pscustomobject]@{ Present = $false; Alive = $false; Stale = $false; Lock = $null }
  }
  $pidVal = 0
  if ($lock.pid) { $pidVal = [int]$lock.pid }
  $alive = Test-SudregProcessAlive -ProcessId $pidVal
  return [pscustomobject]@{
    Present = $true
    Alive   = $alive
    Stale   = -not $alive
    Lock    = $lock
  }
}

function Enter-SudregRunLock {
  param(
    [Parameter(Mandatory = $true)][string]$DataDir,
    [string]$ScriptName = "Update-Sudreg",
    [string]$Mode = "import",
    [switch]$Force
  )

  $lockPath = Get-SudregLockPath -DataDir $DataDir
  $info = Get-SudregLockInfo -DataDir $DataDir
  if ($info.Present -and $info.Alive -and -not $Force) {
    $l = $info.Lock
    throw ("Sudreg unos vec traje (pid={0}, script={1}, started={2}). Status: Sudreg-Control.ps1 -Status. Stop: Sudreg-Control.ps1 -Stop" -f $l.pid, $l.script, $l.started_at)
  }
  if ($info.Present -and $info.Stale) {
    Write-Host ("Uklanjam zastarjeli lock (pid={0} nije ziv)." -f $info.Lock.pid) -ForegroundColor Yellow
  }

  Remove-Item -LiteralPath (Get-SudregAbortPath -DataDir $DataDir) -Force -ErrorAction SilentlyContinue

  $lock = [pscustomobject]@{
    pid        = $PID
    script     = $ScriptName
    mode       = $Mode
    started_at = (Get-Date).ToString("o")
    host       = [System.Net.Dns]::GetHostName()
    data_dir   = $DataDir
  }
  Write-SudregJsonFile -Path $lockPath -Object $lock

  Set-SudregProgress -DataDir $DataDir -Status "running" -Phase "starting" -Message "Pokrenuto" `
    -Extra @{ script = $ScriptName; pid = $PID; started_at = $lock.started_at }

  return $lock
}

function Exit-SudregRunLock {
  param(
    [Parameter(Mandatory = $true)][string]$DataDir,
    [string]$FinalStatus = "completed",
    [string]$Message = "Zavrseno",
    [hashtable]$Extra = $null
  )

  # Samo vlasnik (isti PID) ili force cleanup iz Control
  $info = Get-SudregLockInfo -DataDir $DataDir
  if ($info.Present -and $info.Lock.pid -and ([int]$info.Lock.pid -ne $PID)) {
    # child / drugi proces - ne diraj lock
    return
  }

  Set-SudregProgress -DataDir $DataDir -Status $FinalStatus -Phase "done" -Message $Message -Extra $Extra
  Remove-Item -LiteralPath (Get-SudregLockPath -DataDir $DataDir) -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath (Get-SudregAbortPath -DataDir $DataDir) -Force -ErrorAction SilentlyContinue
}

function Set-SudregProgress {
  param(
    [Parameter(Mandatory = $true)][string]$DataDir,
    [ValidateSet("running", "stopping", "completed", "failed", "aborted", "idle")]
    [string]$Status = "running",
    [string]$Phase = "",
    [string]$Message = "",
    [Nullable[int64]]$SnapshotId = $null,
    [Nullable[int]]$Done = $null,
    [Nullable[int]]$Total = $null,
    [Nullable[int]]$Ok = $null,
    [Nullable[int]]$Err = $null,
    [hashtable]$Extra = $null
  )

  $path = Get-SudregProgressPath -DataDir $DataDir
  $prev = Read-SudregJsonFile -Path $path
  if (-not $prev) { $prev = [pscustomobject]@{} }

  $ht = @{}
  foreach ($p in $prev.PSObject.Properties) { $ht[$p.Name] = $p.Value }

  $ht["status"] = $Status
  $ht["updated_at"] = (Get-Date).ToString("o")
  if ($Phase) { $ht["phase"] = $Phase }
  if ($Message) { $ht["message"] = $Message }
  if ($null -ne $SnapshotId) { $ht["snapshot_id"] = [int64]$SnapshotId }
  if ($null -ne $Done) { $ht["done"] = [int]$Done }
  if ($null -ne $Total) { $ht["total"] = [int]$Total }
  if ($null -ne $Ok) { $ht["ok"] = [int]$Ok }
  if ($null -ne $Err) { $ht["err"] = [int]$Err }
  if ($null -ne $Done -and $null -ne $Total -and [int]$Total -gt 0) {
    $ht["pct"] = [Math]::Round(100.0 * [int]$Done / [int]$Total, 1)
  }
  if ($Extra) {
    foreach ($k in $Extra.Keys) { $ht[$k] = $Extra[$k] }
  }

  Write-SudregJsonFile -Path $path -Object ([pscustomobject]$ht)
}

function Test-SudregAbortRequested {
  param([string]$DataDir)
  return (Test-Path -LiteralPath (Get-SudregAbortPath -DataDir $DataDir))
}

function Request-SudregAbort {
  param([string]$DataDir)
  $p = Get-SudregAbortPath -DataDir $DataDir
  "abort requested at $(Get-Date -Format o)" | Set-Content -LiteralPath $p -Encoding UTF8
  Set-SudregProgress -DataDir $DataDir -Status "stopping" -Phase "abort_requested" -Message "Zatrazen nasilni prekid - ceka se kraj trenutnog batcha"
}

function Stop-SudregRun {
  param(
    [Parameter(Mandatory = $true)][string]$DataDir,
    [switch]$ForceKill,
    [int]$WaitSec = 120
  )

  $info = Get-SudregLockInfo -DataDir $DataDir
  if (-not $info.Present) {
    Write-Host "Nema aktivnog locka - unos ne traje." -ForegroundColor Green
    Remove-Item -LiteralPath (Get-SudregAbortPath -DataDir $DataDir) -Force -ErrorAction SilentlyContinue
    return [pscustomobject]@{ action = "none"; message = "nema locka" }
  }

  Request-SudregAbort -DataDir $DataDir
  $targetPid = [int]$info.Lock.pid
  Write-Host ("Abort zatrazen za pid={0}. Cekam do {1}s da se sam zavrsi..." -f $targetPid, $WaitSec) -ForegroundColor Yellow

  $deadline = (Get-Date).AddSeconds($WaitSec)
  while ((Get-Date) -lt $deadline) {
    if (-not (Test-SudregProcessAlive -ProcessId $targetPid)) { break }
    Start-Sleep -Seconds 2
  }

  if (Test-SudregProcessAlive -ProcessId $targetPid) {
    if (-not $ForceKill) {
      Write-Host "Proces jos radi. Ponovi s -ForceKill da ubijes PID." -ForegroundColor Red
      return [pscustomobject]@{ action = "abort_pending"; pid = $targetPid; alive = $true }
    }
    Write-Host ("ForceKill pid={0}..." -f $targetPid) -ForegroundColor Red
    try {
      Stop-Process -Id $targetPid -Force -ErrorAction Stop
    } catch {
      Write-Host ("Stop-Process: {0}" -f $_.Exception.Message) -ForegroundColor Red
    }
    Start-Sleep -Seconds 1
  }

  Remove-Item -LiteralPath (Get-SudregLockPath -DataDir $DataDir) -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath (Get-SudregAbortPath -DataDir $DataDir) -Force -ErrorAction SilentlyContinue
  Set-SudregProgress -DataDir $DataDir -Status "aborted" -Phase "stopped" -Message "Nasilno prekinuto" `
    -Extra @{ stopped_at = (Get-Date).ToString("o"); stopped_pid = $targetPid }

  return [pscustomobject]@{ action = "stopped"; pid = $targetPid; force = [bool]$ForceKill }
}

function Get-SudregStatusReport {
  param(
    [Parameter(Mandatory = $true)][string]$DataDir,
    [string]$PgDb = "sudreg",
    [string]$PgUser = "oriphiel",
    [string]$PgContainer = "oriphiel-postgres",
    [string]$SshTarget = "root@186.240.157.80",
    [switch]$Local
  )

  $lockInfo = Get-SudregLockInfo -DataDir $DataDir
  $progress = Read-SudregJsonFile -Path (Get-SudregProgressPath -DataDir $DataDir)
  $abort = Test-SudregAbortRequested -DataDir $DataDir

  $db = [ordered]@{}
  try {
    $db.companies = Invoke-SudregPsqlScalar -Sql "SELECT COUNT(*) FROM companies;" -Database $PgDb -PgUser $PgUser -PgContainer $PgContainer -SshTarget $SshTarget -Local:$Local
    $db.people = Invoke-SudregPsqlScalar -Sql "SELECT COUNT(*) FROM company_people;" -Database $PgDb -PgUser $PgUser -PgContainer $PgContainer -SshTarget $SshTarget -Local:$Local
    $db.activities = Invoke-SudregPsqlScalar -Sql "SELECT COUNT(*) FROM company_activities;" -Database $PgDb -PgUser $PgUser -PgContainer $PgContainer -SshTarget $SshTarget -Local:$Local
    $db.snapshots = Invoke-SudregPsqlScalar -Sql "SELECT COUNT(*) FROM snapshots;" -Database $PgDb -PgUser $PgUser -PgContainer $PgContainer -SshTarget $SshTarget -Local:$Local
    $db.last_imported = Invoke-SudregPsqlScalar -Sql "SELECT value FROM sync_state WHERE key = 'last_imported_snapshot_id' LIMIT 1;" -Database $PgDb -PgUser $PgUser -PgContainer $PgContainer -SshTarget $SshTarget -Local:$Local
    $db.last_ok = Invoke-SudregPsqlScalar -Sql "SELECT value FROM sync_state WHERE key = 'last_import_ok_count' LIMIT 1;" -Database $PgDb -PgUser $PgUser -PgContainer $PgContainer -SshTarget $SshTarget -Local:$Local
    $db.last_err = Invoke-SudregPsqlScalar -Sql "SELECT value FROM sync_state WHERE key = 'last_import_err_count' LIMIT 1;" -Database $PgDb -PgUser $PgUser -PgContainer $PgContainer -SshTarget $SshTarget -Local:$Local
    $db.max_company_snapshot = Invoke-SudregPsqlScalar -Sql "SELECT COALESCE(MAX(snapshot_id)::text,'') FROM companies;" -Database $PgDb -PgUser $PgUser -PgContainer $PgContainer -SshTarget $SshTarget -Local:$Local
  } catch {
    $db.error = $_.Exception.Message
  }

  $finished = $false
  $running = $false
  if ($lockInfo.Alive) {
    $running = $true
  } elseif ($progress -and $progress.status -in @("completed", "failed", "aborted", "idle")) {
    $finished = ($progress.status -eq "completed")
  } elseif (-not $lockInfo.Present) {
    if ($progress -and $progress.status -eq "completed") { $finished = $true }
  }

  return [pscustomobject]@{
    running          = $running
    finished         = $finished
    abort_requested  = $abort
    lock             = $lockInfo
    progress         = $progress
    database         = [pscustomobject]$db
    checked_at       = (Get-Date).ToString("o")
  }
}

function Clear-SudregDatabase {
  param(
    [Parameter(Mandatory = $true)][string]$DataDir,
    [Parameter(Mandatory = $true)][string]$SchemaFile,
    [string]$PgDb = "sudreg",
    [string]$PgUser = "oriphiel",
    [string]$PgContainer = "oriphiel-postgres",
    [string]$SshTarget = "root@186.240.157.80",
    [switch]$Local,
    [switch]$Force,
    [switch]$AlsoClearJsonCache
  )

  if (-not $Force) {
    throw "Brisanje baze zahtijeva -Force (npr. Sudreg-Control.ps1 -Wipe -Force)."
  }
  if (-not (Test-Path -LiteralPath $SchemaFile)) {
    throw "Nedostaje schema: $SchemaFile"
  }

  $info = Get-SudregLockInfo -DataDir $DataDir
  if ($info.Alive) {
    throw "Unos jos traje (pid=$($info.Lock.pid)). Prvo: Sudreg-Control.ps1 -Stop -ForceKill"
  }

  Write-Host "DROP DATABASE $PgDb ..." -ForegroundColor Red
  $sql = @"
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$PgDb' AND pid <> pg_backend_pid();
DROP DATABASE IF EXISTS $PgDb;
"@
  Invoke-SudregPsql -Sql $sql -Database "postgres" -PgUser $PgUser -PgContainer $PgContainer -SshTarget $SshTarget -Local:$Local

  Write-Host "CREATE DATABASE $PgDb ..." -ForegroundColor Cyan
  Invoke-SudregPsql -Sql "CREATE DATABASE $PgDb OWNER $PgUser;" -Database "postgres" -PgUser $PgUser -PgContainer $PgContainer -SshTarget $SshTarget -Local:$Local

  $schema = Get-Content -LiteralPath $SchemaFile -Raw -Encoding UTF8
  Invoke-SudregPsql -Sql $schema -Database $PgDb -PgUser $PgUser -PgContainer $PgContainer -SshTarget $SshTarget -Local:$Local

  Remove-Item -LiteralPath (Get-SudregLockPath -DataDir $DataDir) -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath (Get-SudregAbortPath -DataDir $DataDir) -Force -ErrorAction SilentlyContinue
  Set-SudregProgress -DataDir $DataDir -Status "idle" -Phase "wiped" -Message "Baza obrisana i shema ponovno kreirana" `
    -Extra @{ wiped_at = (Get-Date).ToString("o"); done = 0; total = 0; ok = 0; err = 0 }

  if ($AlsoClearJsonCache) {
    Write-Host "Brisem JSON cache u $DataDir (ostavljam run/ i logs/)..." -ForegroundColor Yellow
    Get-ChildItem -LiteralPath $DataDir -File | ForEach-Object {
      Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
    }
    Get-ChildItem -LiteralPath $DataDir -Directory | Where-Object { $_.Name -notin @("run", "logs") } | ForEach-Object {
      Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  Write-Host "Baza $PgDb je prazna (shema OK)." -ForegroundColor Green
}
