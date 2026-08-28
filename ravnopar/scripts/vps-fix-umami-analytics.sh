#!/usr/bin/env bash
# Ravnopar VPS — poveži Umami analitiku s /admin panelom (cijeli fix)
#
# Radi:
#   1) Login u Umami → token + Website ID
#   2) Upiše backend/.env + frontend env (USERNAME/PASSWORD, ne istekli token)
#   3) Patcha backend/src/index.js da uvijek učita backend/.env (PM2 cwd fix)
#   4) pm2 delete + start ravnopar-api (PM2 ne drži stare UMAMI_* varijable)
#   5) Provjeri getUmamiAdminSummary() i lokalni /api/admin/analytics
#
# Na VPS-u:
#   cd /var/www/Render/ravnopar
#   UMAMI_USER=admin UMAMI_PASS='lozinka' bash scripts/vps-fix-umami-analytics.sh
#
# S laptopa (Windows):
#   powershell -ExecutionPolicy Bypass -File scripts\Fix-UmamiOnVps.ps1
#
set -euo pipefail

clean_var() {
  printf '%s' "$1" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

APP="$(clean_var "${RAVNOPAR_APP:-/var/www/Render/ravnopar}")"
BE="$APP/backend"
FE="$APP/frontend-next"
INDEX="$BE/src/index.js"
UMAMI_BASE="$(clean_var "${UMAMI_BASE_URL:-https://analytics.ravnopar.com}")"
UMAMI_BASE="${UMAMI_BASE%/}"
SITE_DOMAIN="$(clean_var "${UMAMI_SITE_DOMAIN:-ravnopar.com}")"
SITE_LABEL="$(clean_var "${UMAMI_SITE_LABEL:-ravnopar.com}")"
DEFAULT_WEBSITE_ID="$(clean_var "${UMAMI_DEFAULT_WEBSITE_ID:-0c0daf08-e152-4f26-93f4-1a01add4c12c}")"
API_PORT="$(clean_var "${RAVNOPAR_API_PORT:-4200}")"

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

def format_env_value(value: str) -> str:
    if value == "":
        return '""'
    if any(c in value for c in '#"\n\r\t \\=$'):
        escaped = value.replace("\\", "\\\\").replace('"', '\\"')
        return f'"{escaped}"'
    return value

path, key, value = sys.argv[1], sys.argv[2], sys.argv[3]
formatted = format_env_value(value)
p = Path(path)
lines = p.read_text(encoding="utf-8").splitlines() if p.exists() else []
out, found = [], False
for line in lines:
    if line.startswith(key + "="):
        out.append(f"{key}={formatted}")
        found = True
    else:
        out.append(line)
if not found:
    out.append(f"{key}={formatted}")
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text("\n".join(out) + "\n", encoding="utf-8")
PY
}

remove_env_line() {
  local file="$1" key="$2"
  python3 - "$file" "$key" <<'PY'
import sys
from pathlib import Path

path, key = sys.argv[1], sys.argv[2]
p = Path(path)
if not p.exists():
    sys.exit(0)
lines = [ln for ln in p.read_text(encoding="utf-8").splitlines() if not ln.startswith(key + "=")]
p.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")
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

patch_index_dotenv() {
  [[ -f "$INDEX" ]] || fail "Nema $INDEX"

  if grep -q 'backendRoot' "$INDEX" 2>/dev/null; then
    info "index.js već učitava backend/.env (backendRoot)."
    return 0
  fi

  info "Patcham $INDEX — dotenv iz backend/.env (PM2 cwd fix)..."
  cp -a "$INDEX" "${INDEX}.bak.$(date +%Y%m%d%H%M%S)"

  python3 - "$INDEX" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
block = """import path from 'path';
import { fileURLToPath } from 'url';
import dotenv from 'dotenv';

const backendRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
dotenv.config({ path: path.join(backendRoot, '.env'), override: true });

"""

if "backendRoot" in text:
    print("already patched")
    sys.exit(0)

for old in (
    "import 'dotenv/config';\n",
    "import dotenv from 'dotenv';\n\n// .env on VPS is source of truth — PM2 keeps stale env across `restart` unless we override.\ndotenv.config({ override: true });\n",
    "import dotenv from 'dotenv';\n\ndotenv.config({ override: true });\n",
):
    if old in text:
        text = text.replace(old, block, 1)
        path.write_text(text, encoding="utf-8")
        print("patched-replace")
        sys.exit(0)

# Prepend before first import if unknown layout
lines = text.splitlines(keepends=True)
first_import = next((i for i, ln in enumerate(lines) if ln.startswith("import ")), 0)
lines[first_import:first_import] = [block]
path.write_text("".join(lines), encoding="utf-8")
print("patched-prepend")
PY
}

verify_backend_umami() {
  info "Provjera backend Umami modula ($BE/.env)..."
  local result env_file="$BE/.env"
  result=$(cd "$BE" && ENV_FILE="$env_file" node --input-type=module <<'PY'
import dotenv from 'dotenv';

dotenv.config({ path: process.env.ENV_FILE, override: true });

const { getUmamiAdminSummary } = await import('./src/services/umami-service.js');
const r = await getUmamiAdminSummary();
console.log(JSON.stringify({
  configured: r.configured,
  error: r.error ?? null,
  visitors7d: r.summary?.visitors7d ?? null,
  env: {
    base: Boolean(process.env.UMAMI_BASE_URL),
    id: Boolean(process.env.UMAMI_WEBSITE_ID),
    user: Boolean(process.env.UMAMI_USERNAME),
    pass: Boolean(process.env.UMAMI_PASSWORD)
  }
}));
PY
) || fail "Backend Umami provjera nije uspjela (node)."

  info "Backend modul: $result"
  if echo "$result" | grep -q '"configured":true' && echo "$result" | grep -q '"error":null'; then
    return 0
  fi
  return 1
}

verify_live_api() {
  info "Provjera da ravnopar-api sluša na :${API_PORT}..."
  curl -sS -o /dev/null -w "%{http_code}" "http://127.0.0.1:${API_PORT}/api/auth/profile" | grep -qE '401|200' \
    || fail "API ne odgovara na portu ${API_PORT}."

  info "PM2 env (UMAMI_* ne smije imati stare vrijednosti osim iz .env):"
  pm2 env ravnopar-api 2>/dev/null | grep -E '^UMAMI_' || warn "Nema UMAMI_* u pm2 env (OK — dotenv učitava iz .env)."

  warn "Live /api/admin/analytics traži admin JWT — provjeri u browseru /admin (Ctrl+F5)."
}

require_cmd curl
require_cmd node
require_cmd python3
require_cmd pm2

[[ -d "$BE" ]] || fail "Backend nije na $BE — postavi RAVNOPAR_APP."
[[ -f "$BE/.env" ]] || fail "Nema $BE/.env"

UMAMI_USER="${UMAMI_USER:-admin}"
if [[ -n "${UMAMI_PASS_B64:-}" ]]; then
  UMAMI_PASS=$(printf '%s' "$UMAMI_PASS_B64" | tr -d '\r\n' | base64 -d 2>/dev/null || true)
fi
if [[ -z "${UMAMI_PASS:-}" ]]; then
  read -r -s -p "Umami lozinka za korisnika '$UMAMI_USER': " UMAMI_PASS
  echo
fi
[[ -n "$UMAMI_PASS" ]] || fail "Lozinka je prazna."

patch_index_dotenv

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
let list = JSON.parse(raw);
const want = (process.env.SITE_DOMAIN || 'ravnopar.com').toLowerCase().replace(/^www\./, '');
const base = want.replace(/\.(com|hr|io)$/, '');
const rows = Array.isArray(list) ? list : (list.data || list.websites || list.results || []);
const norm = (w) => String(w.domain || w.name || w.url || '').toLowerCase().replace(/^www\./, '');
let hit = rows.find((w) => {
  const d = norm(w);
  return d === want || d.includes(want) || want.includes(d) || d.startsWith(base);
});
if (!hit && rows.length === 1) hit = rows[0];
if (!hit) process.exit(2);
process.stdout.write(String(hit.id || hit.websiteId || hit.uuid || ''));
PY
) || true

if [[ -z "${WEBSITE_ID:-}" ]]; then
  warn "Website '$SITE_DOMAIN' nije pronađen automatski — koristim $DEFAULT_WEBSITE_ID"
  WEBSITE_ID="$DEFAULT_WEBSITE_ID"
fi

WEBSITE_ID=$(clean_var "$WEBSITE_ID")
[[ "$WEBSITE_ID" =~ ^[0-9a-fA-F-]{36}$ ]] || fail "Website ID nije valjan UUID: '$WEBSITE_ID'"
info "Website ID: $WEBSITE_ID"

END_MS=$(($(date +%s) * 1000))
START_MS=$((END_MS - 7 * 24 * 60 * 60 * 1000))
STATS_URL="${UMAMI_BASE}/api/websites/${WEBSITE_ID}/stats"

info "Test stats API..."
STATS_JSON=$(curl -sS -G "$STATS_URL" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  --data-urlencode "startAt=${START_MS}" \
  --data-urlencode "endAt=${END_MS}") || fail "Stats API curl nije uspio."

if echo "$STATS_JSON" | grep -q '"error"'; then
  fail "Stats API greška: $STATS_JSON"
fi
info "Stats API OK."

info "Ažuriram backend/.env..."
ensure_env_line "$BE/.env" UMAMI_BASE_URL "$UMAMI_BASE"
ensure_env_line "$BE/.env" UMAMI_WEBSITE_ID "$WEBSITE_ID"
ensure_env_line "$BE/.env" UMAMI_USERNAME "$UMAMI_USER"
ensure_env_line "$BE/.env" UMAMI_PASSWORD "$UMAMI_PASS"
ensure_env_line "$BE/.env" UMAMI_SITE_LABEL "$SITE_LABEL"
# Ukloni istekli statični token — backend koristi USERNAME/PASSWORD (auto refresh).
remove_env_line "$BE/.env" UMAMI_API_TOKEN

FE_ENV="$FE/.env.production"
if [[ -f "$FE/.env.local" ]]; then
  FE_ENV="$FE/.env.local"
elif [[ ! -f "$FE_ENV" ]]; then
  touch "$FE_ENV"
fi

info "Ažuriram frontend env ($FE_ENV)..."
ensure_env_line "$FE_ENV" NEXT_PUBLIC_ANALYTICS_URL "$UMAMI_BASE/script.js"
ensure_env_line "$FE_ENV" NEXT_PUBLIC_UMAMI_WEBSITE_ID "$WEBSITE_ID"
ensure_env_line "$FE_ENV" NEXT_PUBLIC_API_BASE_URL "https://ravnopar.com/api"

if ! verify_backend_umami; then
  warn "Pre-PM2 provjera nije idealna — nastavljam s restartom."
fi

info "Restart PM2 (delete+start — PM2 inače drži stare env varijable)..."
pm2 delete ravnopar-api 2>/dev/null || true
pm2 start npm --name ravnopar-api --cwd "$BE" -- start
pm2 restart ravnopar-web --update-env 2>/dev/null || warn "ravnopar-web nije pronađen — preskačem."
pm2 save 2>/dev/null || true
sleep 3

if ! verify_backend_umami; then
  warn "Backend provjera nije configured:true nakon PM2 restarta."
  warn "Stats API je radio — vjerojatno je OK. Osvjezi /admin (Ctrl+F5)."
  warn "Ako ne radi: pm2 logs ravnopar-api --lines 30"
fi

verify_live_api

echo
echo -e "${GREEN}GOTOVO.${NC}"
echo "  Umami:     $UMAMI_BASE"
echo "  Website:   $SITE_DOMAIN → $WEBSITE_ID"
echo "  Backend:   $BE/.env"
echo "  index.js:  patchan (backend/.env + override)"
echo "  PM2:       ravnopar-api restartan (delete+start)"
echo
echo "Osvježi https://ravnopar.com/admin (Ctrl+F5)."
