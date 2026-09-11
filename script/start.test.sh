#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
START_SCRIPT=$ROOT_DIR/script/start.sh
TEMPLATE=$ROOT_DIR/FutuOpenD.xml
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/futu-start-test.XXXXXX")
PASS_COUNT=0

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'ok %d - %s\n' "$PASS_COUNT" "$1"
}

assert_contains() {
  local file=$1
  local expected=$2
  grep -Fq -- "$expected" "$file" ||
    fail "expected $file to contain: $expected"
}

assert_not_contains() {
  local file=$1
  local unexpected=$2
  if grep -Fq -- "$unexpected" "$file"; then
    fail "expected $file not to contain: $unexpected"
  fi
}

file_mode() {
  local file=$1
  if stat -c '%a' "$file" >/dev/null 2>&1; then
    stat -c '%a' "$file"
  else
    stat -f '%Lp' "$file"
  fi
}

new_case() {
  local name=$1
  CASE_DIR=$TEST_ROOT/$name
  HOME_DIR=$CASE_DIR/home
  BIN_DIR=$CASE_DIR/bin
  ARGS_FILE=$CASE_DIR/args
  TTY_FILE=$CASE_DIR/tty
  STDIN_FILE=$CASE_DIR/stdin
  SIGNAL_FILE=$CASE_DIR/signal
  READY_FILE=$CASE_DIR/ready
  RUNTIME_CONFIG=$CASE_DIR/runtime.xml
  RSA_FILE=$CASE_DIR/'test & <key> "quoted".pem'
  mkdir -p "$HOME_DIR" "$BIN_DIR"
  : >"$RSA_FILE"

  cat >"$BIN_DIR/flock" <<'FAKE_FLOCK'
#!/usr/bin/env bash
[[ ${FAKE_FLOCK_FAIL:-0} != 1 ]]
FAKE_FLOCK

  cat >"$BIN_DIR/FutuOpenD" <<'FAKE_OPEND'
#!/usr/bin/env bash
set -u
printf '%s\n' "$@" >"$FAKE_ARGS_FILE"
if [[ -t 0 && -t 1 ]]; then
  printf 'tty\n' >"$FAKE_TTY_FILE"
else
  printf 'not-tty\n' >"$FAKE_TTY_FILE"
fi
if [[ ${FAKE_READ_STDIN:-0} == 1 ]]; then
  IFS= read -r line
  printf '%s\n' "$line" >"$FAKE_STDIN_FILE"
fi
trap 'printf "TERM\n" >"$FAKE_SIGNAL_FILE"; exit 42' TERM
if [[ ${FAKE_WAIT:-0} == 1 ]]; then
  : >"$FAKE_READY_FILE"
  while :; do
    sleep 1
  done
fi
exit "${FAKE_EXIT_CODE:-0}"
FAKE_OPEND
  chmod +x "$BIN_DIR/flock" "$BIN_DIR/FutuOpenD"
}

run_wrapper() {
  env \
    -u FUTU_ACCOUNT_PWD \
    -u FUTU_ACCOUNT_PWD_MD5 \
    -u FUTU_ACCOUNT_AREA_CODE \
    -u FUTU_OPEND_TELNET_IP \
    -u FUTU_OPEND_TELNET_PORT \
    -u FUTU_OPEND_WEBSOCKET_IP \
    -u FUTU_OPEND_WEBSOCKET_PORT \
    HOME="$HOME_DIR" \
    PATH="$BIN_DIR:$PATH" \
    FUTU_OPEND_VERSION=10.10.7008 \
    FUTU_OPEND_BIN="$BIN_DIR/FutuOpenD" \
    FUTU_OPEND_CONFIG_TEMPLATE="$TEMPLATE" \
    FUTU_OPEND_RUNTIME_CONFIG="$RUNTIME_CONFIG" \
    FUTU_OPEND_RSA_FILE_PATH="$RSA_FILE" \
    FUTU_OPEND_IP=127.0.0.1 \
    FUTU_OPEND_PORT=11111 \
    FAKE_ARGS_FILE="$ARGS_FILE" \
    FAKE_TTY_FILE="$TTY_FILE" \
    FAKE_STDIN_FILE="$STDIN_FILE" \
    FAKE_SIGNAL_FILE="$SIGNAL_FILE" \
    FAKE_READY_FILE="$READY_FILE" \
    "$@" \
    bash "$START_SCRIPT"
}

