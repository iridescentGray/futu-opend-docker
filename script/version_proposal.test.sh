#!/usr/bin/env bash

set -Eeuo pipefail

root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

python3 - "$root_dir" <<'PY'
import os
import pathlib
import subprocess
import sys
import tempfile
import textwrap

root = pathlib.Path(sys.argv[1])
workflow = (root / '.github/workflows/check-ver-update.yml').read_text()
# Execute the actual workflow body, not a second implementation of its logic.
body = textwrap.dedent(workflow.rsplit('        run: |\n', 1)[1])
files = ['opend_version.json', 'README.md', 'AGENTS.md', '.env.example']
branch = 'update-futu-opend-10.11.7108'


def run(args, cwd, env=None):
    return subprocess.run(args, cwd=cwd, env=env, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)


def git(cwd, *args):
    return run(['git', *args], cwd).stdout.strip()


cases = [
    ('new branch', None, False, False, False),
    ('existing identical metadata', 'generated', False, False, False),
    ('existing different metadata', 'older', False, False, False),
    ('open PR already exists', 'generated', True, False, False),
    ('no metadata change', None, False, True, False),
    ('PR query fails', None, False, False, True),
]
with tempfile.TemporaryDirectory(prefix='version-proposal-test-') as temp:
    base = pathlib.Path(temp)
    # Ignore host Git configuration/hooks; all commits and pushes stay here.
    os.environ.update(GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull,
                      GIT_TERMINAL_PROMPT='0')
    for index, (name, existing, open_pr, unchanged, query_fail) in enumerate(cases, 1):
        case = base / str(index)
        case.mkdir()
        remote = case / 'origin.git'
        git(case, 'init', '--bare', str(remote))
        seed = case / 'seed'
        git(case, 'init', '-b', 'main', str(seed))
        git(seed, 'config', 'user.name', 'Test')
        git(seed, 'config', 'user.email', 'test@example.invalid')
        for file in files:
            (seed / file).write_text('base\n')
        git(seed, 'add', '.')
        git(seed, 'commit', '-m', 'base')
        git(seed, 'remote', 'add', 'origin', str(remote))
        git(seed, 'push', 'origin', 'main')
        main_sha = git(seed, 'rev-parse', 'HEAD')
        old_sha = None
        if existing:
            git(seed, 'checkout', '-b', branch)
            for file in files:
                (seed / file).write_text(existing + '\n')
            # A reviewer's unrelated content must survive branch reuse.
            (seed / 'review-note.txt').write_text('retain reviewer work\n')
            git(seed, 'add', '.')
            git(seed, 'commit', '-m', 'existing proposal')
            git(seed, 'push', 'origin', branch)
            old_sha = git(seed, 'rev-parse', 'HEAD')
        checkout = case / 'checkout'
        # Match actions/checkout: shallow single-branch clone.
        git(case, 'clone', '--depth=1', '--single-branch', '--branch', 'main',
            remote.as_uri(), str(checkout))
        if not unchanged:
            for file in files:
                (checkout / file).write_text('generated\n')
        bin_dir = case / 'bin'
        bin_dir.mkdir()
        (bin_dir / 'node').write_text('''#!/usr/bin/env bash
set -euo pipefail
if [[ "$2" == *TARGET_FILES* ]]; then
  echo 'README.md AGENTS.md .env.example'
else
  printf '10.11.7108'
fi
''')
        (bin_dir / 'gh').write_text('''#!/usr/bin/env bash
set -euo pipefail
if [[ "$1 $2" == 'pr list' ]]; then
  if [[ "$QUERY_FAIL" == 1 ]]; then exit 7; fi
  printf '%s\\n' "$OPEN_PRS"
elif [[ "$1 $2" == 'pr create' ]]; then
  printf '%s\\n' "$*" >> "$PR_CALLS"
else
  exit 99
fi
''')
        for file in bin_dir.iterdir():
            file.chmod(0o755)
        calls = case / 'pr-calls'
        env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ['PATH'],
                   OPEN_PRS=str(int(open_pr)), QUERY_FAIL=str(int(query_fail)),
                   PR_CALLS=str(calls))
        result = subprocess.run(['bash', '-c', body], cwd=checkout, env=env,
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert result.returncode == (7 if query_fail else 0), (name, result.stdout, result.stderr)
        skip = open_pr or unchanged or query_fail
        assert calls.exists() == (not skip), (name, result.stdout, result.stderr)
        assert git(remote, 'rev-parse', 'main') == main_sha, name
        if skip:
            if old_sha:
                assert git(remote, 'rev-parse', branch) == old_sha, name
        else:
            for file in files:
                assert git(remote, 'show', f'{branch}:{file}') == 'generated', (name, file)
            new_sha = git(remote, 'rev-parse', branch)
            if old_sha:
                git(remote, 'merge-base', '--is-ancestor', old_sha, new_sha)
                assert git(remote, 'show', f'{branch}:review-note.txt') == 'retain reviewer work', name
                assert (new_sha == old_sha) == (existing == 'generated'), name
            assert git(checkout, 'status', '--porcelain') == '', name
        print(f'ok {index} - {name}')
print(f'1..{len(cases)}')
PY
