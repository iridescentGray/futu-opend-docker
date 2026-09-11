#!/usr/bin/env bash

set -Eeuo pipefail

layer1_result=${LAYER1_RESULT-}
layer2_result=${LAYER2_RESULT-}
build_required=${BUILD_REQUIRED-}

if [[ $layer1_result != success ]]; then
  printf 'CI gate failed: Layer 1 must succeed; got %s\n' "${layer1_result:-missing}" >&2
  exit 1
fi

case "$build_required" in
true)
  if [[ $layer2_result != success ]]; then
    printf 'CI gate failed: Layer 2 was required and must succeed; got %s\n' \
      "${layer2_result:-missing}" >&2
    exit 1
  fi
  ;;
false)
  if [[ $layer2_result != skipped ]]; then
    printf 'CI gate failed: docs-only Layer 2 must be the classified skip; got %s\n' \
      "${layer2_result:-missing}" >&2
    exit 1
  fi
  ;;
*)
  printf 'CI gate failed: Layer 2 classification is missing or invalid\n' >&2
  exit 1
  ;;
esac

printf 'PASSED: Layer 1 and required Layer 2 gates\n'
