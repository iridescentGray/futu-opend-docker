#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INIT_SCRIPT=$ROOT_DIR/script/init-key.sh
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/futu-key-test.XXXXXX")
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

run_init() {
  env \
    FUTU_KEY_SOURCE_PATH="$SOURCE_FILE" \
    FUTU_KEY_VOLUME_DIR="$KEY_DIR" \
    FUTU_OPEND_RSA_FILE_PATH="$TARGET_FILE" \
    FUTU_KEY_TARGET_UID="$(id -u)" \
    FUTU_KEY_TARGET_GID="$(id -g)" \
    bash "$INIT_SCRIPT"
}

SOURCE_FILE=$TEST_ROOT/source.pem
KEY_DIR=$TEST_ROOT/key-volume
TARGET_FILE=$KEY_DIR/futu.pem
mkdir -p "$KEY_DIR"
cat >"$SOURCE_FILE" <<'EOF'
-----BEGIN RSA PRIVATE KEY-----
fake test payload, not an RSA credential
-----END RSA PRIVATE KEY-----
EOF
chmod 0600 "$SOURCE_FILE"
if ! run_init >"$TEST_ROOT/out" 2>"$TEST_ROOT/err"; then
  fail "valid fake key initialization failed: $(<"$TEST_ROOT/err")"
fi
if grep -Fq 'fake test payload, not an RSA credential' "$TEST_ROOT/out" "$TEST_ROOT/err"; then
  fail 'key initializer leaked fake private-key content to output'
fi
[[ -f $TARGET_FILE ]] || fail 'prepared key was not created'
[[ $(<"$TARGET_FILE") == $'-----BEGIN RSA PRIVATE KEY-----\nfake test payload, not an RSA credential\n-----END RSA PRIVATE KEY-----' ]] ||
  fail 'prepared key content does not match fake source'
if stat -c '%a' "$TARGET_FILE" >/dev/null 2>&1; then
  mode=$(stat -c '%a' "$TARGET_FILE")
  owner=$(stat -c '%u:%g' "$TARGET_FILE")
else
  mode=$(stat -f '%Lp' "$TARGET_FILE")
  owner=$(stat -f '%u:%g' "$TARGET_FILE")
fi
[[ $mode == 400 ]] || fail "expected target mode 400, got $mode"
[[ $owner == "$(id -u):$(id -g)" ]] || fail 'target UID/GID mismatch'
pass 'key is copied with requested UID/GID and mode 0400 without logging its content'

SOURCE_FILE=$TEST_ROOT/missing.pem
if run_init >"$TEST_ROOT/out" 2>"$TEST_ROOT/err"; then
  fail 'missing source key was accepted'
fi
grep -Fq 'missing or not a regular file' "$TEST_ROOT/err" ||
  fail 'missing source error was unclear'
pass 'missing key fails clearly'

SOURCE_FILE=$TEST_ROOT/source-directory
mkdir "$SOURCE_FILE"
if run_init >"$TEST_ROOT/out" 2>"$TEST_ROOT/err"; then
  fail 'directory source key was accepted'
fi
grep -Fq 'missing or not a regular file' "$TEST_ROOT/err" ||
  fail 'directory source error was unclear'
pass 'non-file key fails clearly'

SOURCE_FILE=$TEST_ROOT/permissive.pem
printf '%s\n' 'fake permissive key' >"$SOURCE_FILE"
chmod 0644 "$SOURCE_FILE"
if run_init >"$TEST_ROOT/out" 2>"$TEST_ROOT/err"; then
  fail 'permissive source key was accepted'
fi
grep -Fq 'must use mode 0600' "$TEST_ROOT/err" ||
  fail 'permissive-mode error was unclear'
pass 'overly permissive host key fails clearly'

SOURCE_FILE=$TEST_ROOT/unreadable.pem
printf '%s\n' 'fake unreadable key' >"$SOURCE_FILE"
chmod 0000 "$SOURCE_FILE"
if run_init >"$TEST_ROOT/out" 2>"$TEST_ROOT/err"; then
  fail 'unreadable source key was accepted'
fi
grep -Fq 'not readable' "$TEST_ROOT/err" ||
  fail 'unreadable-key error was unclear'
pass 'unreadable key fails clearly'

SOURCE_FILE=$TEST_ROOT/wrong-format.pem
printf '%s\n' 'not a PKCS1 PEM test fixture' >"$SOURCE_FILE"
chmod 0600 "$SOURCE_FILE"
if run_init >"$TEST_ROOT/out" 2>"$TEST_ROOT/err"; then
  fail 'wrong-format source key was accepted'
fi
grep -Fq 'must be an unencrypted PKCS#1 PEM file' "$TEST_ROOT/err" ||
  fail 'wrong-format error was unclear'
pass 'non-PKCS1 PEM input fails clearly'

SOURCE_FILE=$TEST_ROOT/encrypted.pem
cat >"$SOURCE_FILE" <<'EOF'
-----BEGIN RSA PRIVATE KEY-----
Proc-Type: 4,ENCRYPTED
fake encrypted test payload, not an RSA credential
-----END RSA PRIVATE KEY-----
EOF
chmod 0600 "$SOURCE_FILE"
if run_init >"$TEST_ROOT/out" 2>"$TEST_ROOT/err"; then
  fail 'password-encrypted fake key was accepted'
fi
grep -Fq 'must not be password-encrypted' "$TEST_ROOT/err" ||
  fail 'encrypted-key error was unclear'
pass 'password-encrypted PEM input fails clearly'

SOURCE_FILE=$TEST_ROOT/source.pem
chmod 0600 "$SOURCE_FILE"
TARGET_FILE=$TEST_ROOT/outside.pem
if run_init >"$TEST_ROOT/out" 2>"$TEST_ROOT/err"; then
  fail 'target outside key volume was accepted'
fi
grep -Fq 'direct child of the Compose key volume' "$TEST_ROOT/err" ||
  fail 'unsafe target-path error was unclear'
pass 'target path cannot escape the key volume'

printf '1..%d\n' "$PASS_COUNT"
