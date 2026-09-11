#!/usr/bin/env bash

set -Eeuo pipefail

root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly root_dir
test_root=$(mktemp -d "${TMPDIR:-/tmp}/futu-release-test.XXXXXX")
cleanup() { rm -rf -- "$test_root"; }
trap cleanup EXIT HUP INT TERM

readonly digest=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
readonly image=ghcr.io/example/futu-opend-docker@sha256:$digest
for platform in linux-amd64 macos-apple-silicon; do
  bash "$root_dir/script/build-release-bundle.sh" \
    10.10.7008-r2 "$image" "$test_root/dist" "$platform" >/dev/null
  archive=$test_root/dist/futu-opend-10.10.7008-r2-$platform.tar.gz
  [[ -f $archive && -f $archive.sha256 ]]
  (cd "$test_root/dist" && shasum -a 256 -c "${archive##*/}.sha256") >/dev/null
  tar -C "$test_root" -xzf "$archive"
done

linux_bundle=$(cd "$test_root/futu-opend-10.10.7008-r2-linux-amd64" && pwd)
mac_bundle=$(cd "$test_root/futu-opend-10.10.7008-r2-macos-apple-silicon" && pwd)

for bundle in "$linux_bundle" "$mac_bundle"; do
  for file in compose.yaml env.example futu-opend interactive-login.exp README.txt; do
    [[ -f $bundle/$file ]]
  done
  grep -Fq "FUTU_OPEND_IMAGE=$image" "$bundle/env.example"
  # The Compose interpolation token is literal test data.
  # shellcheck disable=SC2016
  grep -Fq 'image: ${FUTU_OPEND_IMAGE:' "$bundle/compose.yaml"
  if grep -Fq 'build:' "$bundle/compose.yaml"; then
    printf 'release Compose unexpectedly contains a local build\n' >&2
    exit 1
  fi
  grep -Fq 'run --rm --interactive --service-ports' "$bundle/futu-opend"
  grep -Fq -- '-e FUTU_LOGIN_MODE=interactive futu-opend' "$bundle/futu-opend"
  if grep -Fq 'down -v' "$bundle/futu-opend"; then
    printf 'release launcher contains destructive volume teardown\n' >&2
    exit 1
  fi
  if grep -Fq '@@FUTU_RELEASE_HOST_PLATFORM@@' "$bundle/futu-opend"; then
    printf 'release launcher contains an unresolved host placeholder\n' >&2
    exit 1
  fi
  if find "$bundle" -type f \( -name Dockerfile -o -name package.json -o -name '*.test.sh' \) | grep -q .; then
    printf 'release bundle unexpectedly contains source/build files\n' >&2
    exit 1
  fi
  bash -n "$bundle/futu-opend"
done
grep -Fq 'release_host_platform=linux-amd64' "$linux_bundle/futu-opend"
grep -Fq 'release_host_platform=macos-apple-silicon' "$mac_bundle/futu-opend"
grep -Fq 'Linux/amd64 host' "$linux_bundle/README.txt"
grep -Fq 'macOS Apple Silicon host' "$mac_bundle/README.txt"
grep -Fq 'not a native arm64 OpenD image' "$mac_bundle/README.txt"
printf 'ok 1 - release builder creates source-free Linux and Apple Silicon host bundles\n'

mkdir "$test_root/fake-bin"
# These variables expand only when the generated fake commands run.
# shellcheck disable=SC2016
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'case "${1:-}" in' \
  '  -s) printf "%s\n" "$TEST_UNAME_S" ;;' \
  '  -m) printf "%s\n" "$TEST_UNAME_M" ;;' \
  '  *) exit 64 ;;' \
  'esac' \
  >"$test_root/fake-bin/uname"
# shellcheck disable=SC2016
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if [[ ${1:-} == compose && ${2:-} == version ]]; then exit 0; fi' \
  'if [[ ${1:-} == info ]]; then printf "linux\n"; exit 0; fi' \
  'printf "%s\n" "$*" >>"$DOCKER_CAPTURE"' \
  >"$test_root/fake-bin/docker"
