#!/usr/bin/env bash
# Ravnopar VPS — poveži Umami analitiku s /admin panelom
#
# Radi:
#   1) Login u Umami → novi API token
#   2) Pronađe Website ID za ravnopar.com
#   3) Testira stats API (sprječava 400 grešku u adminu)
#   4) Upiše backend/.env + frontend env
#   5) Restartira PM2 (API + web)
#
# Korištenje (na VPS-u kao root):
#   cd /var/www/Render/ravnopar
#   UMAMI_USER=admin UMAMI_PASS='tvoja-lozinka' bash scripts/vps-fix-umami-analytics.sh
#
# ili interaktivno (pita lozinku):
#   bash scripts/vps-fix-umami-analytics.sh
#
set -euo pipefail

clean_var() {
  printf '%s' "$1" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

APP=/var/www/Render/ravnopar
BE="$APP/backend"
FE="$APP/frontend-next"
UMAMI_BASE="$(clean_var "${UMAMI_BASE_URL:-https://analytics.ravnopar.com}")"
UMAMI_BASE="${UMAMI_BASE%/}"
SITE_DOMAIN="$(clean_var "${UMAMI_SITE_DOMAIN:-ravnopar.com}")"
SITE_LABEL="$(clean_var "${UMAMI_SITE_LABEL:-ravnopar.com}")"
# Known production website — used when auto-detect fails over non-interactive SSH.
DEFAULT_WEBSITE_ID="$(clean_var "${UMAMI_DEFAULT_WEBSITE_ID:-0c0daf08-e152-4f26-93f4-1a01add4c12c}")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}==>${NC} $*"; }
warn()  { echo -e "${YELLOW}!!${NC} $*"; }
fail()  { echo -e "${RED}ERR${NC} $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Nedostaje naredba: $1"
}

ensure_env_line() {
  local file="$1" key="$2" value="$3"
  python3 - "$file" "$key" "$value" <<'PY'
import sys
from pathlib import Path

path, key, value = sys.argv[1], sys.argv[2], sys.argv[3]
p = Path(path)
lines = p.read_text(encoding="utf-8").splitlines() if p.exists() else []
out, found = [], False
for line in lines:
    if line.startswith(key + "="):
        out.append(f"{key}={value}")
        found = True
    else:
        out.append(line)
if not found:
    out.append(f"{key}={value}")
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text("\n".join(out) + "\n", encoding="utf-8")
PY
}

json_field() {
  local json="$1" expr="$2"
  node -e "
const d = JSON.parse(process.argv[1]);
const v = ($expr);
if (v == null) process.exit(2);
process.stdout.write(String(v));
" "$json"
}

http_json() {
  local method="$1" url="$2" body="${3:-}" auth="${4:-}"
  local args=(-sS -X "$method" "$url" -H "Accept: application/json")
  [[ -n "$auth" ]] && args+=(-H "Authorization: Bearer $auth")
  if [[ -n "$body" ]]; then
    args+=(-H "Content-Type: application/json" -d "$body")
  fi
  curl "${args[@]}"
}

require_cmd curl
require_cmd node
require_cmd python3
require_cmd pm2

[[ -d "$BE" ]] || fail "Backend nije na $BE — prilagodi APP varijablu."
[[ -f "$BE/.env" ]] || fail "Nema $BE/.env"

UMAMI_USER="${UMAMI_USER:-admin}"
if [[ -z "${UMAMI_PASS:-}" ]]; then
  read -r -s -p "Umami lozinka za korisnika '$UMAMI_USER': " UMAMI_PASS
  echo
fi
[[ -n "$UMAMI_PASS" ]] || fail "Lozinka je prazna."

info "Umami login ($UMAMI_BASE)..."
LOGIN_BODY=$(node -e "process.stdout.write(JSON.stringify({username:process.argv[1],password:process.argv[2]}))" "$UMAMI_USER" "$UMAMI_PASS")
LOGIN_JSON=$(http_json POST "$UMAMI_BASE/api/auth/login" "$LOGIN_BODY") || fail "Umami login nije uspio (curl)."

if echo "$LOGIN_JSON" | grep -q '"error"'; then
  echo "$LOGIN_JSON" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf8')); console.error(d.error?.message||JSON.stringify(d)); process.exit(1)"
  exit 1
fi

TOKEN=$(json_field "$LOGIN_JSON" "d.token") || fail "Nema tokena u login odgovoru."
TOKEN=$(clean_var "$TOKEN")
info "Token dobiven (${#TOKEN} znakova)."

info "Dohvat website liste..."
WEBSITES_JSON=$(http_json GET "$UMAMI_BASE/api/websites" "" "$TOKEN") || fail "GET /api/websites nije uspio."

WEBSITES_TMP=$(mktemp)
trap 'rm -f "$WEBSITES_TMP"' EXIT
printf '%s' "$WEBSITES_JSON" > "$WEBSITES_TMP"

WEBSITE_ID=$(WEBSITES_TMP="$WEBSITES_TMP" SITE_DOMAIN="$SITE_DOMAIN" node <<'PY'
const fs = require('fs');
const raw = fs.readFileSync(process.env.WEBSITES_TMP, 'utf8').trim();
if (!raw || (raw[0] !== '{' && raw[0] !== '[')) {
  console.error('Unexpected /api/websites body:', raw.slice(0, 200));
  process.exit(2);
}
let list;
try {
  list = JSON.parse(raw);
} catch (e) {
  console.error('JSON parse failed:', e.message);
  process.exit(2);
}
const want = (process.env.SITE_DOMAIN || 'ravnopar.com').toLowerCase().replace(/^www\./, '');
const base = want.replace(/\.(com|hr|io)$/, '');
const rows = Array.isArray(list)
  ? list
  : (list.data || list.websites || list.results || []);
const norm = (w) => String(w.domain || w.name || w.url || '').toLowerCase().replace(/^www\./, '');
let hit = rows.find((w) => {
  const d = norm(w);
  return d === want || d.includes(want) || want.includes(d) || d.startsWith(base);
});
if (!hit && rows.length === 1) hit = rows[0];
if (!hit) {
  rows.forEach((w) => console.error('-', w.id || w.websiteId, '|', w.domain || w.name));
  process.exit(2);
}
process.stdout.write(String(hit.id || hit.websiteId || hit.uuid || ''));
PY
) || true

if [[ -z "${WEBSITE_ID:-}" ]]; then
  warn "Website '$SITE_DOMAIN' nije pronađen automatski."
  echo "Dostupni websiteovi:"
  WEBSITES_TMP="$WEBSITES_TMP" node <<'PY'
const fs = require('fs');
const raw = fs.readFileSync(process.env.WEBSITES_TMP, 'utf8').trim();
try {
  const list = JSON.parse(raw);
  const rows = Array.isArray(list) ? list : (list.data || list.websites || list.results || []);
  rows.forEach((w) => console.log('-', w.id || w.websiteId, '|', w.domain || w.name));
} catch (e) {
  console.error('Ne mogu parsirati /api/websites:', e.message);
  console.error(raw.slice(0, 300));
}
PY
  if [[ -t 0 ]]; then
    read -r -p "Upiši Website ID (UUID): " WEBSITE_ID
  elif [[ -n "$DEFAULT_WEBSITE_ID" ]]; then
    warn "Koristim poznati Website ID: $DEFAULT_WEBSITE_ID"
    WEBSITE_ID="$DEFAULT_WEBSITE_ID"
  fi
fi

[[ -n "$WEBSITE_ID" ]] || fail "Website ID je obavezan."
WEBSITE_ID=$(clean_var "$WEBSITE_ID")
[[ "$WEBSITE_ID" =~ ^[0-9a-fA-F-]{36}$ ]] || fail "Website ID nije valjan UUID: '$WEBSITE_ID'"
info "Website ID: $WEBSITE_ID"

END_MS=$(($(date +%s) * 1000))
START_MS=$((END_MS - 7 * 24 * 60 * 60 * 1000))

info "Test stats API..."
STATS_URL="${UMAMI_BASE}/api/websites/${WEBSITE_ID}/stats"
if ! STATS_JSON=$(curl -sS -G "$STATS_URL" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  --data-urlencode "startAt=${START_MS}" \
  --data-urlencode "endAt=${END_MS}"); then
  warn "Stats API test nije uspio — nastavljam s upisom .env"
  STATS_JSON=""
fi

if [[ -n "$STATS_JSON" ]] && echo "$STATS_JSON" | grep -q '"error"'; then
  warn "Stats API: $STATS_JSON"
elif [[ -n "$STATS_JSON" ]]; then
  info "Stats API OK (visitors: $(node -e "const d=JSON.parse(process.argv[1]); const v=d.visitors; process.stdout.write(v?.value ?? v ?? '?');" "$STATS_JSON"))."
fi

info "Ažuriram backend/.env..."
ensure_env_line "$BE/.env" UMAMI_BASE_URL "$UMAMI_BASE"
ensure_env_line "$BE/.env" UMAMI_WEBSITE_ID "$WEBSITE_ID"
ensure_env_line "$BE/.env" UMAMI_USERNAME "$UMAMI_USER"
ensure_env_line "$BE/.env" UMAMI_PASSWORD "$UMAMI_PASS"
ensure_env_line "$BE/.env" UMAMI_API_TOKEN "$TOKEN"
ensure_env_line "$BE/.env" UMAMI_SITE_LABEL "$SITE_LABEL"

FE_ENV="$FE/.env.production"
if [[ -f "$FE/.env.local" ]]; then
  FE_ENV="$FE/.env.local"
elif [[ ! -f "$FE_ENV" ]]; then
  touch "$FE_ENV"
fi

info "Ažuriram frontend env ($FE_ENV)..."
ensure_env_line "$FE_ENV" NEXT_PUBLIC_ANALYTICS_URL "$UMAMI_BASE/script.js"
ensure_env_line "$FE_ENV" NEXT_PUBLIC_UMAMI_WEBSITE_ID "$WEBSITE_ID"

info "Restart PM2 (delete+start — PM2 inače drži stare UMAMI_* varijable)..."
pm2 delete ravnopar-api 2>/dev/null || true
pm2 start npm --name ravnopar-api --cwd "$BE" -- start
pm2 restart ravnopar-web --update-env 2>/dev/null || warn "ravnopar-web nije pronađen — preskačem."
pm2 save 2>/dev/null || true
sleep 2

info "Provjera Umami tokena (stats API)..."
if STATS_JSON=$(curl -sS -G "$STATS_URL" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  --data-urlencode "startAt=${START_MS}" \
  --data-urlencode "endAt=${END_MS}") && ! echo "$STATS_JSON" | grep -q '"error"'; then
  info "Umami stats OK nakon restarta."
else
  warn "Stats API još ne radi: ${STATS_JSON:-curl failed}"
  warn "Provjeri: grep '^UMAMI_' $BE/.env && pm2 env ravnopar-api | grep UMAMI || true"
fi

echo
echo -e "${GREEN}GOTOVO.${NC}"
echo "  Umami:     $UMAMI_BASE"
echo "  Website:   $SITE_DOMAIN → $WEBSITE_ID"
echo "  Backend:   $BE/.env (token ažuriran)"
echo "  Frontend:  $FE_ENV"
echo
echo "Osvježi https://ravnopar.com/admin — analitika bi trebala raditi."
echo
echo "Ako frontend i dalje piše 'Plausible', rebuild:"
echo "  cd $FE && npm run build && pm2 restart ravnopar-web --update-env"
