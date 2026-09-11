#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly root_dir
readonly version=${1:-}
readonly image_ref=${2:-}
readonly output_dir=${3:-$root_dir/dist}
readonly host_platform=${4:-linux-amd64}

[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+-r[1-9][0-9]*$ ]] || {
  printf 'ERROR: version must look like 10.10.7008-r1\n' >&2
  exit 64
}
[[ $image_ref =~ ^ghcr\.io/[a-z0-9._/-]+@sha256:[0-9a-f]{64}$ ]] || {
  printf 'ERROR: image must be a lowercase GHCR reference pinned by sha256 digest\n' >&2
  exit 64
}

case "$host_platform" in
linux-amd64)
  readonly readme_template=$root_dir/release/README.txt
  ;;
macos-apple-silicon)
  readonly readme_template=$root_dir/release/README.macos-apple-silicon.txt
  ;;
*)
  printf 'ERROR: host platform must be linux-amd64 or macos-apple-silicon\n' >&2
  exit 64
  ;;
esac

readonly bundle_name=futu-opend-${version}-${host_platform}
temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/futu-release.XXXXXX")
cleanup() { rm -rf -- "$temporary_dir"; }
trap cleanup EXIT HUP INT TERM

mkdir -p "$temporary_dir/$bundle_name" "$output_dir"
cp "$root_dir/release/compose.yaml" "$temporary_dir/$bundle_name/compose.yaml"
cp "$root_dir/script/container-engine.sh" \
  "$temporary_dir/$bundle_name/container-engine.sh"
sed "s|@@FUTU_RELEASE_HOST_PLATFORM@@|$host_platform|g" \
  "$root_dir/release/futu-opend" >"$temporary_dir/$bundle_name/futu-opend"
cp "$readme_template" "$temporary_dir/$bundle_name/README.txt"
cp "$root_dir/script/interactive-login.exp" \
  "$temporary_dir/$bundle_name/interactive-login.exp"
sed "s|@@FUTU_OPEND_IMAGE@@|$image_ref|g" "$root_dir/release/env.example" \
  >"$temporary_dir/$bundle_name/env.example"
chmod 0755 "$temporary_dir/$bundle_name/futu-opend" \
  "$temporary_dir/$bundle_name/interactive-login.exp"
chmod 0644 "$temporary_dir/$bundle_name/compose.yaml" \
  "$temporary_dir/$bundle_name/container-engine.sh" \
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
