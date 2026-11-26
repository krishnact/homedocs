#!/bin/sh
set -eu
cd "$(dirname "$0")"
umask 077

if ! command -v openssl >/dev/null 2>&1; then
  echo "setup.sh: openssl is required" >&2
  exit 1
fi

for example in .env.example .env.production.example; do
  if [ ! -f "$example" ]; then
    echo "setup.sh: missing $example" >&2
    exit 1
  fi
done

mkdir -p \
  storage/data \
  storage/media \
  storage/consume \
  storage/export \
  storage/ai \
  storage/backups \
  storage/postgres \
  storage/redis \
  rclone
chmod 1777 storage/postgres

write_secret() {
  file=$1
  key=$2
  placeholder=$3
  if ! awk -v key="$key" -v old="$placeholder" '
    BEGIN { found = 0 }
    $0 == key "=" old { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$file"; then
    echo "setup.sh: $file is missing ${key}=${placeholder}" >&2
    exit 1
  fi
  if [ "$key" = PAPERLESS_API_TOKEN ]; then
    secret=$(openssl rand -hex 20)
  else
    secret=$(openssl rand -hex 32)
  fi
  tmp=$(mktemp)
  awk -v key="$key" -v old="$placeholder" -v new="$secret" '
    $0 == key "=" old { print key "=" new; next }
    { print }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
  chmod 600 "$file"
}

install_env() {
  example=$1
  dest=$2
  shift 2
  if [ -e "$dest" ]; then
    chmod 600 "$dest"
    echo "Leaving existing $dest unchanged"
    return
  fi
  cp "$example" "$dest"
  chmod 600 "$dest"
  while [ "$#" -ge 2 ]; do
    write_secret "$dest" "$1" "$2"
    shift 2
  done
  echo "Created $dest and assigned secrets"
}

install_env .env.example .env \
  POSTGRES_PASSWORD CHANGE_ME \
  PAPERLESS_SECRET_KEY CHANGE_ME \
  PAPERLESS_ADMIN_PASSWORD CHANGE_ME \
  PAPERLESS_API_TOKEN CHANGE_ME

install_env .env.production.example .env.production \
  POSTGRES_PASSWORD REPLACE_WITH_RANDOM_PASSWORD \
  PAPERLESS_SECRET_KEY REPLACE_WITH_RANDOM_SECRET

if awk '$0 == "PAPERLESS_URL=https://paperless.example.com" { found = 1 } END { exit found ? 0 : 1 }' .env.production; then
  echo "Change PAPERLESS_URL in .env.production before production use."
fi
