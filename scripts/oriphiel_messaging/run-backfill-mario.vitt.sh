#!/usr/bin/env bash
# Retroaktivni uvoz mario.vitt@oriphiel.hr (wipe + full INBOX)
# Pokreni na VPS-u:
#   bash /root/oriphiel-ai/oriphiel_messaging/run-backfill-mario.vitt.sh

set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${ENV_FILE:-$DIR/accounts/oriphiel.hr-mario.vitt.env}"

export RESET_BEFORE="${RESET_BEFORE:-1}"
export RUN_AI="${RUN_AI:-0}"
export BATCH_SIZE="${BATCH_SIZE:-50}"
export MARK_AS_SEEN="${MARK_AS_SEEN:-0}"
export STATUS_FILE="${STATUS_FILE:-/tmp/oriphiel-imap-backfill-mario.vitt.json}"

exec env ENV_FILE="$ENV_FILE" bash "$DIR/sync-imap-backfill.sh"
