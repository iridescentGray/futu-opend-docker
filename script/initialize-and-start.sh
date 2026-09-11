#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

readonly root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly env_file=${FUTU_ENV_FILE:-$root_dir/.env}
readonly compose_file=${FUTU_COMPOSE_FILE:-$root_dir/docker-compose.yaml}
key_path=${LOCAL_RSA_FILE_PATH:-$root_dir/futu.pem}

die() {
  printf 'ERROR: %s\n' "$1" >&2
  exit "${2:-1}"
}

file_mode() {
  local path=$1
  if stat -c '%a' "$path" >/dev/null 2>&1; then
    stat -c '%a' "$path"
  else
    stat -f '%Lp' "$path"
  fi
}

[[ -t 0 && -t 1 ]] ||
  die 'initialization requires a private stdin/stdout TTY' 64
[[ -f "$env_file" ]] || die "environment file not found: $env_file" 66
[[ -f "$compose_file" ]] || die "Compose file not found: $compose_file" 66
[[ "$key_path" != *$'\n'* && "$key_path" != *$'\r'* ]] ||
  die 'LOCAL_RSA_FILE_PATH must not contain line breaks' 64
if [[ "$key_path" != /* ]]; then
  key_path=$root_dir/${key_path#./}
fi

command -v docker >/dev/null 2>&1 || die 'docker is required' 69
command -v openssl >/dev/null 2>&1 || die 'openssl is required' 69

bash "$root_dir/script/lock-artifact.sh" "$env_file"

compose=(docker compose --env-file "$env_file" -f "$compose_file")

# Validate interpolation before creating a key or stopping an existing service.
env -u FUTU_OPEND_SHA256 LOCAL_RSA_FILE_PATH="$key_path" \
  "${compose[@]}" config --quiet ||
  die 'Compose configuration is invalid; no service was stopped'

if [[ -e "$key_path" || -L "$key_path" ]]; then
  [[ -f "$key_path" && ! -L "$key_path" ]] ||
    die 'the existing RSA key path must be a regular file, not a symlink'
  [[ $(file_mode "$key_path") == 600 ]] ||
    die 'the existing RSA key must use mode 0600; it was not modified'
else
  key_parent=${key_path%/*}
  [[ -d "$key_parent" && -w "$key_parent" ]] ||
    die 'the RSA key parent directory must already exist and be writable'
  temporary_key=$(mktemp "$key_parent/.futu-key.XXXXXX")
  cleanup_key() {
    rm -f -- "$temporary_key"
  }
  trap cleanup_key EXIT HUP INT TERM
  openssl genrsa -traditional -out "$temporary_key" 1024 >/dev/null 2>&1 ||
    die 'OpenSSL could not generate the RSA key'
  chmod 0600 "$temporary_key"
  [[ ! -e "$key_path" && ! -L "$key_path" ]] ||
    die 'the RSA key appeared during generation; refusing to overwrite it'
  mv -- "$temporary_key" "$key_path"
  trap - EXIT HUP INT TERM
  printf 'Generated a new mode-0600 RSA key at %s.\n' "$key_path"
fi

# Stop only this Compose project and retain both named volumes.
env -u FUTU_OPEND_SHA256 LOCAL_RSA_FILE_PATH="$key_path" \
  "${compose[@]}" down ||
  die 'could not stop the existing service; interactive login was not started'

printf '%s\n' \
  'Starting the official interactive OpenD login.' \
  'Complete the official account, password, remember-password, and verification prompts yourself.' \
  'After login, this foreground OpenD process is the active API service.'

set +e
env -u FUTU_OPEND_SHA256 LOCAL_RSA_FILE_PATH="$key_path" \
  "${compose[@]}" run --rm --interactive --service-ports \
  -e FUTU_LOGIN_MODE=interactive futu-opend
interactive_status=$?
set -e

if (( interactive_status != 0 )); then
  die "interactive OpenD exited with status $interactive_status" "$interactive_status"
fi

printf '%s\n' \
  'The foreground interactive OpenD session has ended.' \
  'A later routine start can use docker compose up -d with the remembered state.'
