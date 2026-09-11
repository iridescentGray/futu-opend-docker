#!/usr/bin/env bash

set -Eeuo pipefail

root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/futu-engine-test.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT HUP INT TERM

make_engine() {
  local directory=$1 name=$2 compose_status=$3
  mkdir -p "$directory"
  printf '%s\n' \
    '#!/bin/bash' \
    '[[ -z ${ENGINE_CAPTURE:-} ]] || printf "%s\n" "$*" >>"$ENGINE_CAPTURE"' \
    "if [[ \${1:-} == compose && \${2:-} == version ]]; then exit $compose_status; fi" \
    'exit 0' >"$directory/$name"
  chmod 0755 "$directory/$name"
}

run_case() {
  local path=$1 requested=$2 output=$3
  PATH="$path" FUTU_CONTAINER_ENGINE="$requested" /bin/bash -c '
    source "$1"
    resolve_container_engine || exit $?
    printf "%s\n" "${compose_cmd[*]}"
  ' _ "$root_dir/script/container-engine.sh" >"$output" 2>&1
}

case_dir=$test_root/docker-only
make_engine "$case_dir" docker 0
run_case "$case_dir" auto "$case_dir.out"
grep -Fxq 'docker compose' "$case_dir.out"
printf 'ok 1 - auto selects Docker when only Docker Compose is available\n'

case_dir=$test_root/podman-only
make_engine "$case_dir" podman 0
run_case "$case_dir" auto "$case_dir.out"
grep -Fxq 'podman compose' "$case_dir.out"
printf 'ok 2 - auto selects Podman when only Podman Compose is available\n'

case_dir=$test_root/both
make_engine "$case_dir" docker 0
make_engine "$case_dir" podman 0
run_case "$case_dir" auto "$case_dir.out"
grep -Fxq 'docker compose' "$case_dir.out"
printf 'ok 3 - auto prefers Docker when both Compose commands are available\n'

case_dir=$test_root/docker-without-compose
make_engine "$case_dir" docker 1
make_engine "$case_dir" podman 0
run_case "$case_dir" auto "$case_dir.out"
grep -Fxq 'podman compose' "$case_dir.out"
printf 'ok 4 - auto falls back when Docker exists without Docker Compose\n'

case_dir=$test_root/explicit
make_engine "$case_dir" docker 0
make_engine "$case_dir" podman 0
run_case "$case_dir" podman "$case_dir-podman.out"
run_case "$case_dir" docker "$case_dir-docker.out"
grep -Fxq 'podman compose' "$case_dir-podman.out"
grep -Fxq 'docker compose' "$case_dir-docker.out"
printf 'ok 5 - explicit engine selection never falls back\n'

case_dir=$test_root/invalid
mkdir -p "$case_dir"
if run_case "$case_dir" invalid "$case_dir.out"; then
  printf 'invalid engine selection succeeded\n' >&2
  exit 1
fi
grep -Fq 'must be auto, docker, or podman' "$case_dir.out"
printf 'ok 6 - invalid engine selection fails clearly\n'

case_dir=$test_root/neither
mkdir -p "$case_dir"
if run_case "$case_dir" auto "$case_dir.out"; then
  printf 'missing engines unexpectedly succeeded\n' >&2
  exit 1
fi
grep -Fq 'neither Docker Compose nor Podman Compose is available' "$case_dir.out"
printf 'ok 7 - auto fails clearly when neither Compose command is available\n'

case_dir=$test_root/explicit-missing
make_engine "$case_dir" docker 0
if run_case "$case_dir" podman "$case_dir.out"; then
  printf 'explicit missing Podman unexpectedly fell back\n' >&2
  exit 1
fi
grep -Fq 'requires podman compose' "$case_dir.out"
printf 'ok 8 - explicit mode reports a missing Compose command\n'

case_dir=$test_root/config-validation
make_engine "$case_dir" docker 0
ENGINE_CAPTURE="$case_dir-docker.args" PATH="$case_dir" /bin/bash -c '
  source "$1"
  resolve_container_engine
  validate_compose_config "${compose_cmd[@]}" --env-file fake.env -f compose.yaml
' _ "$root_dir/script/container-engine.sh"
grep -Fxq 'compose --env-file fake.env -f compose.yaml config --quiet' \
  "$case_dir-docker.args"
printf 'ok 9 - Docker configuration validation uses config --quiet\n'

case_dir=$test_root/config-validation-podman
make_engine "$case_dir" podman 0
ENGINE_CAPTURE="$case_dir-podman.args" PATH="$case_dir" /bin/bash -c '
  source "$1"
  resolve_container_engine
  validate_compose_config "${compose_cmd[@]}" --env-file fake.env -f compose.yaml
' _ "$root_dir/script/container-engine.sh"
grep -Fxq 'compose --env-file fake.env -f compose.yaml config' \
  "$case_dir-podman.args"
if grep -Fq 'config --quiet' "$case_dir-podman.args"; then
  printf 'Podman configuration validation used unsupported --quiet\n' >&2
  exit 1
fi
printf 'ok 10 - Podman configuration validation avoids unsupported --quiet\n'

printf '1..10\n'