run_wrapper_exec() {
  exec env \
    -u FUTU_ACCOUNT_PWD \
    -u FUTU_ACCOUNT_PWD_MD5 \
    -u FUTU_ACCOUNT_AREA_CODE \
    -u FUTU_OPEND_TELNET_IP \
    -u FUTU_OPEND_TELNET_PORT \
    -u FUTU_OPEND_WEBSOCKET_IP \
    -u FUTU_OPEND_WEBSOCKET_PORT \
    HOME="$HOME_DIR" \
    PATH="$BIN_DIR:$PATH" \
    FUTU_OPEND_VERSION=10.10.7008 \
    FUTU_OPEND_BIN="$BIN_DIR/FutuOpenD" \
    FUTU_OPEND_CONFIG_TEMPLATE="$TEMPLATE" \
    FUTU_OPEND_RUNTIME_CONFIG="$RUNTIME_CONFIG" \
    FUTU_OPEND_RSA_FILE_PATH="$RSA_FILE" \
    FUTU_OPEND_IP=127.0.0.1 \
    FUTU_OPEND_PORT=11111 \
    FAKE_ARGS_FILE="$ARGS_FILE" \
    FAKE_TTY_FILE="$TTY_FILE" \
    FAKE_STDIN_FILE="$STDIN_FILE" \
    FAKE_SIGNAL_FILE="$SIGNAL_FILE" \
    FAKE_READY_FILE="$READY_FILE" \
    "$@" \
    bash "$START_SCRIPT"
}

new_case remember_args
if ! run_wrapper \
  FUTU_LOGIN_MODE=remember \
  'FUTU_ACCOUNT_ID=acct + &[x]' \
  FUTU_ACCOUNT_AREA_CODE=+86 >"$CASE_DIR/out" 2>"$CASE_DIR/err"; then
  sed 's/^/wrapper stderr: /' "$CASE_DIR/err" >&2
  fail 'baseline remember-mode wrapper invocation failed'
fi
assert_contains "$ARGS_FILE" '-login_account=acct + &[x]'
assert_contains "$ARGS_FILE" '-area_code=+86'
assert_contains "$ARGS_FILE" '-login_by_remember=1'
assert_contains "$ARGS_FILE" "-cfg_file=$RUNTIME_CONFIG"
assert_not_contains "$RUNTIME_CONFIG" '<login_account>'
assert_not_contains "$RUNTIME_CONFIG" '<login_pwd'
assert_not_contains "$RUNTIME_CONFIG" '<telnet_port>'
assert_not_contains "$RUNTIME_CONFIG" '<websocket_port>'
pass 'remember mode passes documented arguments without XML credentials'

[[ $(file_mode "$RUNTIME_CONFIG") == 600 ]] || fail 'runtime XML mode must be 600'
assert_contains "$RUNTIME_CONFIG" 'test &amp; &lt;key&gt; &quot;quoted&quot;.pem'
python3 - "$RUNTIME_CONFIG" <<'PY'
import sys
import xml.etree.ElementTree as ET

ET.parse(sys.argv[1])
PY
pass 'runtime XML is mode 0600 and escapes special characters'

new_case missing_account
if run_wrapper FUTU_LOGIN_MODE=remember FUTU_ACCOUNT_ID= >"$CASE_DIR/out" 2>"$CASE_DIR/err"; then
  fail 'remember mode accepted a missing account'
fi
assert_contains "$CASE_DIR/err" 'FUTU_ACCOUNT_ID must not be empty'
pass 'remember mode rejects a missing account'

new_case legacy_password
if run_wrapper \
  FUTU_LOGIN_MODE=remember \
  FUTU_ACCOUNT_ID=fake-account \
  FUTU_ACCOUNT_PWD='do-not-print-this-value' \
  FUTU_ACCOUNT_PWD_MD5='do-not-print-this-hash' >"$CASE_DIR/out" 2>"$CASE_DIR/err"; then
  fail 'legacy password variable was accepted'
fi
assert_contains "$CASE_DIR/err" 'password environment variables are unsupported'
assert_not_contains "$CASE_DIR/err" 'do-not-print-this-value'
assert_not_contains "$CASE_DIR/err" 'do-not-print-this-hash'
assert_not_contains "$CASE_DIR/out" 'do-not-print-this-value'
assert_not_contains "$CASE_DIR/out" 'do-not-print-this-hash'
pass 'legacy password variables produce a value-free migration error'

new_case bad_mode
if run_wrapper FUTU_LOGIN_MODE=automatic >"$CASE_DIR/out" 2>"$CASE_DIR/err"; then
  fail 'invalid login mode was accepted'
