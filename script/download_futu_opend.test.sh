#!/usr/bin/env bash

set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
downloader="${script_dir}/download_futu_opend.sh"
temp_root=$(mktemp -d)
trap 'rm -rf -- "$temp_root"' EXIT

passes=0
failures=0
pass() { printf 'PASSED: %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf 'FAILED: %s\n' "$1" >&2; failures=$((failures + 1)); }

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

make_fixture() {
  local destination=$1 version=$2 fixture_dir
  fixture_dir=$(mktemp -d "${temp_root}/fixture.XXXXXX")
  mkdir -p "${fixture_dir}/Futu_OpenD_${version}_Ubuntu18.04"
  printf 'controlled test payload\n' >"${fixture_dir}/Futu_OpenD_${version}_Ubuntu18.04/FutuOpenD"
  tar -czf "$destination" -C "$fixture_dir" "Futu_OpenD_${version}_Ubuntu18.04"
}

fake_bin="${temp_root}/bin"
mkdir -p "$fake_bin"
cat >"${fake_bin}/curl" <<'FAKE_CURL'
#!/usr/bin/env bash
set -eu
: "${FAKE_CURL_LOG:?}"
printf '%s\n' "$@" >"$FAKE_CURL_LOG"
output=''
while (( $# )); do
  if [[ $1 == --output ]]; then output=$2; shift 2; else shift; fi
done
[[ -n $output ]] || exit 2
[[ ${FAKE_CURL_PARTIAL:-0} != 1 ]] || printf 'partial' >"$output"
[[ ${FAKE_CURL_EXIT:-0} == 0 ]] || exit "$FAKE_CURL_EXIT"
cp -- "${FAKE_CURL_SOURCE:?}" "$output"
FAKE_CURL
chmod +x "${fake_bin}/curl"

run_case() {
  local name=$1
  shift
  local case_dir="${temp_root}/${name// /_}"
  mkdir -p "$case_dir"
  (cd "$case_dir" && PATH="${fake_bin}:$PATH" FAKE_CURL_LOG="${case_dir}/curl.args" "$@")
}

version=10.10.7008
archive="Futu_OpenD_${version}_Ubuntu18.04.tar.gz"
fixture="${temp_root}/fixture.tar.gz"
make_fixture "$fixture" "$version"
fixture_sha=$(sha256_file "$fixture")

if FAKE_CURL_SOURCE="$fixture" run_case success "$downloader" "$version" "$archive" "$fixture_sha" >/dev/null &&
  cmp -s "$fixture" "${temp_root}/success/${archive}" &&
  grep -Fxq -- '--fail' "${temp_root}/success/curl.args" &&
  grep -Fxq -- '--location' "${temp_root}/success/curl.args" &&
  grep -Fxq -- '--connect-timeout' "${temp_root}/success/curl.args" &&
  grep -Fxq -- '--max-time' "${temp_root}/success/curl.args" &&
  grep -Fxq -- '--retry' "${temp_root}/success/curl.args" &&
  [[ $(grep -Fxc -- '=https' "${temp_root}/success/curl.args") == 2 ]]; then
  pass 'HTTPS-only download uses HTTP failure, redirect, timeout and bounded-retry controls'
else
  fail 'HTTPS-only download uses HTTP failure, redirect, timeout and bounded-retry controls'
fi

for bad_version in '../10.10.7008' '10.10' 'v10.10.7008'; do
  if ! FAKE_CURL_SOURCE="$fixture" run_case "bad-version-${bad_version//\//x}" "$downloader" "$bad_version" "$archive" "$fixture_sha" >/dev/null 2>&1; then
    pass "illegal version rejected: ${bad_version}"
  else
    fail "illegal version rejected: ${bad_version}"
  fi
done

if ! FAKE_CURL_SOURCE="$fixture" run_case bad-name "$downloader" "$version" '../escape.tar.gz' "$fixture_sha" >/dev/null 2>&1; then
  pass 'unexpected or traversal archive name rejected'
else
  fail 'unexpected or traversal archive name rejected'
fi

if ! FAKE_CURL_SOURCE="$fixture" run_case bad-digest-format "$downloader" "$version" "$archive" unlocked >/dev/null 2>&1; then
  pass 'missing or malformed pre-recorded digest rejected'
else
  fail 'missing or malformed pre-recorded digest rejected'
fi

tofu_output="${temp_root}/tofu.output"
if FAKE_CURL_SOURCE="$fixture" run_case tofu "$downloader" --report-tofu "$version" "$archive" >"$tofu_output" &&
  grep -Fq 'not publisher authenticity proof' "$tofu_output" &&
  grep -Fq "$fixture_sha" "$tofu_output" &&
  [[ ! -e "${temp_root}/tofu/${archive}" ]] &&
  ! find "${temp_root}/tofu" -name '*.part.*' -print -quit | grep -q .; then
  pass 'TOFU report validates a temporary artifact without installing or overstating it'
else
  fail 'TOFU report validates a temporary artifact without installing or overstating it'
fi

for code in 22 28; do
  case_dir="${temp_root}/curl-${code}"
  if ! FAKE_CURL_SOURCE="$fixture" FAKE_CURL_EXIT="$code" FAKE_CURL_PARTIAL=1 \
    run_case "curl-${code}" "$downloader" "$version" "$archive" "$fixture_sha" >/dev/null 2>&1 &&
    [[ ! -e "${case_dir}/${archive}" ]] &&
    ! find "$case_dir" -name '*.part.*' -print -quit | grep -q .; then
    pass "curl failure ${code} leaves no target or partial file"
  else
    fail "curl failure ${code} leaves no target or partial file"
  fi
done

checksum_dir="${temp_root}/checksum"
mkdir -p "$checksum_dir"
printf 'old accepted artifact\n' >"${checksum_dir}/${archive}"
zeros=$(printf '0%.0s' {1..64})
if ! (cd "$checksum_dir" && PATH="${fake_bin}:$PATH" FAKE_CURL_LOG="$checksum_dir/curl.args" \
  FAKE_CURL_SOURCE="$fixture" "$downloader" "$version" "$archive" "$zeros") >/dev/null 2>&1 &&
  grep -Fxq 'old accepted artifact' "${checksum_dir}/${archive}" &&
  ! find "$checksum_dir" -name '*.part.*' -print -quit | grep -q .; then
  pass 'checksum mismatch preserves existing target and removes temporary file'
else
  fail 'checksum mismatch preserves existing target and removes temporary file'
fi

wrong_root="${temp_root}/wrong-root.tar.gz"
wrong_dir="${temp_root}/wrong-root-src"
mkdir -p "${wrong_dir}/unexpected"
printf 'controlled test payload\n' >"${wrong_dir}/unexpected/file"
tar -czf "$wrong_root" -C "$wrong_dir" unexpected
wrong_sha=$(sha256_file "$wrong_root")
if ! FAKE_CURL_SOURCE="$wrong_root" run_case wrong-root "$downloader" "$version" "$archive" "$wrong_sha" >/dev/null 2>&1 &&
  [[ ! -e "${temp_root}/wrong-root/${archive}" ]]; then
  pass 'archive paths outside the versioned root are rejected'
else
  fail 'archive paths outside the versioned root are rejected'
fi

invalid_tar="${temp_root}/invalid.tar.gz"
printf 'not a gzip tar archive\n' >"$invalid_tar"
invalid_sha=$(sha256_file "$invalid_tar")
if ! FAKE_CURL_SOURCE="$invalid_tar" run_case invalid-tar "$downloader" "$version" "$archive" "$invalid_sha" >/dev/null 2>&1 &&
  [[ ! -e "${temp_root}/invalid-tar/${archive}" ]]; then
  pass 'invalid or truncated archive is rejected after digest verification'
else
  fail 'invalid or truncated archive is rejected after digest verification'
fi

printf '\nDownload wrapper: %d passed, %d failed\n' "$passes" "$failures"
(( failures == 0 ))
