# Deploy Sudreg UI na Ollama VPS + opcionalno pg_trgm indeksi
#
#   powershell -ExecutionPolicy Bypass -File C:\GIT_PROJEKTI\oriphiel-platform\apps\sudreg-ui\Deploy-SudregUiToVps.ps1
#   powershell -ExecutionPolicy Bypass -File ...\Deploy-SudregUiToVps.ps1 -ApplyTrgm -CreateEnvIfMissing
#   powershell -ExecutionPolicy Bypass -File ...\Deploy-SudregUiToVps.ps1 -RestartOnly

[CmdletBinding()]
param(
  [string]$SshTarget = "root@186.240.157.80",
  [string]$RemoteRoot = "/opt/oriphiel-ai/apps/sudreg-ui",
  [string]$PgContainer = "oriphiel-postgres",
  [string]$PgUser = "oriphiel",
  [string]$PgDb = "sudreg",
  [switch]$ApplyTrgm,
  [switch]$SkipUpload,
  [switch]$RestartOnly,
  [switch]$CreateEnvIfMissing
)

$ErrorActionPreference = "Stop"
$localRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

Write-Host "SSH test: $SshTarget" -ForegroundColor Cyan
ssh -o BatchMode=yes -o ConnectTimeout=15 $SshTarget "echo OK; docker inspect -f '{{.State.Status}}' $PgContainer"

if ($RestartOnly) {
  Write-Host "Restart sudreg-ui..." -ForegroundColor Cyan
  ssh $SshTarget "cd $RemoteRoot && docker compose up -d --build"
  Write-Host "Gotovo. Lokalno: ssh -L 8091:127.0.0.1:8091 $SshTarget zatim http://127.0.0.1:8091" -ForegroundColor Green
  return
}

if (-not $SkipUpload) {
  Write-Host "Sync (tar)..." -ForegroundColor Cyan
  $tar = Join-Path $env:TEMP "sudreg-ui-deploy.tgz"
  if (Test-Path $tar) { Remove-Item $tar -Force }
  Push-Location $localRoot
  try {
    tar -czf $tar `
      requirements.txt Dockerfile docker-compose.yml .env.example README.md `
      app sql Deploy-SudregUiToVps.ps1
  } finally {
    Pop-Location
  }
  ssh $SshTarget "mkdir -p $RemoteRoot"
  scp $tar "${SshTarget}:/tmp/sudreg-ui-deploy.tgz" | Out-Null
  ssh $SshTarget "tar -xzf /tmp/sudreg-ui-deploy.tgz -C $RemoteRoot && rm -f /tmp/sudreg-ui-deploy.tgz"
  Remove-Item $tar -Force -ErrorAction SilentlyContinue
  Write-Host "Upload OK." -ForegroundColor Green
}

if ($CreateEnvIfMissing) {
  Write-Host "Env (ako nedostaje)..." -ForegroundColor Cyan
  $bash = @"
set -e
ROOT='$RemoteRoot'
PG='$PgContainer'
cd "`$ROOT"
if [[ ! -f .env ]]; then
  PW=`$(docker exec "`$PG" printenv POSTGRES_PASSWORD)
  NET=`$(docker inspect -f '{{range `$k,`$v := .NetworkSettings.Networks}}{{`$k}} {{end}}' "`$PG" | awk '{print `$1}')
  UIPW=`$(openssl rand -hex 12)
  SEC=`$(openssl rand -hex 24)
  cat > .env <<EOF
DATABASE_URL=postgresql://oriphiel:`${PW}@oriphiel-postgres:5432/sudreg
CRM_DATABASE_URL=postgresql://oriphiel:`${PW}@oriphiel-postgres:5432/oriphiel_crm
SUDREG_UI_USER=admin
SUDREG_UI_PASSWORD=`${UIPW}
SESSION_SECRET=`${SEC}
HOST=0.0.0.0
PORT=8091
EOF
  if [[ -n "`$NET" ]]; then
    sed -i "s/name: .*/name: `$NET/" docker-compose.yml || true
  fi
  echo "Created .env"
  echo "SUDREG_UI_USER=admin"
  echo "SUDREG_UI_PASSWORD=`$UIPW"
  echo "network=`$NET"
else
  echo ".env already exists"
  grep SUDREG_UI_USER .env || true
fi
"@
  $bash | ssh $SshTarget "bash -s"
}

