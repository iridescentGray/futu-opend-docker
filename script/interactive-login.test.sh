#!/usr/bin/env bash

set -Eeuo pipefail

root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
proxy=$root_dir/script/interactive-login.exp
test_root=$(mktemp -d "${TMPDIR:-/tmp}/futu-expect-test.XXXXXX")
cleanup() {
  if [[ ${KEEP_TEST_TMP:-0} == 1 ]]; then
    printf 'KEPT: %s\n' "$test_root" >&2
  else
    rm -rf -- "$test_root"
  fi
}
trap cleanup EXIT

command -v expect >/dev/null 2>&1 || {
  printf 'SKIPPED: expect is unavailable\n'
  exit 0
}

fake_opend=$test_root/fake-opend
cat >"$fake_opend" <<'FAKE_OPEND'
#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -n ${FUTU_EXPECT_PASSWORD-} || -n ${FUTU_LOGIN_PASSWORD-} ]]; then
  printf 'wrapper password leaked into fake OpenD environment\n' >&2
  exit 90
fi

printf '请输入账号\n>>> '
IFS= read -r account
printf '%s' "$account" >"${FAKE_ACCOUNT_FILE:?}"

printf '请输入密码\n>>> '
IFS= read -rs password
printf '\n'
printf '%s' "$password" >"${FAKE_PASSWORD_FILE:?}"

printf '请选择是否记住密码（Y代表记住，N代表不记住）\n>>> '
IFS= read -r remember
printf '%s' "$remember" >"${FAKE_REMEMBER_FILE:?}"

printf '命令提示: input_phone_verify_code -code=123456\n>>> '
IFS= read -r verification
printf '%s' "$verification" >"${FAKE_VERIFICATION_FILE:?}"
printf 'FAKE_LOGIN_FLOW_COMPLETE\n'
FAKE_OPEND
chmod 0755 "$fake_opend"

account_canary='fake-expect-account'
password_canary='FAKE_EXPECT_PASSWORD_MUST_NOT_LEAK'
code_canary='654321'
export FUTU_EXPECT_ACCOUNT=$account_canary
export FAKE_ACCOUNT_FILE=$test_root/account
export FAKE_PASSWORD_FILE=$test_root/password
export FAKE_REMEMBER_FILE=$test_root/remember
export FAKE_VERIFICATION_FILE=$test_root/verification

PASSWORD_CANARY=$password_canary CODE_CANARY=$code_canary \
  python3 - "$proxy" "$fake_opend" "$test_root/output" <<'PY'
import os
import pty
import sys
import time
import termios

