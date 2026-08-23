# Deploy Sudreg pipeline na Ollama/Oriphiel VPS (lokalni docker + cron)
# Pokreni NA VPS-u kao root (nakon scp/rsync):
#   bash /opt/oriphiel-ai/scripts/sudreg/vps-install-sudreg.sh
#
# Cilj:
#   /opt/oriphiel-ai/scripts/sudreg  — skripte
#   /opt/oriphiel-ai/data/sudreg     — JSON cache + logovi
#   cron 06:15 Europe/Zagreb         — dnevni Update

set -euo pipefail

ROOT="${SUDREG_ROOT:-/opt/oriphiel-ai}"
SCRIPTS="$ROOT/scripts/sudreg"
DATA="$ROOT/data/sudreg"
LOGS="$DATA/logs"

echo "==> Provjera docker / postgres..."
command -v docker >/dev/null || { echo "docker nije instaliran"; exit 1; }
docker ps --format '{{.Names}}' | grep -qx 'oriphiel-postgres' || {
  echo "Kontejner oriphiel-postgres nije pokrenut."
  docker ps --format 'table {{.Names}}\t{{.Status}}'
  exit 1
}

echo "==> Instalacija PowerShell (pwsh) ako treba..."
if ! command -v pwsh >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y -qq wget apt-transport-https software-properties-common
    # Microsoft package repo (Ubuntu/Debian)
    . /etc/os-release
    wget -q "https://packages.microsoft.com/config/${ID}/${VERSION_ID}/packages-microsoft-prod.deb" -O /tmp/packages-microsoft-prod.deb || \
      wget -q "https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb" -O /tmp/packages-microsoft-prod.deb
    dpkg -i /tmp/packages-microsoft-prod.deb
    apt-get update -qq
    apt-get install -y -qq powershell
  else
    echo "Nema apt-get — instaliraj pwsh rucno: https://learn.microsoft.com/powershell/scripting/install/install-linux"
    exit 1
  fi
fi
pwsh -NoLogo -Command '$PSVersionTable.PSVersion.ToString()'

mkdir -p "$SCRIPTS" "$DATA" "$LOGS"
chmod 755 "$SCRIPTS" "$DATA" "$LOGS"

# Env za token (opcionalno — skripta ima defaulte, ali bolje env)
ENV_FILE="$SCRIPTS/sudreg.env"
if [ ! -f "$ENV_FILE" ]; then
  cat > "$ENV_FILE" <<'EOF'
# Opcijski override OAuth (inace Get-SudregToken.ps1 koristi ugradjene defaulte)
# export SUDREG_CLIENT_ID=...
# export SUDREG_CLIENT_SECRET=...
export SUDREG_LOCAL=1
EOF
  chmod 600 "$ENV_FILE"
  echo "Kreiran $ENV_FILE"
fi

echo "==> Schema / baza sudreg..."
# shellcheck disable=SC1090
set -a; . "$ENV_FILE"; set +a
pwsh -NoProfile -File "$SCRIPTS/setup-sudreg-db.ps1" -Local

WRAPPER="$SCRIPTS/run-sudreg-daily.sh"
cat > "$WRAPPER" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export SUDREG_LOCAL=1
cd "$ROOT"
# shellcheck disable=SC1091
[ -f "$ENV_FILE" ] && set -a && . "$ENV_FILE" && set +a
LOG_DIR="$LOGS"
mkdir -p "\$LOG_DIR"
LOG="\$LOG_DIR/daily-\$(date +%Y%m%d-%H%M%S).log"
{
  echo "=== START \$(date -Iseconds) ==="
  pwsh -NoProfile -File "$SCRIPTS/Run-SudregDaily.ps1"
  echo "=== END \$(date -Iseconds) ==="
} >>"\$LOG" 2>&1
EOF
chmod +x "$WRAPPER"

CRON_LINE="15 6 * * * $WRAPPER"
( crontab -l 2>/dev/null | grep -v 'run-sudreg-daily.sh' || true; echo "$CRON_LINE" ) | crontab -
echo "==> Cron:"
crontab -l | grep sudreg || true

echo ""
echo "GOTOVO."
echo "  Skripte: $SCRIPTS"
echo "  Data:    $DATA"
echo "  Dnevno:  06:15 (server local time) via $WRAPPER"
echo ""
echo "Kontrola:"
echo "  pwsh -File $SCRIPTS/Sudreg-Control.ps1 -Status"
echo "  pwsh -File $SCRIPTS/Sudreg-Control.ps1 -Stop"
echo "  pwsh -File $SCRIPTS/Sudreg-Control.ps1 -Stop -ForceKill"
echo "  pwsh -File $SCRIPTS/Sudreg-Control.ps1 -Wipe -Force"
echo ""
echo "Prvi put (bootstrap — dugo traje):"
echo "  pwsh -NoProfile -File $SCRIPTS/Update-Sudreg.ps1 -FetchPromjeneFirst -SkipExistingPromjene -Local"
echo ""
echo "Ili samo danas u background:"
echo "  nohup $WRAPPER >/dev/null 2>&1 &"
