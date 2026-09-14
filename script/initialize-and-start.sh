#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077

root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly root_dir
readonly env_file=${FUTU_ENV_FILE:-$root_dir/.env}
readonly compose_file=${FUTU_COMPOSE_FILE:-$root_dir/docker-compose.yaml}
readonly integration_compose_file=$root_dir/docker-compose.integration.yaml
key_path=${LOCAL_RSA_FILE_PATH:-$root_dir/futu.pem}

# shellcheck source=script/container-engine.sh
source "$root_dir/script/container-engine.sh"

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

read_env_value() {
  local name=$1
  awk -F= -v wanted="$name" '
    $1 == wanted { value = substr($0, index($0, "=") + 1) }
    END { print value }
  ' "$env_file"
}

unquote_env_value() {
  local value=$1
  if [[ $value == \"*\" && $value == *\" ]]; then
    value=${value:1:${#value}-2}
  elif [[ $value == \'*\' && $value == *\' ]]; then
    value=${value:1:${#value}-2}
  fi
  printf '%s' "$value"
}

[[ -t 0 && -t 1 ]] ||
  die 'initialization requires a private stdin/stdout TTY' 64
[[ -f $env_file && ! -L $env_file ]] ||
  die "environment file must be a regular file, not a symlink: $env_file" 66
[[ -f $compose_file ]] || die "Compose file not found: $compose_file" 66
if [[ $(file_mode "$env_file") != 600 ]]; then
  chmod 0600 "$env_file" ||
    die 'unable to restrict the environment file to mode 0600' 77
fi
[[ $key_path != *$'\n'* && $key_path != *$'\r'* ]] ||
  die 'LOCAL_RSA_FILE_PATH must not contain line breaks' 64
if [[ $key_path != /* ]]; then
  key_path=$root_dir/${key_path#./}
fi

resolve_container_engine || exit $?
command -v openssl >/dev/null 2>&1 || die 'openssl is required' 69
command -v expect >/dev/null 2>&1 ||
  die 'expect is required for the simplified interactive login' 69

shared_network=${FUTU_SHARED_NETWORK:-$(read_env_value FUTU_SHARED_NETWORK)}
shared_network=$(unquote_env_value "${shared_network%$'\r'}")
[[ $shared_network != *$'\n'* && $shared_network != *$'\r'* ]] ||
  die 'FUTU_SHARED_NETWORK must not contain line breaks' 64
compose_files=(-f "$compose_file")
if [[ -n $shared_network ]]; then
  [[ -f $integration_compose_file ]] ||
    die "integration Compose file not found: $integration_compose_file" 66
  export FUTU_SHARED_NETWORK=$shared_network
  compose_files+=(-f "$integration_compose_file")
fi

account_id=${FUTU_ACCOUNT_ID-}
login_password=${FUTU_LOGIN_PASSWORD-}
unset FUTU_LOGIN_PASSWORD
if [[ -z $account_id ]]; then
  account_id=$(read_env_value FUTU_ACCOUNT_ID)
fi
if [[ -z $login_password ]]; then
  login_password=$(read_env_value FUTU_LOGIN_PASSWORD)
fi
account_id=${account_id%$'\r'}
login_password=${login_password%$'\r'}
for variable_name in account_id login_password; do
  variable_value=${!variable_name}
  if [[ $variable_value == \"*\" && $variable_value == *\" ]]; then
    printf -v "$variable_name" '%s' "${variable_value:1:${#variable_value}-2}"
  elif [[ $variable_value == \'*\' && $variable_value == *\' ]]; then
    printf -v "$variable_name" '%s' "${variable_value:1:${#variable_value}-2}"
  fi
done
variable_value=''
unset variable_value variable_name
[[ -n $account_id && $account_id != *$'\n'* && $account_id != *$'\r'* ]] ||
  die 'FUTU_ACCOUNT_ID must be configured for interactive login' 64
[[ $login_password != *$'\n'* && $login_password != *$'\r'* ]] ||
  die 'FUTU_LOGIN_PASSWORD must not contain line breaks' 64

bash "$root_dir/script/lock-artifact.sh" "$env_file"

compose=("${compose_cmd[@]}" --env-file "$env_file" "${compose_files[@]}")

# Validate interpolation before creating a key or stopping an existing service.
if ! (
  unset FUTU_OPEND_SHA256
  LOCAL_RSA_FILE_PATH="$key_path" validate_compose_config "${compose[@]}"
); then
  die 'Compose configuration is invalid; no service was stopped'
fi

if [[ -e $key_path || -L $key_path ]]; then
  [[ -f $key_path && ! -L $key_path ]] ||
    die 'the existing RSA key path must be a regular file, not a symlink'
  [[ $(file_mode "$key_path") == 600 ]] ||
    die 'the existing RSA key must use mode 0600; it was not modified'
else
  key_parent=${key_path%/*}
  [[ -d $key_parent && -w $key_parent ]] ||
    die 'the RSA key parent directory must already exist and be writable'
  temporary_key=$(mktemp "$key_parent/.futu-key.XXXXXX")
  cleanup_key() {
    rm -f -- "$temporary_key"
  }
  trap cleanup_key EXIT HUP INT TERM
  openssl genrsa -traditional -out "$temporary_key" 1024 >/dev/null 2>&1 ||
    die 'OpenSSL could not generate the RSA key'
  chmod 0600 "$temporary_key"
  [[ ! -e $key_path && ! -L $key_path ]] ||
    die 'the RSA key appeared during generation; refusing to overwrite it'
  mv -- "$temporary_key" "$key_path"
  trap - EXIT HUP INT TERM
  printf 'Generated a new mode-0600 RSA key at %s.\n' "$key_path"
fi

# Stop only this Compose project and retain both named volumes.
env -u FUTU_OPEND_SHA256 LOCAL_RSA_FILE_PATH="$key_path" \
  "${compose[@]}" down ||
  die 'could not stop the existing service; interactive login was not started'

# Do not depend on provider-specific depends_on condition handling. A failed
# key initializer must stop the flow before OpenD is created.
env -u FUTU_OPEND_SHA256 LOCAL_RSA_FILE_PATH="$key_path" \
  "${compose[@]}" run --rm --no-deps futu-key-init ||
  die 'RSA key initialization failed; OpenD was not started'

if [[ -n $login_password ]]; then
  password_message='The password is read from FUTU_LOGIN_PASSWORD and submitted once.'
else
  password_message='Enter the password yourself; FUTU_LOGIN_PASSWORD is unset or empty.'
fi
printf '%s\n' \
  'Starting the official interactive OpenD login.' \
  'The configured account and remember-password choice Y are filled automatically.' \
  "$password_message" \
  'When prompted for phone verification, enter only the 6 digits.' \
  'After login, this foreground OpenD process is the active API service.'

tty_state=$(stty -g) || die 'unable to read terminal settings' 74
restore_tty() {
  stty "$tty_state" 2>/dev/null || true
}
trap restore_tty EXIT
trap 'restore_tty; trap - EXIT; exit 130' HUP INT TERM
stty -echo || die 'unable to disable local terminal echo' 74

set +e
FUTU_EXPECT_ACCOUNT="$account_id" FUTU_EXPECT_PASSWORD="$login_password" \
  expect "$root_dir/script/interactive-login.exp" \
  env -u FUTU_OPEND_SHA256 LOCAL_RSA_FILE_PATH="$key_path" \
  "${compose[@]}" run --rm --no-deps --interactive --service-ports \
  -e FUTU_LOGIN_MODE=interactive futu-opend
interactive_status=$?
set -e
login_password=''
unset login_password
restore_tty
trap - EXIT HUP INT TERM

if ((interactive_status != 0)); then
  die "interactive OpenD exited with status $interactive_status" "$interactive_status"
fi

printf '%s\n' \
  'The foreground interactive OpenD session has ended.' \
  "A later routine start can use $container_engine compose with the remembered state."