proxy, fake_opend, output_path = sys.argv[1:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp('expect', ['expect', proxy, fake_opend])

terminal = termios.tcgetattr(fd)
terminal[3] &= ~termios.ECHO
termios.tcsetattr(fd, termios.TCSANOW, terminal)

output = bytearray()
password_sent = False
code_sent = False
while True:
    try:
        chunk = os.read(fd, 4096)
    except OSError:
        break
    if not chunk:
        break
    output.extend(chunk)
    if not password_sent and '请输入密码'.encode() in output:
        time.sleep(0.1)
        os.write(fd, os.environ['PASSWORD_CANARY'].encode() + b'\r')
        password_sent = True
    if not code_sent and '请输入 6 位手机验证码'.encode() in output:
        time.sleep(0.1)
        os.write(fd, os.environ['CODE_CANARY'].encode() + b'\r')
        code_sent = True

_, status = os.waitpid(pid, 0)
with open(output_path, 'wb') as stream:
    stream.write(output)
raise SystemExit(os.waitstatus_to_exitcode(status))
PY

[[ $(<"$FAKE_ACCOUNT_FILE") == "$account_canary" ]]
[[ $(<"$FAKE_PASSWORD_FILE") == "$password_canary" ]]
[[ $(<"$FAKE_REMEMBER_FILE") == Y ]]
[[ $(<"$FAKE_VERIFICATION_FILE") == "input_phone_verify_code -code=$code_canary" ]]
grep -Fq 'FAKE_LOGIN_FLOW_COMPLETE' "$test_root/output"
if grep -Fq "$password_canary" "$test_root/output"; then
  printf 'not ok 1 - captured output contains the fake password\n' >&2
  exit 1
fi
grep -Fq "input_phone_verify_code -code=$code_canary" "$test_root/output"
printf 'ok 1 - account and remember choice are automatic while password and bare code remain user-entered and hidden\n'

automatic_password_canary='FAKE_ENV_PASSWORD_$[]{}!#=MUST_NOT_LEAK'
automatic_code_canary='123654'
rm -f "$FAKE_ACCOUNT_FILE" "$FAKE_PASSWORD_FILE" "$FAKE_REMEMBER_FILE" \
  "$FAKE_VERIFICATION_FILE"
FUTU_EXPECT_PASSWORD=$automatic_password_canary CODE_CANARY=$automatic_code_canary \
  python3 - "$proxy" "$fake_opend" "$test_root/automatic-output" <<'PY'
import os
import pty
import sys
import time
import termios

proxy, fake_opend, output_path = sys.argv[1:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp('expect', ['expect', proxy, fake_opend])

terminal = termios.tcgetattr(fd)
terminal[3] &= ~termios.ECHO
termios.tcsetattr(fd, termios.TCSANOW, terminal)

output = bytearray()
code_sent = False
while True:
    try:
        chunk = os.read(fd, 4096)
    except OSError:
        break
    if not chunk:
        break
    output.extend(chunk)
    if not code_sent and '请输入 6 位手机验证码'.encode() in output:
        time.sleep(0.1)
        os.write(fd, os.environ['CODE_CANARY'].encode() + b'\r')
        code_sent = True

_, status = os.waitpid(pid, 0)
with open(output_path, 'wb') as stream:
    stream.write(output)
raise SystemExit(os.waitstatus_to_exitcode(status))
PY

[[ $(<"$FAKE_ACCOUNT_FILE") == "$account_canary" ]]
[[ $(<"$FAKE_PASSWORD_FILE") == "$automatic_password_canary" ]]
[[ $(<"$FAKE_REMEMBER_FILE") == Y ]]
[[ $(<"$FAKE_VERIFICATION_FILE") == "input_phone_verify_code -code=$automatic_code_canary" ]]
grep -Fq 'FAKE_LOGIN_FLOW_COMPLETE' "$test_root/automatic-output"
if grep -Fq "$automatic_password_canary" "$test_root/automatic-output"; then
  printf 'not ok 2 - captured output contains the environment password\n' >&2
  exit 1
fi
printf 'ok 2 - an environment password is submitted once and removed before fake OpenD starts\n'

set +e
FUTU_EXPECT_ACCOUNT='' expect "$proxy" "$fake_opend" \
  >"$test_root/missing.out" 2>"$test_root/missing.err"
missing_status=$?
set -e
[[ $missing_status == 64 ]]
grep -Fq 'FUTU_EXPECT_ACCOUNT is required' "$test_root/missing.err"
printf 'ok 3 - missing configured account fails before OpenD starts\n'

rejecting_opend=$test_root/rejecting-opend
cat >"$rejecting_opend" <<'REJECTING_OPEND'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '请输入账号\n>>> '
IFS= read -r account
printf '请输入密码\n>>> '
IFS= read -rs password
printf '\n密码错误\n请输入密码\n>>> '
IFS= read -rs retry
REJECTING_OPEND
chmod 0755 "$rejecting_opend"
set +e
FUTU_EXPECT_PASSWORD=$automatic_password_canary \
  expect "$proxy" "$rejecting_opend" \
  >"$test_root/rejected.out" 2>"$test_root/rejected.err"
rejected_status=$?
set -e
[[ $rejected_status == 77 ]]
grep -Fq 'automatic retry is disabled' "$test_root/rejected.err"
if grep -Fq "$automatic_password_canary" "$test_root/rejected.out" ||
  grep -Fq "$automatic_password_canary" "$test_root/rejected.err"; then
  printf 'not ok 4 - rejected password appeared in proxy output\n' >&2
  exit 1
fi
printf 'ok 4 - a rejected environment password is not retried or printed\n'

printf '1..4\n'
