#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

readonly root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly version=${1:-}
readonly image_ref=${2:-}
readonly output_dir=${3:-$root_dir/dist}

[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+-r[1-9][0-9]*$ ]] || {
  printf 'ERROR: version must look like 10.10.7008-r1\n' >&2
  exit 64
}
[[ $image_ref =~ ^ghcr\.io/[a-z0-9._/-]+@sha256:[0-9a-f]{64}$ ]] || {
  printf 'ERROR: image must be a lowercase GHCR reference pinned by sha256 digest\n' >&2
  exit 64
}

readonly bundle_name=futu-opend-${version}-linux-amd64
temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/futu-release.XXXXXX")
cleanup() { rm -rf -- "$temporary_dir"; }
trap cleanup EXIT HUP INT TERM

mkdir -p "$temporary_dir/$bundle_name" "$output_dir"
cp "$root_dir/release/compose.yaml" "$temporary_dir/$bundle_name/compose.yaml"
cp "$root_dir/release/futu-opend" "$temporary_dir/$bundle_name/futu-opend"
cp "$root_dir/release/README.txt" "$temporary_dir/$bundle_name/README.txt"
cp "$root_dir/script/interactive-login.exp" \
  "$temporary_dir/$bundle_name/interactive-login.exp"
sed "s|@@FUTU_OPEND_IMAGE@@|$image_ref|g" "$root_dir/release/env.example" \
  >"$temporary_dir/$bundle_name/env.example"
chmod 0755 "$temporary_dir/$bundle_name/futu-opend" \
  "$temporary_dir/$bundle_name/interactive-login.exp"
chmod 0644 "$temporary_dir/$bundle_name/compose.yaml" \
  "$temporary_dir/$bundle_name/env.example" \
  "$temporary_dir/$bundle_name/README.txt"

readonly archive=$output_dir/$bundle_name.tar.gz
tar -C "$temporary_dir" -czf "$archive" "$bundle_name"
if command -v sha256sum >/dev/null 2>&1; then
  (cd "$output_dir" && sha256sum "${bundle_name}.tar.gz") \
    >"$archive.sha256"
else
  digest=$(shasum -a 256 "$archive" | awk '{print $1}')
  printf '%s  %s\n' "$digest" "${bundle_name}.tar.gz" >"$archive.sha256"
fi
chmod 0644 "$archive" "$archive.sha256"
printf '%s\n' "$archive"
