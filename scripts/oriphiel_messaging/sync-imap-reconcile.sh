#!/usr/bin/env bash
# Brzi reconcile: soft-delete nestalih UID-ova + refresh FLAGS/labela (bez RFC822).
#
#   ENV_FILE=accounts/oriphiel.hr-mario.vitt.env bash sync-imap-reconcile.sh
#   MAILBOXES=INBOX,Sent,Archive ENV_FILE=... bash sync-imap-reconcile.sh

set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
export ONLY_RECONCILE=1
export SYNC_DELETE="${SYNC_DELETE:-1}"
export SAVE_ATTACHMENTS=0
export RUN_AI=0
export RESET_BEFORE=0
export MAILBOXES="${MAILBOXES:-INBOX,Sent,Archive}"
exec bash "$DIR/sync-imap-backfill.sh"
