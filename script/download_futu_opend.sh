#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

readonly DOWNLOAD_ORIGIN='https://softwaredownload.futunn.com'
readonly CONNECT_TIMEOUT_SECONDS=15
readonly TOTAL_TIMEOUT_SECONDS=180
readonly RETRY_COUNT=2
readonly RETRY_MAX_TIME_SECONDS=300

die() {
  printf 'download_futu_opend: %s\n' "$1" >&2
  exit "${2:-1}"
}

usage() {
  printf '%s\n' \
    "Usage: $0 VERSION ARCHIVE_NAME EXPECTED_SHA256" \
    "       $0 --report-tofu VERSION ARCHIVE_NAME" >&2
  exit 64
}

(( $# == 3 )) || usage

report_tofu=false
if [[ $1 == --report-tofu ]]; then
  report_tofu=true
  version=$2
  archive_name=$3
  expected_sha256=''
else
  version=$1
  archive_name=$2
  expected_sha256=$(printf '%s' "$3" | tr '[:upper:]' '[:lower:]')
fi

[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
  die 'VERSION must use the numeric X.Y.Z form' 64

expected_archive="Futu_OpenD_${version}_Ubuntu18.04.tar.gz"
[[ $archive_name == "$expected_archive" ]] || \
  die "ARCHIVE_NAME must be exactly ${expected_archive}" 64
[[ $archive_name != */* && $archive_name != *'..'* ]] || \
  die 'ARCHIVE_NAME must not contain a path or traversal component' 64
if [[ $report_tofu == false ]]; then
  [[ $expected_sha256 =~ ^[0-9a-f]{64}$ ]] || \
    die 'EXPECTED_SHA256 must be a pre-recorded 64-character hexadecimal digest' 64
fi

command -v curl >/dev/null 2>&1 || die 'curl is required'
command -v tar >/dev/null 2>&1 || die 'tar is required'

if command -v sha256sum >/dev/null 2>&1; then
  sha256_file() { sha256sum "$1" | awk '{print $1}'; }
elif command -v shasum >/dev/null 2>&1; then
  sha256_file() { shasum -a 256 "$1" | awk '{print $1}'; }
else
  die 'sha256sum or shasum is required'
fi

temp_archive=''
temp_listing=''
cleanup() {
  [[ -z $temp_archive ]] || rm -f -- "$temp_archive"
  [[ -z $temp_listing ]] || rm -f -- "$temp_listing"
}
trap cleanup EXIT HUP INT TERM

# Keep the temporary artifact next to its destination so rename is atomic.
temp_archive=$(mktemp "./.${archive_name}.part.XXXXXX")
url="${DOWNLOAD_ORIGIN}/${archive_name}"

printf 'Downloading locked OpenD artifact over HTTPS: %s\n' "$archive_name"
set +e
curl \
  --fail \
  --location \
  --proto '=https' \
  --proto-redir '=https' \
  --connect-timeout "$CONNECT_TIMEOUT_SECONDS" \
  --max-time "$TOTAL_TIMEOUT_SECONDS" \
  --retry "$RETRY_COUNT" \
  --retry-all-errors \
  --retry-delay 2 \
  --retry-max-time "$RETRY_MAX_TIME_SECONDS" \
  --silent \
  --show-error \
  --output "$temp_archive" \
  "$url"
curl_status=$?
set -e

(( curl_status == 0 )) || \
  die "HTTPS download failed after at most $((RETRY_COUNT + 1)) attempts (curl exit ${curl_status})"
[[ -s $temp_archive ]] || die 'download completed without a non-empty artifact'

actual_sha256=$(sha256_file "$temp_archive")
if [[ $report_tofu == false ]]; then
  [[ $actual_sha256 == "$expected_sha256" ]] || \
    die 'downloaded artifact does not match the pre-recorded SHA-256 digest'
fi

temp_listing=$(mktemp "./.${archive_name}.listing.XXXXXX")
tar -tzf "$temp_archive" >"$temp_listing" || \
  die 'downloaded artifact is not a readable gzip tar archive'
[[ -s $temp_listing ]] || die 'downloaded archive is empty'

expected_root="Futu_OpenD_${version}_Ubuntu18.04/"
while IFS= read -r entry; do
  entry=${entry#./}
  [[ -n $entry ]] || die 'archive contains an empty path'
  [[ $entry != /* ]] || die 'archive contains an absolute path'
  [[ $entry == "$expected_root"* ]] || \
    die "archive entry is outside the expected ${expected_root} directory"

  IFS='/' read -r -a components <<<"$entry"
  for component in "${components[@]}"; do
    [[ $component != '..' ]] || \
      die 'archive contains a parent-directory traversal component'
  done
done <"$temp_listing"

if [[ $report_tofu == true ]]; then
  printf '%s\n' \
    'TOFU candidate only: this locally calculated digest is not publisher authenticity proof.' \
    "${archive_name} ${actual_sha256}"
  exit 0
fi

mv -f -- "$temp_archive" "$archive_name"
temp_archive=''
printf 'Verified and installed %s\n' "$archive_name"
