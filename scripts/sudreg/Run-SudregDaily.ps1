# Dnevni Sudreg update (omotac za Task Scheduler)
# Isti tok kao Update-Sudreg.ps1 -FetchPromjeneFirst -SkipExistingPromjene
#
# Registracija (Admin PowerShell), npr. svaki dan u 06:15:
#   $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Run-SudregDaily.ps1"
#   $trigger = New-ScheduledTaskTrigger -Daily -At 6:15am
#   Register-ScheduledTask -TaskName "SudregDailyUpdate" -Action $action -Trigger $trigger -RunLevel Highest

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
. (Join-Path $scriptDir "SudregPg.ps1")
$repoRoot = Get-SudregRepoRoot -ScriptDir $scriptDir
$logDir = Join-Path (Get-SudregDataDir -RepoRoot $repoRoot) "logs"
if (-not (Test-Path -LiteralPath $logDir)) {
  New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$log = Join-Path $logDir ("daily-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))

try {
  "=== START $(Get-Date -Format o) ===" | Tee-Object -FilePath $log
  & (Join-Path $scriptDir "Update-Sudreg.ps1") -FetchPromjeneFirst -SkipExistingPromjene -Local *>&1 |
    Tee-Object -FilePath $log -Append
  "=== END $(Get-Date -Format o) ===" | Tee-Object -FilePath $log -Append
  exit 0
} catch {
  $_ | Tee-Object -FilePath $log -Append
  exit 1
}
