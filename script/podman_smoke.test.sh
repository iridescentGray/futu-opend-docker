#!/usr/bin/env bash

set -Eeuo pipefail

root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly root_dir

# shellcheck source=script/container-engine.sh
source "$root_dir/script/container-engine.sh"
container_engine=podman

skip_or_fail() {
  if [[ ${PODMAN_SMOKE_REQUIRED:-0} == 1 ]]; then
    printf 'FAILED: %s\n' "$1" >&2
    exit 1
  fi
  printf 'SKIPPED: %s\n' "$1"
  exit 0
}

command -v podman >/dev/null 2>&1 || skip_or_fail 'podman is unavailable'
podman compose version >/dev/null 2>&1 || skip_or_fail 'podman compose is unavailable'
command -v node >/dev/null 2>&1 || skip_or_fail 'node is unavailable'
command -v openssl >/dev/null 2>&1 || skip_or_fail 'openssl is unavailable'

[[ $(podman info --format '{{.Host.Security.Rootless}}') == true ]] ||
  skip_or_fail 'the Podman smoke test requires rootless Podman'

test_root=$(mktemp -d "${TMPDIR:-/tmp}/futu-podman-smoke.XXXXXX")
project_name=futu-podman-smoke-$$
image_name=localhost/futu-opend-podman-smoke:$$
env_file=$test_root/podman.env
key_file=$test_root/futu.pem

cleanup() {
  LOCAL_RSA_FILE_PATH="$key_file" podman compose \
    --project-name "$project_name" --env-file "$env_file" \
    -f "$root_dir/release/compose.yaml" down -v >/dev/null 2>&1 || true
  podman image rm "$image_name" >/dev/null 2>&1 || true
  rm -rf -- "$test_root"
}
trap cleanup EXIT HUP INT TERM

version=$(node -e "process.stdout.write(require('$root_dir/opend_version.json').stableVersion)")
artifact_sha=$(node -e "process.stdout.write(require('$root_dir/opend_version.json').stableArtifact.sha256 || '')")
[[ $artifact_sha =~ ^[0-9a-f]{64}$ ]] ||
  skip_or_fail 'the reviewed OpenD artifact digest is unavailable'

openssl genrsa -traditional -out "$key_file" 1024 >/dev/null 2>&1
chmod 0600 "$key_file"
printf '%s\n' \
  "FUTU_OPEND_IMAGE=$image_name" \
  'FUTU_ACCOUNT_ID=fake-podman-smoke-account' \
  'FUTU_OPEND_PORT=11111' \
  "FUTU_OPEND_VER=$version" \
  "FUTU_OPEND_SHA256=$artifact_sha" >"$env_file"
chmod 0600 "$env_file"

podman build --platform linux/amd64 --target runtime \
  --build-arg "FUTU_OPEND_VER=$version" \
  --build-arg "FUTU_OPEND_SHA256=$artifact_sha" \
  --tag "$image_name" "$root_dir"
printf 'PASSED: podman build produced the locked Linux/amd64 runtime image\n'

LOCAL_RSA_FILE_PATH="$key_file" validate_compose_config podman compose \
  --project-name "$project_name-source" --env-file "$env_file" \
  -f "$root_dir/docker-compose.yaml"
printf 'PASSED: podman compose accepted the source deployment model\n'

LOCAL_RSA_FILE_PATH="$key_file" validate_compose_config podman compose \
  --project-name "$project_name" --env-file "$env_file" \
  -f "$root_dir/release/compose.yaml"
printf 'PASSED: podman compose accepted the release model\n'

LOCAL_RSA_FILE_PATH="$key_file" podman compose \
  --project-name "$project_name" --env-file "$env_file" \
  -f "$root_dir/release/compose.yaml" run --rm --no-deps futu-key-init

metadata=$(LOCAL_RSA_FILE_PATH="$key_file" podman compose \
  --project-name "$project_name" --env-file "$env_file" \
  -f "$root_dir/release/compose.yaml" run --rm --no-deps \
  --entrypoint stat futu-opend -c '%u:%g:%a' /.futu/futu.pem)
[[ $metadata == *'10001:10001:400'* ]] || {
  printf 'FAILED: rootless Podman key metadata was %s\n' "$metadata" >&2
  exit 1
}
printf 'PASSED: rootless Podman preserved uid=10001 gid=10001 mode=0400 in the named volume\n'
