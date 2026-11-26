#!/bin/sh
set -eu
cd "$(dirname "$0")"

cat <<'EOF'
This permanently deletes the local installation:

  - containers and Docker volumes for this stack
  - storage/ (database, documents, Redis, Paperless-AI data, local backups)
  - .env and .env.production (passwords, secret key, API token)
  - rclone/rclone.conf (OpenDrive remote and crypt passwords)

Copies already uploaded to OpenDrive or Degoo are left in place.
The repository files, examples, and scripts are left in place.

Type WIPE to continue.
EOF

if [ ! -t 0 ]; then
  echo "wipe.sh: confirmation requires an interactive terminal" >&2
  exit 1
fi

printf '> '
read -r confirmation
if [ "$confirmation" != WIPE ]; then
  echo "Wipe cancelled."
  exit 1
fi

if [ -f .env ] && [ -f .env.production ]; then
  docker compose --env-file .env --env-file .env.production down --remove-orphans --volumes
else
  docker compose down --remove-orphans --volumes
fi

rm -rf storage
rm -f .env .env.production rclone/rclone.conf
echo "Local installation removed. Run ./setup.sh and ./stack.sh start for a fresh install."
