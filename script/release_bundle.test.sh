#!/usr/bin/env bash

set -Eeuo pipefail

root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly root_dir
test_root=$(mktemp -d "${TMPDIR:-/tmp}/futu-release-test.XXXXXX")
cleanup() { rm -rf -- "$test_root"; }
trap cleanup EXIT HUP INT TERM

file_mode() {
  if stat -c '%a' "$1" >/dev/null 2>&1; then
    stat -c '%a' "$1"
  else
    stat -f '%Lp' "$1"
  fi
}

verify_checksum() {
  local directory=$1 checksum_file=$2
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$directory" && sha256sum -c "$checksum_file") >/dev/null
  else
    (cd "$directory" && shasum -a 256 -c "$checksum_file") >/dev/null
  fi
}

readonly digest=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
readonly image=ghcr.io/example/futu-opend-docker@sha256:$digest
for platform in linux-amd64 macos-apple-silicon; do
  bash "$root_dir/script/build-release-bundle.sh" \
    10.10.7008-r2 "$image" "$test_root/dist" "$platform" >/dev/null
  archive=$test_root/dist/futu-opend-10.10.7008-r2-$platform.tar.gz
  [[ -f $archive && -f $archive.sha256 ]]
  verify_checksum "$test_root/dist" "${archive##*/}.sha256"
  tar -C "$test_root" -xzf "$archive"
done

linux_bundle=$(cd "$test_root/futu-opend-10.10.7008-r2-linux-amd64" && pwd)
mac_bundle=$(cd "$test_root/futu-opend-10.10.7008-r2-macos-apple-silicon" && pwd)

for bundle in "$linux_bundle" "$mac_bundle"; do
  for file in compose.yaml compose.integration.yaml container-engine.sh env.example futu-opend interactive-login.exp README.txt; do
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
  grep -Fq 'run --rm --no-deps --service-ports' "$bundle/futu-opend"
  if grep -Fq -- '--interactive' "$bundle/futu-opend"; then
    printf 'release launcher contains a Podman-incompatible Compose flag\n' >&2
    exit 1
  fi
  grep -Fq 'external: true' "$bundle/compose.integration.yaml"
  grep -Fq 'FUTU_SHARED_NETWORK' "$bundle/compose.integration.yaml"
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

for help_option in -h --help; do
  help_output=$(FUTU_CONTAINER_ENGINE=unsupported \
    FUTU_ENV_FILE="$test_root/does-not-exist" \
    bash "$linux_bundle/futu-opend" "$help_option")
  grep -Fq 'Usage:' <<<"$help_output"
  grep -Fq 'init      Perform the first interactive login' <<<"$help_output"
  grep -Fq -- '-h, --help  Show this help message and exit' <<<"$help_output"
done
if FUTU_CONTAINER_ENGINE=unsupported FUTU_ENV_FILE="$test_root/does-not-exist" \
  bash "$linux_bundle/futu-opend" unsupported-command \
  >"$test_root/invalid-command.out" 2>&1; then
  printf 'release launcher accepted an unsupported command\n' >&2
  exit 1
else
  invalid_status=$?
fi
[[ $invalid_status == 64 ]]
grep -Fq 'Usage:' "$test_root/invalid-command.out"
printf 'ok 2 - release launcher provides help without runtime prerequisites\n'

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
  'printf "%s\n" "$*" >>"$ENGINE_CAPTURE"' \
  'if [[ " $* " == *" run "* && " $* " == *" FUTU_LOGIN_MODE=interactive "* ]]; then' \
  '  printf "请输入账号\n>>> "; IFS= read -r account' \
  '  printf "请输入密码\n>>> "; IFS= read -rs password' \
  '  printf "\n请选择是否记住密码（Y代表记住，N代表不记住）\n>>> "; IFS= read -r remember' \
  'fi' \
  >"$test_root/fake-bin/docker"
cp "$test_root/fake-bin/docker" "$test_root/fake-bin/podman"
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
  "$test_root/fake-bin/podman" \
  "$test_root/fake-bin/openssl"

