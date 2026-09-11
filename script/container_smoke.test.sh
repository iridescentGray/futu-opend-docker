#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/futu-container-smoke.XXXXXX")
suffix="$$-${RANDOM}"
container_name="futu-opend-smoke-${suffix}"
volume_name="futu-opend-smoke-state-${suffix}"
image_name=${SMOKE_IMAGE:-"futu-opend-smoke:test-${suffix}"}
container_created=false
volume_created=false
image_built=false

fail() {
  printf 'FAILED: container smoke: %s\n' "$1" >&2
  exit 1
}

run_timeout() {
  local seconds=$1
  shift
  python3 - "$seconds" "$@" <<'PY'
import subprocess
import sys

try:
    completed = subprocess.run(sys.argv[2:], timeout=int(sys.argv[1]), check=False)
except subprocess.TimeoutExpired:
    raise SystemExit(124)
raise SystemExit(completed.returncode)
PY
}

cleanup() {
  if [[ $container_created == true ]]; then
    run_timeout 15 docker rm -f "$container_name" >/dev/null 2>&1 || true
  fi
  if [[ $volume_created == true ]]; then
    run_timeout 15 docker volume rm "$volume_name" >/dev/null 2>&1 || true
  fi
  if [[ $image_built == true && ${SMOKE_KEEP_IMAGE:-0} != 1 ]]; then
    run_timeout 30 docker image rm "$image_name" >/dev/null 2>&1 || true
  fi
  rm -rf -- "$test_root"
}
trap cleanup EXIT HUP INT TERM

[[ $image_name =~ ^[a-zA-Z0-9._/:@-]+$ ]] || fail 'SMOKE_IMAGE contains unsupported characters'
command -v docker >/dev/null 2>&1 || fail 'docker is required'
command -v python3 >/dev/null 2>&1 || fail 'python3 is required for bounded Docker operations'
run_timeout 10 docker info >/dev/null 2>&1 || fail 'Docker daemon is unavailable'

version=''
sha256=''
while IFS= read -r field; do
  if [[ -z $version ]]; then version=$field; else sha256=$field; fi
done < <(
  python3 - "$root_dir/opend_version.json" <<'PY'
import json
import re
import sys

data = json.load(open(sys.argv[1], encoding='utf-8'))
version = data.get('stableVersion', '')
sha256 = (data.get('stableArtifact') or {}).get('sha256') or ''
if not re.fullmatch(r'\d+\.\d+\.\d+', version):
    raise SystemExit('stableVersion is invalid')
if not re.fullmatch(r'[0-9a-f]{64}', sha256):
    raise SystemExit('stableArtifact.sha256 is not locked; container smoke cannot build')
print(version)
print(sha256)
PY
)
[[ -n $version && -n $sha256 ]] || fail 'could not read locked build inputs'

if [[ ${SMOKE_SKIP_BUILD:-0} == 1 ]]; then
  run_timeout 10 docker image inspect "$image_name" >/dev/null 2>&1 || fail 'SMOKE_SKIP_BUILD=1 image does not exist'
else
  if run_timeout 10 docker image inspect "$image_name" >/dev/null 2>&1; then
    fail 'refusing to overwrite an existing SMOKE_IMAGE; use a unique tag or SMOKE_SKIP_BUILD=1'
  fi
  image_built=true
  run_timeout 1200 docker build \
    --platform linux/amd64 \
    --target runtime \
    --build-arg "FUTU_OPEND_VER=${version}" \
    --build-arg "FUTU_OPEND_SHA256=${sha256}" \
    --tag "$image_name" \
    "$root_dir"
fi

[[ $(run_timeout 10 docker image inspect --format '{{.Architecture}}' "$image_name") == amd64 ]] ||
  fail 'image architecture is not amd64'
[[ $(run_timeout 10 docker image inspect --format '{{.Config.User}}' "$image_name") == 10001:10001 ]] ||
  fail 'image runtime user is not 10001:10001'
