#!/bin/sh
set -eu

degoo_configured() {
  [ -n "${DEGOO_EMAIL:-}" ] || [ -n "${DEGOO_PASSWORD:-}" ]
}

degoo_mkdir() {
  if cligoo ls "$1" >/dev/null 2>&1; then
    return 0
  fi
  cligoo mkdir "$1"
}

prepare_degoo_login() {
  python3 - <<'PY'
import json
import os
from pathlib import Path

dest = Path.home() / ".config" / "cligoo"
dest.mkdir(parents=True, exist_ok=True)
cred = dest / "credentials.json"
cred.write_text(json.dumps({
    "email": os.environ["DEGOO_EMAIL"],
    "password": os.environ["DEGOO_PASSWORD"],
}))
cred.chmod(0o600)
PY
}

upload_degoo() {
  if ! degoo_configured; then
    echo "Degoo backup skipped"
    return 0
  fi
  if [ -z "${DEGOO_EMAIL:-}" ] || [ -z "${DEGOO_PASSWORD:-}" ]; then
    echo "Set both DEGOO_EMAIL and DEGOO_PASSWORD to upload to Degoo" >&2
    return 1
  fi
  remote=${DEGOO_REMOTE:-/Web/paperless-backup}
  remote=${remote%/}
  case $remote in
    /*) ;;
    *)
      echo "DEGOO_REMOTE must be an absolute Degoo path" >&2
      return 1
      ;;
  esac
  prepare_degoo_login
  cligoo login
  degoo_mkdir "$remote"
  degoo_mkdir "$remote/$stamp"
  cligoo upload \
    "$stage/database.dump" \
    "$stage/media.tar.gz" \
    "$stage/data.tar.gz" \
    "$stage/ai.tar.gz" \
    "$stage/deployment.tar.gz" \
    -t "$remote/$stamp" \
    --workers 4
  cligoo upload "$stage/SHA256SUMS" -t "$remote/$stamp" --workers 1
  echo "Degoo backup uploaded: $remote/$stamp"
}

run_backup() (
  set -eu
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  stage=$(mktemp -d /backup/staging.XXXXXX)
  trap 'rm -rf "$stage"' EXIT
  pg_dump -Fc -f "$stage/database.dump"
  tar -czf "$stage/media.tar.gz" -C /source media
  tar -czf "$stage/data.tar.gz" -C /source data
  tar -czf "$stage/ai.tar.gz" -C /source ai
  tar -czf "$stage/deployment.tar.gz" -C /deployment compose.yaml .env .env.production backup
  (cd "$stage" && sha256sum *.gz database.dump > SHA256SUMS)
  rclone copy "$stage" "$BACKUP_REMOTE/$stamp" --exclude SHA256SUMS
  rclone copyto "$stage/SHA256SUMS" "$BACKUP_REMOTE/$stamp/SHA256SUMS"
  echo "Backup uploaded: $stamp"
  upload_degoo
)
if [ "${1:-}" = once ]; then
  run_backup
  exit
fi
while true; do
  if "$0" once; then sleep "$BACKUP_INTERVAL"; else echo 'Backup failed; retrying in 300 seconds' >&2; sleep 300; fi
done