exercise_bundle() {
  local bundle=$1 host_os=$2 host_arch=$3 engine=$4 capture=$5
  cp "$bundle/env.example" "$bundle/.env"
  chmod 0600 "$bundle/.env"
  printf '%s\n' 'fake release key material' >"$bundle/futu.pem"
  chmod 0600 "$bundle/futu.pem"
  ENGINE_CAPTURE="$capture" FUTU_CONTAINER_ENGINE="$engine" \
    TEST_UNAME_S="$host_os" TEST_UNAME_M="$host_arch" \
    PATH="$test_root/fake-bin:$PATH" bash "$bundle/futu-opend" start
  ENGINE_CAPTURE="$capture" FUTU_CONTAINER_ENGINE="$engine" \
    TEST_UNAME_S="$host_os" TEST_UNAME_M="$host_arch" \
    PATH="$test_root/fake-bin:$PATH" bash "$bundle/futu-opend" stop
  ENGINE_CAPTURE="$capture" FUTU_CONTAINER_ENGINE="$engine" \
    TEST_UNAME_S="$host_os" TEST_UNAME_M="$host_arch" \
    PATH="$test_root/fake-bin:$PATH" bash "$bundle/futu-opend" status
  ENGINE_CAPTURE="$capture" FUTU_CONTAINER_ENGINE="$engine" \
    TEST_UNAME_S="$host_os" TEST_UNAME_M="$host_arch" \
    PATH="$test_root/fake-bin:$PATH" bash "$bundle/futu-opend" logs
  if [[ $engine == podman ]]; then
    grep -Fq 'run --rm --pull=missing --platform linux/amd64 --network none' "$capture"
    grep -Fq 'entrypoint /usr/local/bin/init-futu-key' "$capture"
    grep -Fq 'run --name futu-opend --pull=missing --platform linux/amd64' "$capture"
    grep -Fq 'FUTU_LOGIN_MODE=remember' "$capture"
    grep -Fq '127.0.0.1:11111:11111' "$capture"
    grep -Fq 'futu-opend_futu-opend-key:/.futu:ro' "$capture"
    grep -Fq 'futu-opend_futu-opend-data:/home/futu/.com.futunn.FutuOpenD' "$capture"
    grep -Fq 'stop --time 30 futu-opend' "$capture"
    grep -Fq 'ps -a --filter name=^futu-opend$' "$capture"
    grep -Fq 'logs -f futu-opend' "$capture"
  else
    grep -Fq "compose --env-file $bundle/.env -f $bundle/compose.yaml run --rm --no-deps futu-key-init" "$capture"
    grep -Fq "compose --env-file $bundle/.env -f $bundle/compose.yaml up -d --no-deps futu-opend" "$capture"
    grep -Fq "compose --env-file $bundle/.env -f $bundle/compose.yaml down" "$capture"
    grep -Fq "compose --env-file $bundle/.env -f $bundle/compose.yaml ps" "$capture"
    grep -Fq "compose --env-file $bundle/.env -f $bundle/compose.yaml logs -f futu-opend" "$capture"
  fi
  if grep -Fq -- 'down -v' "$capture"; then
    printf 'release stop attempted destructive volume teardown\n' >&2
    exit 1
  fi
  if grep -Fq 'FUTU_LOGIN_PASSWORD' "$capture"; then
    printf 'wrapper-only password name reached Docker arguments\n' >&2
    exit 1
  fi
  if [[ $engine == podman ]]; then
    if grep -Eq '(^|[[:space:]])compose([[:space:]]|$)' "$capture"; then
      printf 'Podman release launcher unexpectedly used Compose\n' >&2
      exit 1
    fi
  else
    grep -Fq 'config --quiet' "$capture"
  fi
  if grep -Fq 'compose.integration.yaml' "$capture"; then
    printf 'standalone launcher unexpectedly loaded the integration override\n' >&2
    exit 1
  fi
}

exercise_bundle "$linux_bundle" Linux x86_64 podman "$test_root/linux-podman.args"
exercise_bundle "$mac_bundle" Darwin arm64 auto "$test_root/mac-docker.args"
printf 'ok 3 - Linux Podman and macOS Docker launchers preserve key ordering and volumes\n'

