#!/usr/bin/env bash

set -Eeuo pipefail

root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
gate="$root_dir/script/ci_gate.sh"
passes=0

expect_pass() {
  local name=$1 layer1=$2 layer2=$3 required=$4
  if LAYER1_RESULT=$layer1 LAYER2_RESULT=$layer2 BUILD_REQUIRED=$required \
    bash "$gate" >/dev/null 2>&1; then
    passes=$((passes + 1))
    printf 'ok %d - %s\n' "$passes" "$name"
  else
    printf 'not ok - %s\n' "$name" >&2
    exit 1
  fi
}

expect_fail() {
  local name=$1 layer1=$2 layer2=$3 required=$4
  if LAYER1_RESULT=$layer1 LAYER2_RESULT=$layer2 BUILD_REQUIRED=$required \
    bash "$gate" >/dev/null 2>&1; then
    printf 'not ok - %s\n' "$name" >&2
    exit 1
  else
    passes=$((passes + 1))
    printf 'ok %d - %s\n' "$passes" "$name"
  fi
}

expect_pass 'required Layer 2 accepts only two successful layers' success success true
expect_pass 'classified docs-only change accepts the exact Layer 2 skip' success skipped false
expect_fail 'upstream Layer 1 failure cannot become a successful skipped build' failure skipped true
expect_fail 'required Layer 2 failure is rejected' success failure true
expect_fail 'unexpected Layer 2 success is not a docs-only skip' success success false
expect_fail 'missing classification is rejected' success skipped ''
expect_fail 'cancelled required Layer 2 is rejected' success cancelled true

printf '1..%d\n' "$passes"
