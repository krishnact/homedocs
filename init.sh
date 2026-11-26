#!/bin/sh
set -eu
cd "$(dirname "$0")"

compose() {
  docker compose --env-file .env --env-file .env.production "$@"
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
      echo "init.sh: invalid variable name: $key" >&2
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

needs_generated_value() {
  value=$1
  [ -z "$value" ] || [ "$value" = CHANGE_ME ] || [ "$value" = REPLACE_WITH_RANDOM_PASSWORD ] || [ "$value" = REPLACE_WITH_RANDOM_SECRET ]
}

set_env_line() {
  file=$1
  key=$2
  value=$3
  mkdir -p "$(dirname "$file")"
  if [ ! -f "$file" ]; then
    : > "$file"
  fi
  tmp=$(mktemp)
  awk -v key="$key" -v value="$value" '
    BEGIN { found = 0 }
    {
      line = $0
      sub(/\r$/, "", line)
      eq = index(line, "=")
      name = ""
      if (eq > 0) {
        name = substr(line, 1, eq - 1)
        gsub(/[[:space:]]/, "", name)
      }
      if (name == key) {
        if (!found) print key "=" value
        found = 1
        next
      }
      print line
    }
    END { if (!found) print key "=" value }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
  chmod 600 "$file"
}

unset_env_line() {
  file=$1
  key=$2
  if [ ! -f "$file" ]; then
    return 0
  fi
  tmp=$(mktemp)
  awk -v key="$key" '
    {
      line = $0
      sub(/\r$/, "", line)
      eq = index(line, "=")
      name = ""
      if (eq > 0) {
        name = substr(line, 1, eq - 1)
        gsub(/[[:space:]]/, "", name)
      }
      if (name == key) next
      print line
    }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
  chmod 600 "$file"
}

ai_key_ready() {
  value=$1
  [ -n "$value" ] && ! needs_generated_value "$value"
}

ensure_accounts() {
  if needs_generated_value "$(effective_value PAPERLESS_ADMIN_USER)"; then
    set_env_line .env PAPERLESS_ADMIN_USER admin
  fi
  if needs_generated_value "$(effective_value PAPERLESS_ADMIN_EMAIL)"; then
    set_env_line .env PAPERLESS_ADMIN_EMAIL admin@localhost
  fi
  if needs_generated_value "$(effective_value PAPERLESS_ADMIN_PASSWORD)"; then
    set_env_line .env PAPERLESS_ADMIN_PASSWORD "$(openssl rand -hex 32)"
    echo "Added PAPERLESS_ADMIN_PASSWORD to .env"
  fi
  if needs_generated_value "$(effective_value PAPERLESS_API_TOKEN)"; then
    set_env_line .env PAPERLESS_API_TOKEN "$(openssl rand -hex 20)"
    echo "Added PAPERLESS_API_TOKEN to .env"
  fi
}

wait_until() {
  label=$1
  shift
  i=0
  while [ "$i" -lt 60 ]; do
    if "$@"; then
      echo "$label is ready"
      return 0
    fi
    i=$((i + 1))
    sleep 5
  done
  echo "init.sh: $label did not become ready" >&2
  return 1
}

db_ready() {
  user=$(effective_value POSTGRES_USER)
  database=$(effective_value POSTGRES_DB)
  [ -n "$user" ] || user=paperless
  [ -n "$database" ] || database=paperless
  compose exec -T db pg_isready -U "$user" -d "$database" >/dev/null 2>&1
}

redis_ready() {
  compose exec -T redis redis-cli ping 2>/dev/null | grep -qx PONG
}

service_running() {
  compose ps --status running --services | grep -qx "$1"
}

paperless_ready() {
  compose exec -T -w /usr/src/paperless/src webserver python manage.py migrate
}

if [ ! -f .env ] || [ ! -f .env.production ]; then
  echo "init.sh: missing .env or .env.production. Run ./setup.sh first." >&2
  exit 1
fi
if ! command -v openssl >/dev/null 2>&1; then
  echo "init.sh: openssl is required" >&2
  exit 1
fi

ensure_accounts
compose up -d

wait_until PostgreSQL db_ready
wait_until Redis redis_ready
wait_until Tika service_running tika
wait_until Gotenberg service_running gotenberg
wait_until Paperless paperless_ready

compose exec -T -w /usr/src/paperless/src webserver \
  python manage.py shell -c "exec(open('/usr/src/paperless/bootstrap-ai.py').read())"

ai_env=storage/ai/.env
set_env_line "$ai_env" PAPERLESS_API_URL http://webserver:8000
set_env_line "$ai_env" PAPERLESS_API_TOKEN "$(effective_value PAPERLESS_API_TOKEN)"
set_env_line "$ai_env" PAPERLESS_USERNAME "$(effective_value PAPERLESS_ADMIN_USER)"
public_url=$(effective_value PAPERLESS_URL)
if [ -n "$public_url" ]; then
  set_env_line "$ai_env" PAPERLESS_PUBLIC_URL "$public_url"
fi

ai_provider=$(effective_value AI_PROVIDER)
case $ai_provider in
  openai)
    openai_key=$(effective_value OPENAI_API_KEY)
    if ai_key_ready "$openai_key"; then
      unset_env_line "$ai_env" ANTHROPIC_API_KEY
      unset_env_line "$ai_env" ANTHROPIC_MODEL
      unset_env_line "$ai_env" CUSTOM_BASE_URL
      unset_env_line "$ai_env" CUSTOM_API_KEY
      unset_env_line "$ai_env" CUSTOM_MODEL
      set_env_line "$ai_env" AI_PROVIDER openai
      set_env_line "$ai_env" OPENAI_API_KEY "$openai_key"
      openai_model=$(effective_value OPENAI_MODEL)
      if [ -n "$openai_model" ]; then
        set_env_line "$ai_env" OPENAI_MODEL "$openai_model"
      fi
      echo "Paperless-AI provider: openai"
    else
      echo "init.sh: AI_PROVIDER=openai but OPENAI_API_KEY is empty" >&2
    fi
    ;;
  anthropic)
    anthropic_key=$(effective_value ANTHROPIC_API_KEY)
    if ai_key_ready "$anthropic_key"; then
      unset_env_line "$ai_env" OPENAI_API_KEY
      unset_env_line "$ai_env" OPENAI_MODEL
      unset_env_line "$ai_env" CUSTOM_BASE_URL
      unset_env_line "$ai_env" CUSTOM_API_KEY
      unset_env_line "$ai_env" CUSTOM_MODEL
      set_env_line "$ai_env" AI_PROVIDER anthropic
      set_env_line "$ai_env" ANTHROPIC_API_KEY "$anthropic_key"
      anthropic_model=$(effective_value ANTHROPIC_MODEL)
      if [ -n "$anthropic_model" ]; then
        set_env_line "$ai_env" ANTHROPIC_MODEL "$anthropic_model"
      fi
      echo "Paperless-AI provider: claude"
    else
      echo "init.sh: AI_PROVIDER=anthropic but ANTHROPIC_API_KEY is empty" >&2
    fi
    ;;
  custom)
    custom_key=$(effective_value CUSTOM_API_KEY)
    custom_url=$(effective_value CUSTOM_BASE_URL)
    custom_model=$(effective_value CUSTOM_MODEL)
    if ai_key_ready "$custom_key" && [ -n "$custom_url" ] && [ -n "$custom_model" ]; then
      unset_env_line "$ai_env" OPENAI_API_KEY
      unset_env_line "$ai_env" OPENAI_MODEL
      unset_env_line "$ai_env" ANTHROPIC_API_KEY
      unset_env_line "$ai_env" ANTHROPIC_MODEL
      set_env_line "$ai_env" AI_PROVIDER custom
      set_env_line "$ai_env" CUSTOM_BASE_URL "$custom_url"
      set_env_line "$ai_env" CUSTOM_API_KEY "$custom_key"
      set_env_line "$ai_env" CUSTOM_MODEL "$custom_model"
      echo "Paperless-AI provider: custom ($custom_model)"
    else
      echo "init.sh: AI_PROVIDER=custom needs CUSTOM_BASE_URL, CUSTOM_API_KEY, and CUSTOM_MODEL" >&2
    fi
    ;;
  "")
    ;;
  *)
    echo "init.sh: unsupported AI_PROVIDER=$ai_provider" >&2
    ;;
esac

if compose ps -a --services | grep -qx paperless-ai; then
  compose restart paperless-ai
  echo "Paperless-AI is connected to http://webserver:8000"
fi

echo "Paperless admin user: $(effective_value PAPERLESS_ADMIN_USER)"
echo "Password and API token are in .env"