run_bundle_with_tty() {
  local bundle=$1 command_name=$2 capture=$3 output=$4
  ENGINE_CAPTURE="$capture" FUTU_CONTAINER_ENGINE=podman \
    TEST_UNAME_S=Linux TEST_UNAME_M=x86_64 PATH="$test_root/fake-bin:$PATH" \
    python3 - "$bundle/futu-opend" "$command_name" "$output" <<'PY'
import os
import pty
import sys

script, command_name, output_path = sys.argv[1:]
pid, fd = pty.fork()
if pid == 0:
    os.execv('/bin/bash', ['bash', script, command_name])
output = bytearray()
while True:
    try:
        chunk = os.read(fd, 4096)
    except OSError:
        break
    if not chunk:
        break
    output.extend(chunk)
_, status = os.waitpid(pid, 0)
with open(output_path, 'wb') as stream:
    stream.write(output)
raise SystemExit(os.waitstatus_to_exitcode(status))
PY
}

printf '%s\n' \
  'FUTU_ACCOUNT_ID=fake-release-account' \
  'FUTU_LOGIN_PASSWORD=FAKE_RELEASE_PASSWORD_MUST_NOT_LEAK' \
  'FUTU_SHARED_NETWORK=trading-backend' \
  >>"$linux_bundle/.env"
run_bundle_with_tty "$linux_bundle" init "$test_root/linux-podman.args" "$test_root/init.out"
run_bundle_with_tty "$linux_bundle" reauth "$test_root/linux-podman.args" "$test_root/reauth.out"
[[ $(grep -c 'FUTU_LOGIN_MODE=interactive' "$test_root/linux-podman.args") == 2 ]]
if grep -Fq -- '--interactive' "$test_root/linux-podman.args"; then
  printf 'Podman release init used an unsupported Compose flag\n' >&2
  exit 1
fi
grep -Fq -- '--network trading-backend --network-alias futu-opend' "$test_root/linux-podman.args"
if grep -Fq 'compose.integration.yaml' "$test_root/linux-podman.args"; then
  printf 'native Podman init unexpectedly used a Compose override\n' >&2
  exit 1
fi
if grep -Fq 'FAKE_RELEASE_PASSWORD_MUST_NOT_LEAK' "$test_root/linux-podman.args" ||
  grep -Fq 'FAKE_RELEASE_PASSWORD_MUST_NOT_LEAK' "$test_root/init.out" ||
  grep -Fq 'FAKE_RELEASE_PASSWORD_MUST_NOT_LEAK' "$test_root/reauth.out"; then
  printf 'release init/reauth exposed the fake password\n' >&2
  exit 1
fi
printf 'ok 4 - all six launcher operations stay behind the engine abstraction\n'

rm -f -- "$mac_bundle/futu.pem"
ENGINE_CAPTURE="$test_root/mac-docker.args" FUTU_CONTAINER_ENGINE=docker \
  TEST_UNAME_S=Darwin TEST_UNAME_M=arm64 \
  PATH="$test_root/fake-bin:$PATH" bash "$mac_bundle/futu-opend" start >/dev/null
grep -Fqx -- '-----BEGIN RSA PRIVATE KEY-----' "$mac_bundle/futu.pem"
[[ $(file_mode "$mac_bundle/futu.pem") == 600 ]]
printf 'ok 5 - Apple Silicon launcher supports the macOS LibreSSL PKCS#1 fallback\n'

if ENGINE_CAPTURE="$test_root/mismatch.args" FUTU_CONTAINER_ENGINE=docker \
  TEST_UNAME_S=Linux TEST_UNAME_M=x86_64 \
  PATH="$test_root/fake-bin:$PATH" bash "$mac_bundle/futu-opend" status \
  >"$test_root/mismatch.out" 2>&1; then
  printf 'Apple Silicon package accepted a Linux host\n' >&2
  exit 1
fi
grep -Fq 'this release requires an Apple Silicon Mac' "$test_root/mismatch.out"
[[ ! -e $test_root/mismatch.args ]]
printf 'ok 6 - platform-specific launcher rejects a mismatched host before Docker access\n'

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
printf 'ok 7 - release builder rejects unpinned images and unsupported host platforms\n'
printf '1..7\n'
