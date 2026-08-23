#!/usr/bin/env bash
# Popravi env (ukloni slučajno zalijepljene shell naredbe) i zamijeni source -> load_env_file.
# Pokreni NA VPS-u:
#   cd /root/oriphiel-ai/oriphiel_messaging && bash vps-patch-backfill.sh

set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ENV="$DIR/accounts/oriphiel.hr-mario.vitt.env"
SH="$DIR/sync-imap-backfill.sh"

if [[ ! -f "$ENV" ]]; then
  echo "Nema env: $ENV" >&2
  exit 1
fi
if [[ ! -f "$SH" ]]; then
  echo "Nema skripte: $SH" >&2
  exit 1
fi

cp -a "$ENV" "${ENV}.bak.$(date +%Y%m%d%H%M%S)"
cp -a "$SH" "${SH}.bak.$(date +%Y%m%d%H%M%S)"

python3 <<'PY'
from pathlib import Path
import re

env = Path("accounts/oriphiel.hr-mario.vitt.env")
lines = env.read_text(encoding="utf-8", errors="replace").splitlines()
clean = []
for line in lines:
    s = line.strip()
    if not s:
        continue
    if "bash sync-imap-backfill.sh" in s:
        continue
    if s == "# backfill (stara verzija skripte, ali radi):":
        continue
    clean.append(line.rstrip())
if not clean or not clean[0].startswith("#"):
    clean.insert(0, "# Oriphiel (oriphiel.hr) - mario.vitt@oriphiel.hr")
env.write_text("\n".join(clean) + "\n")
print(f"env OK ({len(clean)} linija)")

sh = Path("sync-imap-backfill.sh")
text = sh.read_text(encoding="utf-8", errors="replace")
loader = r'''
load_env_file() {
  local f="$1"
  local line key val
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      val="${BASH_REMATCH[2]}"
      if [[ "$val" =~ ^\'(.*)\'$ ]]; then
        val="${BASH_REMATCH[1]}"
      elif [[ "$val" =~ ^\"(.*)\"$ ]]; then
        val="${BASH_REMATCH[1]}"
      fi
      printf -v "$key" '%s' "$val"
      export "$key"
    fi
  done < "$f"
}
'''
if "load_env_file()" not in text:
    text = text.replace(
        'if [[ -n "$ENV_FILE" ]]; then',
        loader.strip() + '\n\nif [[ -n "$ENV_FILE" ]]; then',
        1,
    )
text, n = re.subn(r'^\s*(?:source|\.)+\s+"\$ENV_FILE"\s*$', '  load_env_file "$ENV_FILE"', text, flags=re.M)
text, n2 = re.subn(r'^\s*set\s+-a\s*;\s*source\s+"\$ENV_FILE"\s*;\s*set\s+\+a\s*$', '  load_env_file "$ENV_FILE"', text, flags=re.M)
sh.write_text(text)
print("shell OK (load_env_file)")
PY

grep -n 'load_env_file\|source' "$SH" | head -5
echo "--- env (prvih 8 linija) ---"
sed -n '1,8p' "$ENV" | cat -n
echo "Gotovo. Pokreni:"
echo "  ENV_FILE=accounts/oriphiel.hr-mario.vitt.env RESET_BEFORE=1 STATUS_FILE=/tmp/oriphiel-imap-backfill-mario.vitt.json bash sync-imap-backfill.sh"