if ($ApplyTrgm) {
  Write-Host "Primjenjujem pg_trgm indekse (moze potrajati)..." -ForegroundColor Yellow
  scp (Join-Path $localRoot "sql\pg_trgm_indexes.sql") "${SshTarget}:/tmp/pg_trgm_indexes.sql" | Out-Null
  ssh $SshTarget "docker exec -i $PgContainer psql -U $PgUser -d $PgDb -v ON_ERROR_STOP=1 < /tmp/pg_trgm_indexes.sql && rm -f /tmp/pg_trgm_indexes.sql"
  Write-Host "pg_trgm OK." -ForegroundColor Green
}

Write-Host "CRM baza oriphiel_crm + web_finder job shema..." -ForegroundColor Cyan
$crmSetup = @"
set -e
PG='$PgContainer'
PU='$PgUser'
# CREATE DATABASE ako ne postoji
docker exec -i "`$PG" psql -U "`$PU" -d postgres -v ON_ERROR_STOP=1 <<'SQL'
SELECT 'CREATE DATABASE oriphiel_crm'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'oriphiel_crm')\gexec
SQL
docker exec -i "`$PG" psql -U "`$PU" -d oriphiel_crm -v ON_ERROR_STOP=1 < '$RemoteRoot/sql/oriphiel-crm-schema.sql'
docker exec -i "`$PG" psql -U "`$PU" -d oriphiel_crm -v ON_ERROR_STOP=1 < '$RemoteRoot/sql/web-finder-jobs.sql'
docker exec -i "`$PG" psql -U "`$PU" -d oriphiel_crm -v ON_ERROR_STOP=1 < '$RemoteRoot/sql/company-websites-multi.sql'
# CRM_DATABASE_URL u .env ako nedostaje
cd '$RemoteRoot'
if [[ -f .env ]] && ! grep -q '^CRM_DATABASE_URL=' .env; then
  PW=`$(grep '^DATABASE_URL=' .env | sed -E 's#.*://[^:]+:([^@]+)@.*#\1#')
  HOST=`$(grep '^DATABASE_URL=' .env | sed -E 's#.*@([^:/]+).*#\1#')
  echo "CRM_DATABASE_URL=postgresql://oriphiel:`${PW}@`${HOST}:5432/oriphiel_crm" >> .env
  echo "Dodan CRM_DATABASE_URL"
fi
grep CRM_DATABASE_URL .env || true
"@
$crmSetup | ssh $SshTarget "bash -s"

Write-Host "Compose up (UI + web-finder-worker)..." -ForegroundColor Cyan
$up = @"
set -e
cd '$RemoteRoot'
NET=`$(docker inspect -f '{{range `$k,`$v := .NetworkSettings.Networks}}{{`$k}} {{end}}' $PgContainer | awk '{print `$1}')
echo "postgres network=`$NET"
if [[ -f docker-compose.yml && -n "`$NET" ]]; then
  sed -i "s/name: .*/name: `$NET/" docker-compose.yml || true
fi
if [[ ! -f .env ]]; then
  echo "NEDOSTAJE .env — pokreni s -CreateEnvIfMissing" >&2
  exit 1
fi
docker compose up -d --build
docker compose ps
echo "UI: http://127.0.0.1:8091"
echo "Worker: web-finder-worker (docker logs -f web-finder-worker)"
"@
$up | ssh $SshTarget "bash -s"

Write-Host ""
Write-Host "Deploy gotov." -ForegroundColor Green
Write-Host "1) ssh -L 8091:127.0.0.1:8091 $SshTarget"
Write-Host "2) browser http://127.0.0.1:8091  → Masovno"
Write-Host "Lozinka: ssh $SshTarget `"grep SUDREG_UI_PASSWORD $RemoteRoot/.env`""