# Simulate macOS LibreSSL: reject -traditional, then emit PKCS#1 by default.
# shellcheck disable=SC2016
printf '%s\n' \
  '#!/usr/bin/env bash' \
  '[[ " $* " != *" -traditional "* ]] || exit 1' \
  'output=' \
  'while (($#)); do' \
  '  if [[ $1 == -out ]]; then output=$2; break; fi' \
  '  shift' \
  'done' \
  '[[ -n $output ]] || exit 64' \
  'printf "%s\n" "-----BEGIN RSA PRIVATE KEY-----" fake "-----END RSA PRIVATE KEY-----" >"$output"' \
  >"$test_root/fake-bin/openssl"
chmod 0755 "$test_root/fake-bin/uname" "$test_root/fake-bin/docker" \
  "$test_root/fake-bin/openssl"

exercise_bundle() {
  local bundle=$1 host_os=$2 host_arch=$3 capture=$4
  cp "$bundle/env.example" "$bundle/.env"
  chmod 0600 "$bundle/.env"
  printf '%s\n' 'fake release key material' >"$bundle/futu.pem"
  chmod 0600 "$bundle/futu.pem"
  DOCKER_CAPTURE="$capture" TEST_UNAME_S="$host_os" TEST_UNAME_M="$host_arch" \
    PATH="$test_root/fake-bin:$PATH" bash "$bundle/futu-opend" start
  DOCKER_CAPTURE="$capture" TEST_UNAME_S="$host_os" TEST_UNAME_M="$host_arch" \
    PATH="$test_root/fake-bin:$PATH" bash "$bundle/futu-opend" stop
  grep -Fq "compose --env-file $bundle/.env -f $bundle/compose.yaml up -d" "$capture"
  grep -Fq "compose --env-file $bundle/.env -f $bundle/compose.yaml down" "$capture"
  if grep -Fq -- 'down -v' "$capture"; then
    printf 'release stop attempted destructive volume teardown\n' >&2
    exit 1
  fi
  if grep -Fq 'FUTU_LOGIN_PASSWORD' "$capture"; then
    printf 'wrapper-only password name reached Docker arguments\n' >&2
    exit 1
  fi
}

exercise_bundle "$linux_bundle" Linux x86_64 "$test_root/linux-docker.args"
exercise_bundle "$mac_bundle" Darwin arm64 "$test_root/mac-docker.args"
printf 'ok 2 - both host launchers start and stop without exposing secrets or deleting volumes\n'

rm -f -- "$mac_bundle/futu.pem"
DOCKER_CAPTURE="$test_root/mac-docker.args" TEST_UNAME_S=Darwin TEST_UNAME_M=arm64 \
  PATH="$test_root/fake-bin:$PATH" bash "$mac_bundle/futu-opend" start >/dev/null
grep -Fqx -- '-----BEGIN RSA PRIVATE KEY-----' "$mac_bundle/futu.pem"
[[ $(stat -f '%Lp' "$mac_bundle/futu.pem") == 600 ]]
printf 'ok 3 - Apple Silicon launcher supports the macOS LibreSSL PKCS#1 fallback\n'

if DOCKER_CAPTURE="$test_root/mismatch.args" TEST_UNAME_S=Linux TEST_UNAME_M=x86_64 \
  PATH="$test_root/fake-bin:$PATH" bash "$mac_bundle/futu-opend" status \
  >"$test_root/mismatch.out" 2>&1; then
  printf 'Apple Silicon package accepted a Linux host\n' >&2
  exit 1
fi
grep -Fq 'this release requires an Apple Silicon Mac' "$test_root/mismatch.out"
[[ ! -e $test_root/mismatch.args ]]
printf 'ok 4 - platform-specific launcher rejects a mismatched host before Docker access\n'

if bash "$root_dir/script/build-release-bundle.sh" \
  10.10.7008-r2 latest "$test_root/invalid" >/dev/null 2>&1; then
  printf 'invalid unpinned image reference was accepted\n' >&2
  exit 1
fi
if bash "$root_dir/script/build-release-bundle.sh" \
  10.10.7008-r2 "$image" "$test_root/invalid" windows-amd64 >/dev/null 2>&1; then
  printf 'unsupported release host platform was accepted\n' >&2
  exit 1
fi
printf 'ok 5 - release builder rejects unpinned images and unsupported host platforms\n'
printf '1..5\n'
