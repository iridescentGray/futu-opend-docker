#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

die() {
  printf 'ERROR: %s\n' "$1" >&2
  exit "${2:-64}"
}

validate_absolute_path() {
  local name=$1
  local value=$2
  [[ -n $value && $value == /* ]] || die "$name must be an absolute path"
  [[ $value != *$'\n'* && $value != *$'\r'* ]] ||
    die "$name must not contain line breaks"
}

file_mode() {
  local path=$1
  if stat -c '%a' "$path" >/dev/null 2>&1; then
    stat -c '%a' "$path"
  else
    stat -f '%Lp' "$path"
  fi
}

file_metadata() {
  local path=$1
  if stat -c '%u:%g:%a' "$path" >/dev/null 2>&1; then
    stat -c '%u:%g:%a' "$path"
  else
    stat -f '%u:%g:%Lp' "$path"
  fi
}

source_path=${FUTU_KEY_SOURCE_PATH:-/source/futu.pem}
volume_dir=${FUTU_KEY_VOLUME_DIR:-/.futu}
target_path=${FUTU_OPEND_RSA_FILE_PATH:-/.futu/futu.pem}

validate_absolute_path FUTU_KEY_SOURCE_PATH "$source_path"
validate_absolute_path FUTU_KEY_VOLUME_DIR "$volume_dir"
validate_absolute_path FUTU_OPEND_RSA_FILE_PATH "$target_path"
[[ $target_path == "$volume_dir"/* ]] ||
  die 'FUTU_OPEND_RSA_FILE_PATH must be a direct child of the Compose key volume'

target_name=${target_path#"$volume_dir"/}
[[ -n $target_name && $target_name != . && $target_name != .. && $target_name != */* ]] ||
  die 'FUTU_OPEND_RSA_FILE_PATH must be a direct child of the Compose key volume'

[[ -f $source_path ]] || die 'the host RSA key mount is missing or not a regular file'
[[ -r $source_path ]] || die 'the host RSA key mount is not readable'
[[ -d $volume_dir && -w $volume_dir ]] ||
  die 'the Compose key volume is missing or not writable'

source_mode=$(file_mode "$source_path")
[[ $source_mode =~ ^[0-7]{3,4}$ ]] || die 'unable to determine host RSA key permissions'
[[ $source_mode == 600 ]] || die 'the host RSA key must use mode 0600'

IFS= read -r pem_header <"$source_path" || die 'the host RSA key is empty or unreadable'
[[ $pem_header == '-----BEGIN RSA PRIVATE KEY-----' ]] ||
  die 'the host RSA key must be an unencrypted PKCS#1 PEM file for OpenD'
if grep -Fq 'Proc-Type: 4,ENCRYPTED' "$source_path"; then
  die 'the host RSA key must not be password-encrypted'
fi

target_uid=${FUTU_KEY_TARGET_UID:-$(id -u futu)}
target_gid=${FUTU_KEY_TARGET_GID:-$(id -g futu)}
[[ $target_uid =~ ^[0-9]+$ && $target_gid =~ ^[0-9]+$ ]] ||
  die 'unable to determine the futu runtime UID/GID'

temporary_path=$(mktemp "$volume_dir/.futu-key.XXXXXX")
cleanup() {
  rm -f "$temporary_path"
}
trap cleanup EXIT

install -o "$target_uid" -g "$target_gid" -m 0400 "$source_path" "$temporary_path"
mv -f "$temporary_path" "$target_path"
trap - EXIT

source_fingerprint=$(cksum <"$source_path")
target_fingerprint=$(cksum <"$target_path")
[[ $source_fingerprint == "$target_fingerprint" ]] ||
  die 'the prepared RSA key does not match the host source key'
target_metadata=$(file_metadata "$target_path" 2>/dev/null || true)
[[ $target_metadata == "$target_uid:$target_gid:400" ]] ||
  die 'the prepared RSA key ownership or permissions do not match the futu runtime user'

printf 'Prepared the OpenD RSA key for the non-root runtime user.\n'
