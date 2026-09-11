#!/usr/bin/env bash

set -Eeuo pipefail

root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script_under_test=$root_dir/script/lock-artifact.sh
test_root=$(mktemp -d "${TMPDIR:-/tmp}/futu-lock-test.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT

version=10.10.7008
archive="Futu_OpenD_${version}_Ubuntu18.04.tar.gz"
fixture_dir=$test_root/fixture
mkdir -p "$fixture_dir/Futu_OpenD_${version}_Ubuntu18.04"
printf 'controlled OpenD lock fixture\n' \
  >"$fixture_dir/Futu_OpenD_${version}_Ubuntu18.04/FutuOpenD"
fixture=$test_root/fixture.tar.gz
tar -czf "$fixture" -C "$fixture_dir" "Futu_OpenD_${version}_Ubuntu18.04"

fake_bin=$test_root/bin
mkdir "$fake_bin"
cat >"$fake_bin/curl" <<'FAKE_CURL'
#!/usr/bin/env bash
set -eu
[[ ${FAKE_CURL_FAIL:-0} == 0 ]] || exit "${FAKE_CURL_FAIL}"
output=''
while (( $# )); do
  if [[ $1 == --output ]]; then output=$2; shift 2; else shift; fi
done
[[ -n $output ]]
cp -- "${FAKE_CURL_SOURCE:?}" "$output"
FAKE_CURL
chmod 0755 "$fake_bin/curl"

mode_of() {
  if stat -c '%a' "$1" >/dev/null 2>&1; then stat -c '%a' "$1"; else stat -f '%Lp' "$1"; fi
}

accepted_env=$test_root/accepted.env
printf '%s\n' \
  'FUTU_ACCOUNT_ID=fake-lock-account' \
  'FUTU_OPEND_SHA256=' \
  >"$accepted_env"
chmod 0644 "$accepted_env"
PATH="$fake_bin:$PATH" FAKE_CURL_SOURCE="$fixture" \
  bash "$script_under_test" "$accepted_env" >"$test_root/accepted.out"
grep -Eq '^FUTU_OPEND_SHA256=[0-9a-f]{64}$' "$accepted_env"
grep -Fxq 'FUTU_ACCOUNT_ID=fake-lock-account' "$accepted_env"
[[ $(grep -c '^FUTU_OPEND_SHA256=' "$accepted_env") == 1 ]]
[[ $(mode_of "$accepted_env") == 600 ]]
grep -Fq 'not a publisher signature' "$test_root/accepted.out"
[[ ! -e "$root_dir/$archive" ]]
printf 'ok 1 - official-HTTPS fixture candidate is automatically written once with mode 0600\n'

failed_env=$test_root/failed.env
printf '%s\n' 'FUTU_OPEND_SHA256=' >"$failed_env"
set +e
PATH="$fake_bin:$PATH" FAKE_CURL_SOURCE="$fixture" FAKE_CURL_FAIL=22 \
  bash "$script_under_test" "$failed_env" >"$test_root/failed.out" 2>"$test_root/failed.err"
failed_status=$?
set -e
[[ $failed_status != 0 ]]
grep -Fxq 'FUTU_OPEND_SHA256=' "$failed_env"
grep -Fq 'official HTTPS artifact inspection failed' "$test_root/failed.err"
printf 'ok 2 - failed official download leaves the environment file unchanged\n'

existing_env=$test_root/existing.env
existing_sha=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
printf 'FUTU_OPEND_SHA256=%s\n' "$existing_sha" >"$existing_env"
chmod 0600 "$existing_env"
PATH="$fake_bin:$PATH" FAKE_CURL_SOURCE="$test_root/missing-fixture" \
  bash "$script_under_test" "$existing_env" >"$test_root/existing.out"
grep -Fxq "FUTU_OPEND_SHA256=$existing_sha" "$existing_env"
grep -Fq 'already configured' "$test_root/existing.out"
printf 'ok 3 - an existing valid lock is neither downloaded nor replaced\n'

printf '1..3\n'
