#!/usr/bin/env bash

set -Eeuo pipefail

root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script_under_test=$root_dir/script/initialize-and-start.sh
test_root=$(mktemp -d "${TMPDIR:-/tmp}/futu-init-start-test.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT

fake_bin=$test_root/bin
mkdir -p "$fake_bin"

cat >"$fake_bin/docker" <<'FAKE_DOCKER'
#!/usr/bin/env bash
set -eu
{
  printf 'CALL\n'
  printf '%s\n' "$@"
  printf 'END\n'
} >>"${FAKE_DOCKER_LOG:?}"
for argument in "$@"; do
  if [[ $argument == run ]]; then
    printf '请输入账号\n>>> '
    IFS= read -r account
    printf '请输入密码\n>>> '
    IFS= read -rs password
    printf '%s' "$password" >"${FAKE_RECEIVED_PASSWORD_FILE:?}"
    if [[ -n ${FUTU_LOGIN_PASSWORD-} || -n ${FUTU_EXPECT_PASSWORD-} ]]; then
      printf 'password leaked into fake Docker/OpenD environment\n' >&2
      exit 90
    fi
    printf '\n请选择是否记住密码（Y代表记住，N代表不记住）\n>>> '
    IFS= read -r remember
    exit "${FAKE_INTERACTIVE_STATUS:-0}"
  fi
done
exit 0
FAKE_DOCKER

cat >"$fake_bin/openssl" <<'FAKE_OPENSSL'
#!/usr/bin/env bash
set -eu
output=''
while (( $# )); do
  if [[ $1 == -out ]]; then output=$2; shift 2; else shift; fi
done
[[ -n $output ]]
printf '%s\n' \
  '-----BEGIN RSA PRIVATE KEY-----' \
  'controlled bootstrap test payload' \
  '-----END RSA PRIVATE KEY-----' >"$output"
FAKE_OPENSSL
chmod 0755 "$fake_bin/docker" "$fake_bin/openssl"

run_with_tty() {
  local output_file=$1
  shift
  python3 - "$output_file" "$script_under_test" "$@" <<'PY'
import os
import pty
import sys

output_path, script, *arguments = sys.argv[1:]
pid, fd = pty.fork()
if pid == 0:
    os.execv('/bin/bash', ['bash', script, *arguments])

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

mode_of() {
  if stat -c '%a' "$1" >/dev/null 2>&1; then stat -c '%a' "$1"; else stat -f '%Lp' "$1"; fi
}

env_file=$test_root/test.env
password_canary='FAKE_INITIALIZE_ENV_PASSWORD_$[]{}!#=MUST_NOT_LEAK'
printf '%s\n' \
  'FUTU_ACCOUNT_ID=fake-initialize-account' \
  "FUTU_LOGIN_PASSWORD='$password_canary'" \
  'FUTU_OPEND_VER=10.10.7008' \
  'FUTU_OPEND_SHA256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
  >"$env_file"

success_dir=$test_root/success
mkdir "$success_dir"
success_log=$success_dir/docker.log
success_key=$success_dir/futu.pem
if PATH="$fake_bin:$PATH" \
  FAKE_DOCKER_LOG="$success_log" \
  FAKE_RECEIVED_PASSWORD_FILE="$success_dir/received-password" \
  FUTU_ENV_FILE="$env_file" \
  FUTU_COMPOSE_FILE="$root_dir/docker-compose.yaml" \
  LOCAL_RSA_FILE_PATH="$success_key" \
  run_with_tty "$success_dir/output"; then
  [[ -f $success_key && $(mode_of "$success_key") == 600 ]]
else
  printf 'not ok 1 - unified initialization succeeded\n' >&2
  exit 1
fi
[[ $(mode_of "$env_file") == 600 ]]

python3 - "$success_log" <<'PY'
import sys

parts = open(sys.argv[1], encoding='utf-8').read().split('CALL\n')[1:]
calls = [part.split('END\n', 1)[0].splitlines() for part in parts]
assert len(calls) == 3, calls
assert calls[0][-2:] == ['config', '--quiet'], calls[0]
assert calls[1][-1] == 'down', calls[1]
assert 'run' in calls[2] and '--rm' in calls[2] and '--interactive' in calls[2], calls[2]
assert '--service-ports' in calls[2], calls[2]
assert 'FUTU_LOGIN_MODE=interactive' in calls[2], calls[2]
PY
grep -Fq 'foreground OpenD process is the active API service' "$success_dir/output"
[[ $(<"$success_dir/received-password") == "$password_canary" ]]
if grep -Fq "$password_canary" "$success_dir/output" ||
  grep -Fq "$password_canary" "$success_log"; then
  printf 'not ok 1 - unified initialization output contains the fake password\n' >&2
  exit 1
fi
printf 'ok 1 - one command protects the env/key and runs the port-published interactive service\n'

[[ $(grep -c '^CALL$' "$success_log") == 3 ]]
printf 'ok 2 - a clean interactive exit does not launch a second OpenD container\n'

failure_dir=$test_root/failure
mkdir "$failure_dir"
failure_key=$failure_dir/futu.pem
override_password_canary='FAKE_SHELL_ENV_PASSWORD_!$[]{}#=MUST_NOT_LEAK'
printf 'existing test key\n' >"$failure_key"
chmod 0600 "$failure_key"
set +e
PATH="$fake_bin:$PATH" \
  FAKE_DOCKER_LOG="$failure_dir/docker.log" \
  FAKE_RECEIVED_PASSWORD_FILE="$failure_dir/received-password" \
  FAKE_INTERACTIVE_STATUS=23 \
  FUTU_LOGIN_PASSWORD="$override_password_canary" \
  FUTU_ENV_FILE="$env_file" \
  FUTU_COMPOSE_FILE="$root_dir/docker-compose.yaml" \
  LOCAL_RSA_FILE_PATH="$failure_key" \
  run_with_tty "$failure_dir/output"
failure_status=$?
set -e
[[ $failure_status == 23 ]]
[[ $(<"$failure_dir/received-password") == "$override_password_canary" ]]
[[ $(grep -c '^CALL$' "$failure_dir/docker.log") == 3 ]]
grep -Fq 'interactive OpenD exited with status 23' "$failure_dir/output"
if grep -Fq "$override_password_canary" "$failure_dir/output" ||
  grep -Fq "$override_password_canary" "$failure_dir/docker.log"; then
  printf 'not ok 3 - shell environment password leaked to output or Docker argv\n' >&2
  exit 1
fi
printf 'ok 3 - interactive OpenD failure is propagated without a second container\n'

printf '1..3\n'