fi
assert_contains "$CASE_DIR/err" 'FUTU_LOGIN_MODE must be interactive or remember'
pass 'login mode is validated as an enum'

new_case unsupported_version
if run_wrapper \
  FUTU_LOGIN_MODE=remember \
  FUTU_ACCOUNT_ID=fake-account \
  FUTU_OPEND_VERSION=10.11.9999 >"$CASE_DIR/out" 2>"$CASE_DIR/err"; then
  fail 'unsupported OpenD version was accepted'
fi
assert_contains "$CASE_DIR/err" 'this wrapper supports OpenD 10.10.7008 only'
pass 'wrapper support is limited to the reviewed OpenD version'

new_case bad_port
if run_wrapper \
  FUTU_LOGIN_MODE=remember \
  FUTU_ACCOUNT_ID=fake-account \
  FUTU_OPEND_PORT=70000 >"$CASE_DIR/out" 2>"$CASE_DIR/err"; then
  fail 'invalid API port was accepted'
fi
assert_contains "$CASE_DIR/err" 'FUTU_OPEND_PORT must be an integer from 1 to 65535'
pass 'ports are range checked'

new_case bad_path
if run_wrapper \
  FUTU_LOGIN_MODE=remember \
  FUTU_ACCOUNT_ID=fake-account \
  FUTU_OPEND_RSA_FILE_PATH=relative.pem >"$CASE_DIR/out" 2>"$CASE_DIR/err"; then
  fail 'relative RSA path was accepted'
fi
assert_contains "$CASE_DIR/err" 'FUTU_OPEND_RSA_FILE_PATH must be an absolute path'
pass 'documented path overrides must be absolute'

new_case missing_nonlocal_key
if run_wrapper \
  FUTU_LOGIN_MODE=remember \
  FUTU_ACCOUNT_ID=fake-account \
  FUTU_OPEND_IP=0.0.0.0 \
  FUTU_OPEND_RSA_FILE_PATH= >"$CASE_DIR/out" 2>"$CASE_DIR/err"; then
  fail 'non-loopback API without RSA key was accepted'
fi
assert_contains "$CASE_DIR/err" 'a readable RSA private key is required'
pass 'non-loopback API requires a readable RSA key'

new_case bad_area
if run_wrapper \
  FUTU_LOGIN_MODE=remember \
  FUTU_ACCOUNT_ID=1234567890 \
  FUTU_ACCOUNT_AREA_CODE=86 >"$CASE_DIR/out" 2>"$CASE_DIR/err"; then
  fail 'invalid area code was accepted'
fi
assert_contains "$CASE_DIR/err" 'FUTU_ACCOUNT_AREA_CODE must be a plus sign'
pass 'remember mode validates the documented area-code shape'

new_case telnet_enabled
run_wrapper \
  FUTU_LOGIN_MODE=remember \
  FUTU_ACCOUNT_ID=fake-account \
  FUTU_OPEND_TELNET_IP=127.0.0.2 \
  FUTU_OPEND_TELNET_PORT=22222 >"$CASE_DIR/out" 2>"$CASE_DIR/err"
assert_contains "$RUNTIME_CONFIG" '<telnet_ip>127.0.0.2</telnet_ip>'
assert_contains "$RUNTIME_CONFIG" '<telnet_port>22222</telnet_port>'
pass 'explicit Telnet opt-in uses its independent bind address'

new_case optional_disabled
run_wrapper \
  FUTU_LOGIN_MODE=remember \
  FUTU_ACCOUNT_ID=fake-account \
  FUTU_OPEND_TELNET_PORT= >"$CASE_DIR/out" 2>"$CASE_DIR/err"
assert_not_contains "$RUNTIME_CONFIG" '<telnet_ip>'
assert_not_contains "$RUNTIME_CONFIG" '<telnet_port>'
assert_not_contains "$RUNTIME_CONFIG" '<websocket_port>'
pass 'explicit empty values disable optional Telnet and WebSocket config'

new_case unsafe_websocket
if run_wrapper \
  FUTU_LOGIN_MODE=remember \
  FUTU_ACCOUNT_ID=fake-account \
  FUTU_OPEND_WEBSOCKET_IP=0.0.0.0 \
  FUTU_OPEND_WEBSOCKET_PORT=33333 >"$CASE_DIR/out" 2>"$CASE_DIR/err"; then
  fail 'non-loopback WebSocket without TLS was accepted'
fi
assert_contains "$CASE_DIR/err" 'non-loopback WebSocket is unsupported'
pass 'non-loopback WebSocket is rejected while TLS configuration is unavailable'

