#!/usr/bin/env bash
# Svi accounti iz accounts/*.env
# RESET_BEFORE=1 brise SAMO taj account (u petlji po svakom .env)
# RESET_ALL=1 brise SVE poruke/fileove jednom na pocetku

set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ACC_DIR="${ACC_DIR:-$DIR/accounts}"
PG_CONTAINER="${PG_CONTAINER:-oriphiel-postgres}"
PG_USER="${PG_USER:-oriphiel}"
PG_DB="${PG_DB:-oriphiel}"
ATTACH_DIR="${ATTACH_DIR:-/var/lib/oriphiel/attachments}"

if [[ ! -d "$ACC_DIR" ]]; then
  echo "Nema foldera: $ACC_DIR" >&2
  exit 1
fi

shopt -s nullglob
files=("$ACC_DIR"/*.env)
if [[ ${#files[@]} -eq 0 ]]; then
  echo "Nema $ACC_DIR/*.env" >&2
  exit 1
fi

if [[ "${RESET_ALL:-0}" == "1" && "${DRY_RUN:-0}" != "1" ]]; then
  echo "=== RESET_ALL (jednom) ==="
  SQL='TRUNCATE TABLE message_attachments, messages, contacts RESTART IDENTITY CASCADE;'
  echo "$SQL" | docker exec -i "$PG_CONTAINER" psql -U "$PG_USER" -d "$PG_DB" -v ON_ERROR_STOP=1
  rm -rf "${ATTACH_DIR:?}"/*
  mkdir -p "$ATTACH_DIR"
fi

ec=0
for f in "${files[@]}"; do
  echo
  echo "########## $(basename "$f") ##########"
  # RESET_BEFORE ostaje ukljucen po accountu (scoped u pythonu)
  if ! RESET_ALL=0 ENV_FILE="$f" bash "$DIR/sync-imap-backfill.sh"; then
    ec=1
    echo "FAILED: $f" >&2
  fi
done

exit "$ec"
