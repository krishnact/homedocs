#!/bin/sh
set -eu
cd "$(dirname "$0")"

usage() {
  cat <<'EOF'
Usage: stack.sh <command>

Commands:
  start   Build and start the stack in the background
  stop    Stop the stack without removing containers
  help    Show this help

Run ./setup.sh once before start. start and stop load both env files:

  docker compose --env-file .env --env-file .env.production ...

start requires POSTGRES_PASSWORD and PAPERLESS_SECRET_KEY. A shell value
wins, then .env.production, then .env. Example placeholders are rejected.

start then runs ./init.sh, which waits for the services, creates the
Paperless admin account and API token, and connects Paperless-AI.
EOF
}

compose() {
  docker compose --env-file .env --env-file .env.production "$@"
}

require_env() {
  missing=0
  for file in .env .env.production; do
    if [ ! -f "$file" ]; then
      echo "stack.sh: missing $file. Run ./setup.sh first." >&2
      missing=1
    fi
  done
  if [ "$missing" -ne 0 ]; then
    exit 1
  fi
}

file_value() {
  key=$1
  awk -v key="$key" '
    BEGIN { value = "" }
    /^[[:space:]]*($|#)/ { next }
    {
      line = $0
      sub(/\r$/, "", line)
      sub(/^[[:space:]]*export[[:space:]]+/, "", line)
      eq = index(line, "=")
      if (eq == 0) next
      name = substr(line, 1, eq - 1)
      gsub(/[[:space:]]/, "", name)
      if (name != key) next
      value = substr(line, eq + 1)
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      if (value ~ /^".*"$/ || value ~ /^'\''.*'\''$/) {
        value = substr(value, 2, length(value) - 2)
      }
    }
    END { printf "%s", value }
  ' .env .env.production
}

effective_value() {
  key=$1
  case $key in
    *[!A-Z0-9_]*)
      echo "stack.sh: invalid variable name: $key" >&2
      exit 1
      ;;
  esac
  eval "present=\${$key+x}"
  if [ -n "$present" ]; then
    eval "value=\${$key}"
    printf '%s' "$value"
    return
  fi
  file_value "$key"
}

require_vars() {
  missing=0
  for key in POSTGRES_PASSWORD PAPERLESS_SECRET_KEY; do
    value=$(effective_value "$key")
    if [ -z "$value" ] || [ "$value" = CHANGE_ME ] || [ "$value" = REPLACE_WITH_RANDOM_PASSWORD ] || [ "$value" = REPLACE_WITH_RANDOM_SECRET ]; then
      echo "stack.sh: set $key to a generated secret in .env or .env.production" >&2
      missing=1
    fi
  done
  if [ "$missing" -ne 0 ]; then
    exit 1
  fi
}

if [ "$#" -gt 1 ]; then
  echo "stack.sh: too many arguments" >&2
  usage >&2
  exit 1
fi

case "${1:-help}" in
  start)
    require_env
    require_vars
    compose up -d --build
    ./init.sh
    ;;
  stop)
    require_env
    compose stop
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    echo "stack.sh: unknown command: $1" >&2
    usage >&2
    exit 1
    ;;
esac
