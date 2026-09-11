#!/usr/bin/env bash

set -Eeuo pipefail

root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
gate="$root_dir/script/ci_gate.sh"
passes=0

expect_pass() {
  local name=$1 layer1=$2 layer2=$3 podman=$4 required=$5
  if LAYER1_RESULT=$layer1 LAYER2_RESULT=$layer2 PODMAN_RESULT=$podman BUILD_REQUIRED=$required \
    bash "$gate" >/dev/null 2>&1; then
    passes=$((passes + 1))
    printf 'ok %d - %s\n' "$passes" "$name"
  else
    printf 'not ok - %s\n' "$name" >&2
    exit 1
  fi
}

expect_fail() {
  local name=$1 layer1=$2 layer2=$3 podman=$4 required=$5
  if LAYER1_RESULT=$layer1 LAYER2_RESULT=$layer2 PODMAN_RESULT=$podman BUILD_REQUIRED=$required \
    bash "$gate" >/dev/null 2>&1; then
    printf 'not ok - %s\n' "$name" >&2
    exit 1
  else
    passes=$((passes + 1))
    printf 'ok %d - %s\n' "$passes" "$name"
  fi
}

expect_pass 'required runtime checks accept Docker and Podman success' success success success true
expect_pass 'classified docs-only change accepts both exact skips' success skipped skipped false
expect_fail 'upstream Layer 1 failure cannot become a successful skipped build' failure skipped skipped true
expect_fail 'required Docker Layer 2 failure is rejected' success failure success true
expect_fail 'required Podman smoke failure is rejected' success success failure true
expect_fail 'unexpected Docker success is not a docs-only skip' success success skipped false
expect_fail 'unexpected Podman success is not a docs-only skip' success skipped success false
expect_fail 'missing classification is rejected' success skipped skipped ''
expect_fail 'cancelled required Podman smoke is rejected' success success cancelled true

printf '1..%d\n' "$passes"
