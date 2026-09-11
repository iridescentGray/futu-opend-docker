#!/usr/bin/env bash

set -Eeuo pipefail

root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly root_dir
test_root=$(mktemp -d "${TMPDIR:-/tmp}/futu-release-test.XXXXXX")
cleanup() { rm -rf -- "$test_root"; }
trap cleanup EXIT HUP INT TERM

readonly digest=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
readonly image=ghcr.io/example/futu-opend-docker@sha256:$digest
bash "$root_dir/script/build-release-bundle.sh" \
  10.10.7008-r1 "$image" "$test_root/dist" >/dev/null

archive=$test_root/dist/futu-opend-10.10.7008-r1-linux-amd64.tar.gz
[[ -f $archive && -f $archive.sha256 ]]
(cd "$test_root/dist" && shasum -a 256 -c "${archive##*/}.sha256") >/dev/null
tar -C "$test_root" -xzf "$archive"
bundle=$(cd "$test_root/futu-opend-10.10.7008-r1-linux-amd64" && pwd)

for file in compose.yaml env.example futu-opend interactive-login.exp README.txt; do
  [[ -f $bundle/$file ]]
done
grep -Fq "FUTU_OPEND_IMAGE=$image" "$bundle/env.example"
# The Compose interpolation token is literal test data.
# shellcheck disable=SC2016
grep -Fq 'image: ${FUTU_OPEND_IMAGE:' "$bundle/compose.yaml"
if grep -Fq 'build:' "$bundle/compose.yaml"; then
  printf 'release Compose unexpectedly contains a local build\n' >&2
  exit 1
fi
grep -Fq 'run --rm --interactive --service-ports' "$bundle/futu-opend"
grep -Fq -- '-e FUTU_LOGIN_MODE=interactive futu-opend' "$bundle/futu-opend"
if grep -Fq 'down -v' "$bundle/futu-opend"; then
  printf 'release launcher contains destructive volume teardown\n' >&2
  exit 1
fi
if find "$bundle" -type f \( -name Dockerfile -o -name package.json -o -name '*.test.sh' \) | grep -q .; then
  printf 'release bundle unexpectedly contains source/build files\n' >&2
  exit 1
fi
bash -n "$bundle/futu-opend"
printf 'ok 1 - release bundle contains only operator files and a digest-pinned image\n'

cp "$bundle/env.example" "$bundle/.env"
chmod 0600 "$bundle/.env"
printf '%s\n' 'fake release key material' >"$bundle/futu.pem"
chmod 0600 "$bundle/futu.pem"
mkdir "$test_root/fake-bin"
# These variables expand only when the generated fake Docker command runs.
# shellcheck disable=SC2016
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\\n" "$*" >>"$DOCKER_CAPTURE"' \
  >"$test_root/fake-bin/docker"
chmod 0755 "$test_root/fake-bin/docker"
DOCKER_CAPTURE="$test_root/docker.args" PATH="$test_root/fake-bin:$PATH" \
  bash "$bundle/futu-opend" start
DOCKER_CAPTURE="$test_root/docker.args" PATH="$test_root/fake-bin:$PATH" \
  bash "$bundle/futu-opend" stop
grep -Fq "compose --env-file $bundle/.env -f $bundle/compose.yaml up -d" \
  "$test_root/docker.args"
grep -Fq "compose --env-file $bundle/.env -f $bundle/compose.yaml down" \
  "$test_root/docker.args"
if grep -Fq -- 'down -v' "$test_root/docker.args"; then
  printf 'release stop attempted destructive volume teardown\n' >&2
  exit 1
fi
if grep -Fq 'FUTU_LOGIN_PASSWORD' "$test_root/docker.args"; then
  printf 'wrapper-only password name reached Docker arguments\n' >&2
  exit 1
fi
printf 'ok 2 - release launcher starts and stops without exposing wrapper secrets or deleting volumes\n'

if bash "$root_dir/script/build-release-bundle.sh" \
  10.10.7008 latest "$test_root/invalid" >/dev/null 2>&1; then
  printf 'invalid unpinned image reference was accepted\n' >&2
  exit 1
fi
printf 'ok 3 - release bundle rejects unpinned image references\n'
printf '1..3\n'
