#!/usr/bin/env bash
# Jedan IMAP account -> Postgres
#
#   bash sync-imap-backfill.sh
#   ENV_FILE=./accounts/oriphiel.hr-mario.vitt.env bash sync-imap-backfill.sh
#   LIMIT=20 ENV_FILE=... bash sync-imap-backfill.sh
#   DRY_RUN=1 LIMIT=5 ENV_FILE=... bash sync-imap-backfill.sh

set -euo pipefail
set +H
DIR="$(cd "$(dirname "$0")" && pwd)"

# Jedan backfill odjednom (n8n / SSH / rucno)
LOCK_FILE="${BACKFILL_LOCK:-/tmp/oriphiel-imap-backfill.lock}"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "ERROR: backfill vec traje (lock $LOCK_FILE)." >&2
  echo "Status: cat /tmp/oriphiel-imap-backfill-mario.vitt.json" >&2
  echo "Stop:   pkill -f sync-imap-backfill" >&2
  exit 75
fi

# Zapamti override s command line (da .env ne pregazi LIMIT/DRY_RUN/RESET/ATTACH)
_OV_LIMIT="${LIMIT-__UNSET__}"
_OV_ONLY_UNSEEN="${ONLY_UNSEEN-__UNSET__}"
_OV_DRY_RUN="${DRY_RUN-__UNSET__}"
_OV_RESET_BEFORE="${RESET_BEFORE-__UNSET__}"
_OV_RESET_ACCOUNTS="${RESET_ACCOUNTS-__UNSET__}"
_OV_SAVE_ATTACHMENTS="${SAVE_ATTACHMENTS-__UNSET__}"
_OV_ATTACH_DIR="${ATTACH_DIR-__UNSET__}"
_OV_ATTACH_URL_PREFIX="${ATTACH_URL_PREFIX-__UNSET__}"
_OV_MAX_ATTACH_BYTES="${MAX_ATTACH_BYTES-__UNSET__}"
_OV_STATUS_FILE="${STATUS_FILE-__UNSET__}"
_OV_PROGRESS_EVERY="${PROGRESS_EVERY-__UNSET__}"

ENV_FILE="${ENV_FILE:-}"
if [[ -z "$ENV_FILE" && -f "$DIR/imap-backfill.env" ]]; then
  ENV_FILE="$DIR/imap-backfill.env"
fi

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

if [[ -n "$ENV_FILE" ]]; then
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "ENV_FILE not found: $ENV_FILE" >&2
    exit 1
  fi
  load_env_file "$ENV_FILE"
fi

# Vrati command-line override
[[ "$_OV_LIMIT" != "__UNSET__" ]] && LIMIT="$_OV_LIMIT"
[[ "$_OV_ONLY_UNSEEN" != "__UNSET__" ]] && ONLY_UNSEEN="$_OV_ONLY_UNSEEN"
[[ "$_OV_DRY_RUN" != "__UNSET__" ]] && DRY_RUN="$_OV_DRY_RUN"
[[ "$_OV_RESET_BEFORE" != "__UNSET__" ]] && RESET_BEFORE="$_OV_RESET_BEFORE"
[[ "$_OV_RESET_ACCOUNTS" != "__UNSET__" ]] && RESET_ACCOUNTS="$_OV_RESET_ACCOUNTS"
[[ "$_OV_SAVE_ATTACHMENTS" != "__UNSET__" ]] && SAVE_ATTACHMENTS="$_OV_SAVE_ATTACHMENTS"
[[ "$_OV_ATTACH_DIR" != "__UNSET__" ]] && ATTACH_DIR="$_OV_ATTACH_DIR"
[[ "$_OV_ATTACH_URL_PREFIX" != "__UNSET__" ]] && ATTACH_URL_PREFIX="$_OV_ATTACH_URL_PREFIX"
[[ "$_OV_MAX_ATTACH_BYTES" != "__UNSET__" ]] && MAX_ATTACH_BYTES="$_OV_MAX_ATTACH_BYTES"
[[ "$_OV_STATUS_FILE" != "__UNSET__" ]] && STATUS_FILE="$_OV_STATUS_FILE"
[[ "$_OV_PROGRESS_EVERY" != "__UNSET__" ]] && PROGRESS_EVERY="$_OV_PROGRESS_EVERY"

: "${IMAP_USER:?Set IMAP_USER (or ENV_FILE)}"
: "${IMAP_PASSWORD:?Set IMAP_PASSWORD (or ENV_FILE)}"

export IMAP_HOST="${IMAP_HOST:-imap.hostinger.com}"
export IMAP_PORT="${IMAP_PORT:-993}"
export MAILBOX="${MAILBOX:-INBOX}"
export MAILBOXES="${MAILBOXES:-INBOX,Sent,Archive}"
export ACCOUNT_EMAIL="${ACCOUNT_EMAIL:-$IMAP_USER}"
export PG_CONTAINER="${PG_CONTAINER:-oriphiel-postgres}"
export PG_USER="${PG_USER:-oriphiel}"
export PG_DB="${PG_DB:-oriphiel}"
export LIMIT="${LIMIT:-0}"
export ONLY_UNSEEN="${ONLY_UNSEEN:-0}"
export DRY_RUN="${DRY_RUN:-0}"
export RESET_BEFORE="${RESET_BEFORE:-0}"
export RESET_ACCOUNTS="${RESET_ACCOUNTS:-0}"
export SAVE_ATTACHMENTS="${SAVE_ATTACHMENTS:-1}"
export ATTACH_DIR="${ATTACH_DIR:-/var/lib/oriphiel/attachments}"
export ATTACH_URL_PREFIX="${ATTACH_URL_PREFIX:-/data/attachments}"
export MAX_ATTACH_BYTES="${MAX_ATTACH_BYTES:-26214400}"
export STATUS_FILE="${STATUS_FILE:-/tmp/oriphiel-imap-backfill-status.json}"
export PROGRESS_EVERY="${PROGRESS_EVERY:-10}"
export BATCH_SIZE="${BATCH_SIZE:-50}"
export BATCH_SLEEP_SEC="${BATCH_SLEEP_SEC:-1}"
export RUN_AI="${RUN_AI:-0}"
export OLLAMA_URL="${OLLAMA_URL:-http://127.0.0.1:11434}"
export OLLAMA_MODEL="${OLLAMA_MODEL:-llama3.1:8b}"
export MARK_AS_SEEN="${MARK_AS_SEEN:-0}"
export SYNC_DELETE="${SYNC_DELETE:-1}"
export ONLY_RECONCILE="${ONLY_RECONCILE:-0}"
export PYTHONUNBUFFERED=1

echo "=== Backfill account: $ACCOUNT_EMAIL ($IMAP_USER) ==="
echo "MAILBOXES=$MAILBOXES SYNC_DELETE=$SYNC_DELETE ONLY_RECONCILE=$ONLY_RECONCILE"
echo "LIMIT=$LIMIT DRY_RUN=$DRY_RUN RESET_BEFORE=$RESET_BEFORE SAVE_ATTACHMENTS=$SAVE_ATTACHMENTS"
echo "BATCH_SIZE=$BATCH_SIZE RUN_AI=$RUN_AI MARK_AS_SEEN=$MARK_AS_SEEN"
echo "STATUS_FILE=$STATUS_FILE (watch -n1 cat \$STATUS_FILE)"
exec python3 -u "$DIR/sync-imap-backfill.py"
