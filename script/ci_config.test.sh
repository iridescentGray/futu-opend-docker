#!/usr/bin/env bash

set -Eeuo pipefail

root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

python3 - "$root_dir" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
workflow_dir = root / '.github' / 'workflows'
workflows = {path.name: path.read_text(encoding='utf-8') for path in workflow_dir.glob('*.yml')}

uses_re = re.compile(r'^\s*-?\s*uses:\s*([^\s#]+)', re.MULTILINE)
verified_pins = {
    'actions/checkout': '11bd71901bbe5b1630ceea73d27597364c9af683',
    'actions/setup-node': '49933ea5288caeca8642d1e84afbd3f7d6820020',
}
for name, text in workflows.items():
    for action in uses_re.findall(text):
        if action.startswith('./'):
            continue
        assert re.fullmatch(r'[^@\s]+@[0-9a-f]{40}', action), (name, action)
        repository, commit = action.rsplit('@', 1)
        assert verified_pins.get(repository) == commit, (name, action)
print('ok 1 - every external GitHub Action reference is pinned to a full commit SHA')

ci = workflows['ci.yml']
publish = workflows['publish.yml']
release = workflows['release.yml']
version = workflows['check-ver-update.yml']

assert 'pull_request:' in ci
assert 'packages: write' not in ci
assert 'secrets.' not in ci
assert 'persist-credentials: false' in ci
assert 'docker login' not in ci and 'docker push' not in ci
assert 'upload-artifact' not in ci
assert 'apt-get install --yes expect' in ci
print('ok 2 - PR CI is read-only, credential-free, non-publishing, and artifact-free')

assert 'LAYER1_RESULT:' in ci
assert 'LAYER2_RESULT:' in ci
assert 'BUILD_REQUIRED:' in ci
assert 'bash script/ci_gate.sh' in ci
assert 'README.md|AGENTS.md|CLAUDE.md|LICENSE|docs/*' in ci
assert 'npm run test:unit' in ci and 'npm run test:offline' in ci
print('ok 3 - aggregate gate receives all outcomes and delegates to the tested strict policy')

assert 'pull_request:' not in publish
assert 'packages: write' in publish
layer1_at = publish.index('npm run test:unit')
offline_at = publish.index('npm run test:offline')
layer2_at = publish.index('npm run test:smoke')
login_at = publish.index('docker login')
push_at = publish.index('docker push')
assert layer1_at < offline_at < layer2_at < login_at < push_at
assert 'upload-artifact' not in publish
assert 'apt-get install --yes expect' in publish
print('ok 4 - publishing is trusted-event-only and occurs after both test layers')

assert 'tags:' in release and 'v*-r*' in release
assert 'pull_request:' not in release
assert 'contents: write' in release and 'packages: write' in release
release_layer1_at = release.index('npm run test:unit')
release_offline_at = release.index('npm run test:offline')
release_layer2_at = release.index('npm run test:smoke')
release_login_at = release.index('docker login')
release_push_at = release.index('docker push')
release_bundle_at = release.index('build-release-bundle.sh')
release_create_at = release.index('gh release create')
assert release_layer1_at < release_offline_at < release_layer2_at < release_login_at < release_push_at
assert release_push_at < release_bundle_at < release_create_at
assert 'IMAGE_REF' in release and 'sha256:' in release
assert "tr '[:upper:]' '[:lower:]'" in release
assert '--notes-file "release-notes/${GITHUB_REF_NAME}.md"' in release
assert 'macos-apple-silicon.tar.gz' in release
assert 'linux-amd64.tar.gz' in release
assert 'dist macos-apple-silicon' in release
assert 'apt-get install --yes expect' in release
print('ok 5 - tagged releases publish one tested image and two digest-pinned host bundles')

assert 'AUTO_MERGE_TOKEN' not in version
assert 'gh pr merge' not in version
assert '--auto' not in version
assert 'issues: write' not in version
assert '${{ github.token }}' in version
assert 'Human review' in version
print('ok 6 - version automation uses the repository token and creates review-only PRs')

for name, text in workflows.items():
    assert '.env' not in text
    assert 'futu.pem' not in text
    assert 'upload-artifact' not in text
print('ok 7 - workflows do not collect environment, key, session, or log artifacts')
print('1..7')
PY
