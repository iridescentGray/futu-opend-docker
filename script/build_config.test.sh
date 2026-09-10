#!/usr/bin/env bash

set -Eeuo pipefail

root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

python3 - "$root_dir" <<'PY'
import json
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
version = json.loads((root / 'opend_version.json').read_text(encoding='utf-8'))
dockerfile = (root / 'Dockerfile').read_text(encoding='utf-8')
workflow = (root / '.github/workflows/publish.yml').read_text(encoding='utf-8')
smoke = (root / 'script/container_smoke.test.sh').read_text(encoding='utf-8')

stable = version['stableVersion']
artifact = version['stableArtifact']
expected_name = f'Futu_OpenD_{stable}_Ubuntu18.04.tar.gz'
assert artifact['fileName'] == expected_name
assert artifact['url'] == f'https://softwaredownload.futunn.com/{expected_name}'
assert artifact['platform'] == 'linux/amd64'
assert artifact['sha256'] is None or re.fullmatch(r'[0-9a-f]{64}', artifact['sha256'])
print('ok 1 - version metadata binds stable version to one exact amd64 artifact')

for stage in ('build', 'runtime'):
    base = version['baseImages'][stage]
    pinned = f"{base['reference']}@{base['digest']}"
    assert pinned in dockerfile
    assert base['platform'] == 'linux/amd64'
assert dockerfile.count('FROM --platform=linux/amd64 ') == 2
print('ok 2 - both declared amd64 base manifests match the Dockerfile pins')

assert 'ARG BASE_IMG' not in dockerfile
assert 'centos:' not in dockerfile.lower()
assert 'ARG FUTU_OPEND_VER=' not in dockerfile
assert dockerfile.count(' AS runtime') == 1
assert dockerfile.rstrip().endswith('ENTRYPOINT ["/usr/local/bin/start-futu-opend"]')
print('ok 3 - one runtime target has no base selector or hidden OpenD fallback')

assert 'USER 10001:10001' in dockerfile
assert '/opt/futu-opend/FutuOpenD' in dockerfile
assert not re.search(r'chown\s+-R[^\n]*/bin', dockerfile)
assert '--platform linux/amd64' in smoke
assert '--target runtime' in smoke
assert ':ubuntu-stable' not in workflow and ':latest' not in workflow
assert 'matrix.BASE_IMG' not in workflow
print('ok 4 - runtime identity/layout and version-only amd64 publishing are explicit')
print('1..4')
PY