new_case no_tty
if run_wrapper FUTU_LOGIN_MODE=interactive >"$CASE_DIR/out" 2>"$CASE_DIR/err"; then
  fail 'interactive mode accepted non-TTY input'
fi
assert_contains "$CASE_DIR/err" 'interactive login requires an attached stdin and stdout TTY'
pass 'interactive mode fails clearly without a TTY'

new_case interactive_tty
export HOME="$HOME_DIR"
export PATH="$BIN_DIR:$PATH"
export FUTU_LOGIN_MODE=interactive
export FUTU_OPEND_VERSION=10.10.7008
export FUTU_OPEND_BIN="$BIN_DIR/FutuOpenD"
export FUTU_OPEND_CONFIG_TEMPLATE="$TEMPLATE"
export FUTU_OPEND_RUNTIME_CONFIG="$RUNTIME_CONFIG"
export FUTU_OPEND_RSA_FILE_PATH="$RSA_FILE"
export FUTU_OPEND_IP=127.0.0.1
export FUTU_OPEND_PORT=11111
export FUTU_OPEND_TELNET_PORT=22222
export FUTU_OPEND_WEBSOCKET_PORT=
export FAKE_ARGS_FILE="$ARGS_FILE"
export FAKE_TTY_FILE="$TTY_FILE"
export FAKE_STDIN_FILE="$STDIN_FILE"
export FAKE_SIGNAL_FILE="$SIGNAL_FILE"
unset FUTU_ACCOUNT_PWD FUTU_ACCOUNT_PWD_MD5
python3 - "$START_SCRIPT" <<'PY'
import os
import pty
import sys

pid, fd = pty.fork()
if pid == 0:
    os.execv('/bin/bash', ['bash', sys.argv[1]])
while True:
    try:
        if not os.read(fd, 4096):
            break
    except OSError:
        break
_, status = os.waitpid(pid, 0)
raise SystemExit(os.waitstatus_to_exitcode(status))
PY
[[ $(<"$TTY_FILE") == tty ]] || fail 'interactive child did not inherit a TTY'
assert_contains "$ARGS_FILE" "-cfg_file=$RUNTIME_CONFIG"
assert_not_contains "$ARGS_FILE" '-login_by_remember=1'
pass 'interactive mode preserves the TTY and avoids remembered-login arguments'

new_case stdin
printf 'fake-input\n' | run_wrapper \
  FUTU_LOGIN_MODE=remember \
  FUTU_ACCOUNT_ID=fake-account \
  FAKE_READ_STDIN=1 >"$CASE_DIR/out" 2>"$CASE_DIR/err"
[[ $(<"$STDIN_FILE") == fake-input ]] || fail 'stdin was not preserved through exec'
pass 'stdin is preserved through the wrapper'

new_case exit_status
set +e
run_wrapper \
  FUTU_LOGIN_MODE=remember \
  FUTU_ACCOUNT_ID=fake-account \
  FAKE_EXIT_CODE=23 >"$CASE_DIR/out" 2>"$CASE_DIR/err"
status=$?
set -e
[[ $status == 23 ]] || fail "expected child exit 23, got $status"
pass 'child exit status is preserved'

new_case signal
(run_wrapper_exec \
  FUTU_LOGIN_MODE=remember \
  FUTU_ACCOUNT_ID=fake-account \
  FAKE_WAIT=1) >"$CASE_DIR/out" 2>"$CASE_DIR/err" &
wrapper_pid=$!
for _ in {1..250}; do
  [[ -f "$READY_FILE" ]] && break
  sleep 0.02
done
[[ -f "$READY_FILE" ]] || fail 'fake OpenD did not become signal-ready'
kill -TERM "$wrapper_pid"
set +e
wait "$wrapper_pid"
status=$?
set -e
[[ $status == 42 ]] || fail "expected signal handler exit 42, got $status"
[[ $(<"$SIGNAL_FILE") == TERM ]] || fail 'SIGTERM did not reach fake OpenD'
pass 'exec preserves PID targeting and SIGTERM delivery'

new_case lock_conflict
if run_wrapper \
  FUTU_LOGIN_MODE=remember \
  FUTU_ACCOUNT_ID=fake-account \
  FAKE_FLOCK_FAIL=1 >"$CASE_DIR/out" 2>"$CASE_DIR/err"; then
  fail 'concurrent state lock failure was ignored'
fi
assert_contains "$CASE_DIR/err" 'another OpenD process is already using this HOME state directory'
pass 'shared-state concurrency is rejected before OpenD starts'

printf '1..%d\n' "$PASS_COUNT"
