#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly root_dir
readonly env_file=${1:-$root_dir/.env}
readonly version=10.10.7008
readonly archive_name="Futu_OpenD_${version}_Ubuntu18.04.tar.gz"

die() {
  printf 'ERROR: %s\n' "$1" >&2
  exit "${2:-1}"
}

[[ -f $env_file && ! -L $env_file ]] ||
  die 'the environment file must be a regular file, not a symlink' 66

current_sha=$(awk -F= '
  $1 == "FUTU_OPEND_SHA256" { value = substr($0, index($0, "=") + 1) }
  END { print value }
' "$env_file")
current_sha=${current_sha%$'\r'}

if [[ $current_sha =~ ^[0-9a-fA-F]{64}$ ]]; then
  printf 'OpenD artifact SHA-256 is already configured in %s.\n' "$env_file"
  exit 0
fi

cd "$root_dir"
set +e
tofu_output=$(bash "$root_dir/script/download_futu_opend.sh" \
  --report-tofu "$version" "$archive_name")
download_status=$?
set -e
((download_status == 0)) ||
  die "official HTTPS artifact inspection failed with status $download_status"

printf '%s\n' "$tofu_output"
candidate_sha=$(printf '%s\n' "$tofu_output" | awk -v archive="$archive_name" \
  '$1 == archive { value = $2 } END { print value }')
[[ $candidate_sha =~ ^[0-9a-f]{64}$ ]] ||
  die 'could not extract a valid SHA-256 candidate from the downloader output'

printf '%s\n' \
  'Automatically recording this TOFU consistency lock from the fixed official HTTPS origin.' \
  'This is not a publisher signature or independent authenticity proof.'

env_dir=${env_file%/*}
[[ -n $env_dir ]] || env_dir=.
temporary_env=$(mktemp "$env_dir/.futu-env.XXXXXX")
cleanup_env() {
  rm -f -- "$temporary_env"
}
trap cleanup_env EXIT HUP INT TERM

awk -v digest="$candidate_sha" '
  BEGIN { written = 0 }
  $0 ~ /^FUTU_OPEND_SHA256=/ {
    if (!written) {
      print "FUTU_OPEND_SHA256=" digest
      written = 1
    }
    next
  }
  { print }
  END {
    if (!written) print "FUTU_OPEND_SHA256=" digest
  }
' "$env_file" >"$temporary_env"
chmod 0600 "$temporary_env"
mv -- "$temporary_env" "$env_file"
trap - EXIT HUP INT TERM

printf 'Recorded the TOFU candidate in %s with mode 0600.\n' "$env_file"
printf '%s\n' \
  'For repository CI, record the same digest in opend_version.json after review.'
