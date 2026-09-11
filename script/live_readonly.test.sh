#!/usr/bin/env bash

set -Eeuo pipefail

root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/futu-live-unit.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT

passes=0
pass() {
  passes=$((passes + 1))
  printf 'ok %d - %s\n' "$passes" "$1"
}
fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

python_bin=${PYTHON_BIN:-python3}
live_script="$root_dir/script/live_readonly.py"
fake_sdk="$test_root/sdk"
mkdir -p "$fake_sdk"

cat >"$fake_sdk/futu.py" <<'PY'
import os
import time

RET_OK = 0

class SysConfig:
    encrypted = False
    key_path = None

    @classmethod
    def enable_proto_encrypt(cls, enabled):
        cls.encrypted = enabled

    @classmethod
    def set_init_rsa_file(cls, path):
        cls.key_path = path

class OpenQuoteContext:
    def __init__(self, host, port):
        if os.environ.get('FAKE_LIVE_PHASE') == 'connect-timeout':
            time.sleep(2)
        with open(os.environ['FAKE_LIVE_CAPTURE'], 'w', encoding='utf-8') as output:
            output.write(f'{host}:{port} encrypted={SysConfig.encrypted}\n')

    def get_global_state(self):
        if os.environ.get('FAKE_LIVE_PHASE') == 'request-timeout':
            time.sleep(2)
        if os.environ.get('FAKE_LIVE_PHASE') == 'request-error':
            return 1, 'FAKE_SDK_PRIVATE_ERROR'
        return RET_OK, {
            'qot_logined': os.environ.get('FAKE_QOT', '1') == '1',
            'trd_logined': os.environ.get('FAKE_TRD', '0') == '1',
            'market_us': 'CLOSED',
        }

    def close(self):
        if os.environ.get('FAKE_CLOSE_FAIL') == '1':
            raise RuntimeError('FAKE_CLOSE_PRIVATE_ERROR')
        with open(os.environ['FAKE_LIVE_CLOSED'], 'w', encoding='utf-8') as output:
            output.write('closed\n')
PY

key="$test_root/test-key.pem"
key_canary='FAKE_PRIVATE_KEY_CONTENT_MUST_NOT_LEAK'
printf '%s\n' "$key_canary" >"$key"
chmod 0600 "$key"

run_live() {
  env \
    PYTHONPATH="$fake_sdk" \
    RUN_LIVE_TESTS=1 \
    FUTU_OPEND_RSA_FILE_PATH="$key" \
    FUTU_OPEND_HOST=127.0.0.1 \
    FUTU_OPEND_PORT=12345 \
    FUTU_LIVE_CONNECT_TIMEOUT=1 \
    FUTU_LIVE_REQUEST_TIMEOUT=1 \
    FUTU_ACCOUNT_PWD=FAKE_PASSWORD_MUST_NOT_LEAK \
    FUTU_ACCOUNT_PWD_MD5=FAKE_MD5_MUST_NOT_LEAK \
    FAKE_LIVE_CAPTURE="$test_root/capture" \
    FAKE_LIVE_CLOSED="$test_root/closed" \
    "$@" "$python_bin" "$live_script"
}

if RUN_LIVE_TESTS=0 PYTHONPATH="$test_root/missing-sdk" "$python_bin" "$live_script" >"$test_root/out" 2>"$test_root/err" &&
  grep -Fxq 'SKIPPED: live read-only acceptance requires RUN_LIVE_TESTS=1' "$test_root/out"; then
  pass 'default live acceptance reports SKIPPED before loading the SDK'
else
  fail 'default live acceptance did not report a clean skip'
fi

rm -f "$test_root/closed" "$test_root/capture"
if run_live env FAKE_QOT=1 FAKE_TRD=0 >"$test_root/out" 2>"$test_root/err" &&
  grep -Fq 'PASSED: live read-only GetGlobalState qot_logined=true trd_logined=false' "$test_root/out" &&
  grep -Fxq '127.0.0.1:12345 encrypted=True' "$test_root/capture" &&
  [[ -f "$test_root/closed" ]]; then
  pass 'encrypted quote-only success uses the configured client port and closes the SDK context'
else
  fail 'encrypted quote-only fake SDK acceptance failed'
fi
for canary in "$key_canary" FAKE_PASSWORD_MUST_NOT_LEAK FAKE_MD5_MUST_NOT_LEAK; do
  if grep -Fq "$canary" "$test_root/out" "$test_root/err"; then
    fail 'live acceptance leaked fake sensitive content'
  fi
done
pass 'live output omits fake password, MD5, and private-key content'

rm -f "$test_root/closed"
if ! run_live env FAKE_QOT=1 FAKE_TRD=0 FUTU_LIVE_REQUIRE_TRD_LOGIN=1 >"$test_root/out" 2>"$test_root/err" &&
  grep -Fq 'trd_logined=false' "$test_root/err" && [[ -f "$test_root/closed" ]]; then
  pass 'optional trading-login requirement fails independently and still closes the context'
else
  fail 'optional trading-login condition was not enforced'
fi

rm -f "$test_root/closed"
if ! run_live env FAKE_LIVE_PHASE=request-error >"$test_root/out" 2>"$test_root/err" &&
  ! grep -Fq 'FAKE_SDK_PRIVATE_ERROR' "$test_root/out" "$test_root/err" &&
  [[ -f "$test_root/closed" ]]; then
  pass 'SDK errors are redacted and the context is closed'
else
  fail 'SDK error handling leaked details or skipped close'
fi

if ! env RUN_LIVE_TESTS=1 FUTU_OPEND_RSA_FILE_PATH="$test_root/missing.pem" \
  "$python_bin" "$live_script" >"$test_root/out" 2>"$test_root/err" &&
  grep -Fq 'missing, not a file, or unreadable' "$test_root/err"; then
  pass 'explicit live request with a missing key fails instead of skipping'
else
  fail 'explicit live request with missing prerequisites did not fail'
fi

chmod 0644 "$key"
if ! run_live env >"$test_root/out" 2>"$test_root/err" &&
  grep -Fq 'must not grant group or other access' "$test_root/err"; then
  pass 'live key permissions reject group or other access'
else
  fail 'live acceptance allowed overly broad key permissions'
fi
chmod 0600 "$key"

if ! run_live env FAKE_LIVE_PHASE=connect-timeout >"$test_root/out" 2>"$test_root/err" &&
  grep -Fq 'live connection timed out' "$test_root/err"; then
  pass 'connection wait is bounded by its configured timeout'
else
  fail 'connection timeout was not enforced'
fi

rm -f "$test_root/closed"
if ! run_live env FAKE_LIVE_PHASE=request-timeout >"$test_root/out" 2>"$test_root/err" &&
  grep -Fq 'live request timed out' "$test_root/err" && [[ -f "$test_root/closed" ]]; then
  pass 'request wait is bounded and the context is closed after timeout'
else
  fail 'request timeout was not enforced or context was not closed'
fi

if ! run_live env FAKE_CLOSE_FAIL=1 >"$test_root/out" 2>"$test_root/err" &&
  grep -Fq 'could not be closed cleanly' "$test_root/err" &&
  ! grep -Fq 'FAKE_CLOSE_PRIVATE_ERROR' "$test_root/out" "$test_root/err"; then
  pass 'close failure is redacted and prevents a false live success'
else
  fail 'close failure was ignored, leaked, or returned success'
fi

printf '1..%d\n' "$passes"