[[ $(run_timeout 10 docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.version"}}' "$image_name") == "$version" ]] ||
  fail 'image version label does not match the locked OpenD version'

# This script is intentionally evaluated in the container.
# shellcheck disable=SC2016
run_timeout 30 docker run --rm --network none --entrypoint /bin/sh "$image_name" -eu -c '
  test "$(id -u):$(id -g)" = 10001:10001
  test -x /opt/futu-opend/FutuOpenD
  test -x /usr/local/bin/start-futu-opend
  test -x /usr/local/bin/init-futu-key
  test -r /etc/futu-opend/FutuOpenD.xml
  test "$(stat -c %a /etc/futu-opend/FutuOpenD.xml)" = 644
' || fail 'required image files, modes, or non-root identity are invalid'

set +e
run_timeout 30 docker run --rm --network none \
  --entrypoint /opt/futu-opend/FutuOpenD "$image_name" -help \
  >"$test_root/help.out" 2>"$test_root/help.err"
help_status=$?
set -e
if ((help_status == 124)); then
  printf 'FutuOpenD -help exit status: %s\n' "$help_status" >&2
  sed -n '1,80{s/^/FutuOpenD stdout: /;p;}' "$test_root/help.out" >&2
  sed -n '1,80{s/^/FutuOpenD stderr: /;p;}' "$test_root/help.err" >&2
  fail 'FutuOpenD -help timed out'
fi
for parameter in login_account login_by_remember area_code cfg_file; do
  grep -Fq "$parameter" "$test_root/help.out" "$test_root/help.err" ||
    fail "FutuOpenD -help omitted required parameter ${parameter}"
done

fake_opend="$test_root/fake-opend"
cat >"$fake_opend" <<'FAKE_OPEND'
#!/usr/bin/env bash
set -Eeuo pipefail
cfg=''
for arg in "$@"; do
  case "$arg" in -cfg_file=*) cfg=${arg#-cfg_file=} ;; esac
done
[[ -n $cfg && -r $cfg ]]
grep -Fq '<api_port>12345</api_port>' "$cfg"
printf 'SMOKE_ARGS_OK\n'
trap 'printf "SMOKE_TERM_OK\n"; exit 0' TERM INT
printf 'SMOKE_READY\n'
while :; do sleep 1 & wait $!; done
FAKE_OPEND
chmod 0755 "$fake_opend"

volume_created=true
run_timeout 10 docker volume create "$volume_name" >/dev/null
container_created=true
run_timeout 30 docker run -d \
  --name "$container_name" \
  --network none \
  --no-healthcheck \
  --mount "type=volume,source=${volume_name},target=/home/futu/.com.futunn.FutuOpenD" \
  --mount "type=bind,source=${fake_opend},target=/tmp/fake-opend,readonly" \
  -e FUTU_LOGIN_MODE=remember \
  -e FUTU_ACCOUNT_ID=smoke-fake-account \
  -e FUTU_OPEND_BIN=/tmp/fake-opend \
  -e FUTU_OPEND_RSA_FILE_PATH= \
  -e FUTU_OPEND_PORT=12345 \
  -e FUTU_OPEND_TELNET_PORT= \
  -e FUTU_OPEND_WEBSOCKET_PORT= \
  "$image_name" >/dev/null

ready=false
for _ in $(seq 1 50); do
  if run_timeout 5 docker logs "$container_name" 2>&1 | grep -Fq SMOKE_READY; then
    ready=true
    break
  fi
  sleep 0.2
done
[[ $ready == true ]] || fail 'controlled container did not become signal-ready within 10 seconds'
[[ $(run_timeout 10 docker inspect --format '{{.State.Running}}' "$container_name") == true ]] ||
  fail 'controlled container was not running at the assertion point'

run_timeout 20 docker stop --time 10 "$container_name" >/dev/null ||
  fail 'controlled container did not stop within the bounded timeout'
[[ $(run_timeout 10 docker inspect --format '{{.State.ExitCode}}' "$container_name") == 0 ]] ||
  fail 'controlled SIGTERM shutdown did not return exit code 0'
run_timeout 10 docker logs "$container_name" >"$test_root/container.log" 2>&1
grep -Fq SMOKE_ARGS_OK "$test_root/container.log" || fail 'fake OpenD did not validate custom-port XML'
grep -Fq SMOKE_TERM_OK "$test_root/container.log" || fail 'SIGTERM did not reach the fake OpenD PID 1'

password_canary='SMOKE_FAKE_PASSWORD_MUST_NOT_LEAK'
md5_canary='SMOKE_FAKE_MD5_MUST_NOT_LEAK'
if run_timeout 30 docker run --rm --network none --no-healthcheck \
  --mount "type=bind,source=${fake_opend},target=/tmp/fake-opend,readonly" \
  -e FUTU_LOGIN_MODE=remember \
  -e FUTU_ACCOUNT_ID=smoke-fake-account \
  -e FUTU_ACCOUNT_PWD="$password_canary" \
  -e FUTU_ACCOUNT_PWD_MD5="$md5_canary" \
  -e FUTU_OPEND_BIN=/tmp/fake-opend \
  -e FUTU_OPEND_RSA_FILE_PATH= \
  "$image_name" >"$test_root/reject.out" 2>"$test_root/reject.err"; then
  fail 'legacy password variables were accepted by the image wrapper'
fi
grep -Fq 'password environment variables are unsupported' "$test_root/reject.err" ||
  fail 'legacy password rejection was unclear'
for canary in "$password_canary" "$md5_canary"; do
  if grep -Fq "$canary" "$test_root/reject.out" "$test_root/reject.err" "$test_root/container.log"; then
    fail 'container output leaked a fake sensitive value'
  fi
done

printf '%s\n' \
  'PASSED: image build/inspection and controlled no-credential container smoke' \
  'NOT VERIFIED: real OpenD login, business readiness, SDK response, or market availability'
