#!/bin/sh
set -eu
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
)
if [ "${1:-}" = once ]; then
  run_backup
  exit
fi
while true; do
  if "$0" once; then sleep "$BACKUP_INTERVAL"; else echo 'Backup failed; retrying in 300 seconds' >&2; sleep 300; fi
done
