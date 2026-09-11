# Layered test and acceptance model

The project has three deliberately separate test layers. Passing a lower layer
must never be reported as a real OpenD login or business-readiness result.

| Layer | Command | Prerequisites | Proves | Does not prove |
| --- | --- | --- | --- | --- |
| 1 — unit/config | `npm run test:layer1` | Node dependencies, Bash, Python, Compose CLI for config rendering; no daemon or credentials | Wrapper argv/XML/TTY/signals, permissions, download failures, version/build/Compose/CI contracts, secret-canary redaction | Image execution, real OpenD, login, API readiness |
| 2 — container smoke | `npm run test:smoke` | Linux/amd64-capable Docker daemon, network for locked build, recorded OpenD SHA-256; no credentials | Actual image build, architecture/user/files/help, wrapper validation, custom-port rendering, controlled PID-1 TERM/exit | Login, remembered session, SDK response, business readiness |
| 3 — live read-only | `npm run test:live` | Explicit `RUN_LIVE_TESTS=1`, user-initialized/logged-in OpenD, official Python SDK, matching readable RSA key | Encrypted `get_global_state()`, `qot_logined`, optional `trd_logined` | Trading unlock/order ability, paid quote rights, permanent session validity |

## Layer 1 — unit and configuration tests

Install the locked development dependency and run the complete layer:

```bash
npm ci
npm run test:layer1
```

When Node dependencies are unavailable, the shell/configuration portion remains
available as:

```bash
npm run test:offline
```

It runs the existing fake-OpenD, fake-key, local-archive/fake-curl, build-model,
rendered-Compose, fake-SDK, and CI-policy suites. Inputs live only in explicitly
created temporary directories. Tests use recognizable fake password, fake MD5,
and fake private-key canaries and fail if those values appear in captured stdout
or stderr.

Coverage includes:

- `interactive`/`remember` argv, account/area-code validation, stdin/TTY,
  child exit status, shared-state locking, and SIGTERM delivery through `exec`;
- unified initialization ordering, protected missing-key generation,
  service-port publication, one foreground OpenD process, and exit propagation;
- fake-OpenD Expect behavior for configured-account fill, optional one-time
  environment-password submission, automatic `Y`, bare six-digit phone-code
  expansion, rejected-password no-retry, missing-account failure, child-env
  removal and password-output redaction;
- fake-download TOFU candidate handling, automatic atomic mode-`0600` `.env`
  update, download failure without file changes, and existing-lock reuse;
- XML escaping, login-field absence, optional Telnet/WebSocket omission,
  special-character paths, and runtime file modes;
- key source/target type, readability, containment, UID/GID/mode, and
  content-redaction behavior;
- HTTPS-only download flags, HTTP/timeout failure, bounded retries, malformed
  inputs, SHA mismatch, invalid archive paths/content, atomic preservation, and
  TOFU-report isolation;
- bridge/host effective Compose models, custom API port propagation to the
  runtime environment, loopback client endpoint, configuration-aware health
  command, and exclusion of the wrapper-only password from container config;
- source-free release contents, archive checksum, GHCR registry-digest pin,
  image-only Compose, launcher start/stop arguments, volume preservation, and
  rejection of unpinned image references;
- Action SHA pins, PR permissions, exact skip/gate rules, publish ordering, and
  tag-only release ordering, source-free bundle creation, and review-only
  version automation;
- Layer 3 default skip, encryption enablement before client creation, configured
  custom client port, redaction, separate quote/trade conditions, timeouts, and
  SDK-context cleanup using a fake module.

Layer 1 invokes neither the Docker daemon nor Futu. Fake program and fake SDK
results are wrapper tests only.

## Layer 2 — isolated no-credential container smoke

The exact stable archive SHA-256 must first be reviewed and recorded as described
in `README.md`. The current `null` lock intentionally makes this test fail its
preflight rather than build unreviewed bytes.

On a Linux/amd64 Docker host:

```bash
npm run test:smoke
```

The script does not load `.env` or Compose, does not connect to an existing
OpenD, and passes no real account or key. It:

1. Builds the locked `runtime` target with `--platform linux/amd64` and bounded
   execution time.
2. Checks image architecture, `10001:10001`, version label, required executable
   and template paths, and template mode.
3. Runs the real binary's `-help` under `--network none` and checks only the
   documented parameters used by the wrapper.
4. Mounts a controlled fake OpenD plus a uniquely named test state volume,
   verifies custom API-port XML, asserts that the container is actually running,
   sends TERM with a timeout, and checks the resulting exit code and marker.
5. Exercises legacy-password rejection and scans captured output for fake
   password/MD5 canaries.

Every Docker operation that waits has a timeout. Cleanup tracks and removes only
the unique container, state volume, temporary directory, and image created by
that invocation. It never calls Compose teardown, volume-wide cleanup, or global
Docker prune. `SMOKE_IMAGE` may select an explicit test tag;
`SMOKE_SKIP_BUILD=1` reuses only that explicitly named existing image, and
`SMOKE_KEEP_IMAGE=1` is reserved for the trusted publish workflow.

A Layer 2 pass is reported as image/container smoke only. Exit code 0, a process
marker, config file, or TCP availability is never translated into OpenD login or
business readiness.

## Layer 3 — operator-only encrypted read-only acceptance

Public CI and default tests never enable this layer. Its default result is
explicit:

```text
SKIPPED: live read-only acceptance requires RUN_LIVE_TESTS=1
```

Before enabling it, the user must complete the documented interactive
initialization/login in a private terminal and start the normal service. The
script neither prompts for nor reads a password, verification code, account ID,
or session cache. Install the official Python SDK in a private environment using
the official `futu-api` package and record the accepted SDK version yourself.

```bash
python3 -m venv /private/path/futu-live-venv
/private/path/futu-live-venv/bin/python -m pip install futu-api
/private/path/futu-live-venv/bin/python -m pip freeze
```

Use that virtual environment's Python in the command below. Review and retain
the exact reported `futu-api` version; the project does not silently install or
upgrade it during live acceptance.

Run with exported values rather than asking an agent or public CI to load `.env`:

```bash
RUN_LIVE_TESTS=1 \
FUTU_OPEND_HOST=127.0.0.1 \
FUTU_OPEND_PORT=11111 \
FUTU_OPEND_RSA_FILE_PATH=/absolute/private/path/futu.pem \
FUTU_LIVE_CONNECT_TIMEOUT=10 \
FUTU_LIVE_REQUEST_TIMEOUT=10 \
/private/path/futu-live-venv/bin/python script/live_readonly.py
```

The key must be the same key configured in OpenD. The script always calls
`SysConfig.enable_proto_encrypt(True)` and sets that key before creating
`OpenQuoteContext`; it rejects group/other-readable key modes and has no
encryption-disable fallback. It calls only
`get_global_state()`, requires `RET_OK`, requires `qot_logined=true`, and closes
the context in `finally`. Market-state values are neither printed nor used, so a
closed market is not a failure.

Trading-server login is optional for quote-only users. To require it explicitly:

```bash
RUN_LIVE_TESTS=1 FUTU_LIVE_REQUIRE_TRD_LOGIN=1 \
FUTU_OPEND_RSA_FILE_PATH=/absolute/private/path/futu.pem \
/private/path/futu-live-venv/bin/python script/live_readonly.py
```

This only checks the returned `trd_logined` boolean. It does not create a trade
context, unlock trading, query an account, place/cancel an order, move funds, or
open paid quote permissions. Output is limited to `PASSED`/`FAILED` and the two
login booleans; SDK exception detail is suppressed. An explicit live request
with a missing SDK, key, invalid input, timeout, failed request, or unmet login
condition exits nonzero—it never converts missing prerequisites into success.

Cleanup consists only of closing the SDK quote context. The live script does not
start/stop containers, touch volumes, or modify OpenD state.

Official references:

- [Install the Python `futu-api` SDK](https://openapi.futunn.com/futu-api-doc/en/quick/demo.html)
- [SDK encryption configuration](https://openapi.futunn.com/futu-api-doc/en/ftapi/init.html)
- [`get_global_state()` result and login fields](https://openapi.futunn.com/futu-api-doc/en/quote/get-global-state.html)

## CI gates and permissions

`ci.yml` runs on pull requests with repository `contents: read` only. Layer 1
always runs, including documentation changes and fork PRs. Layer 2 runs for code,
configuration, workflow, or build changes. Its sole allowed skip is an explicit
classifier result where every changed file is `README.md`, `AGENTS.md`,
`CLAUDE.md`, `LICENSE`, or below `docs/`.

The final `ci-gate` uses `if: always()` but does not accept arbitrary `skipped`:
Layer 1 must be `success`; required Layer 2 must be `success`; docs-only Layer 2
must be exactly `skipped`. Missing outputs, upstream failure, cancellation, or an
unexpected outcome fails the gate.

`publish.yml` has no pull-request trigger. Only a push to `main` or an explicit
manual dispatch runs it. It reruns Layer 1 and Layer 2 against the exact image
tag. The trusted job has package-write permission, but it does not authenticate
to the registry until both layers pass, immediately before push. It publishes no
image when either test layer fails. Layer 3 remains `SKIPPED` and is reported
separately.

No workflow uploads `.env`, keys, state volumes, or logs as artifacts. All
external Actions are pinned to full upstream commits verified against their
release pages:

- `actions/checkout` v4.2.2 — `11bd71901bbe5b1630ceea73d27597364c9af683`
- `actions/setup-node` v4.4.0 — `49933ea5288caeca8642d1e84afbd3f7d6820020`

The scheduled version workflow uses the repository `GITHUB_TOKEN`, proposes a
human-review PR, and neither auto-merges nor deploys. Repository settings must
allow Actions to create pull requests; otherwise that final step fails and a
maintainer must open the PR manually. A high-privilege PAT is not required or
requested. GitHub may suppress follow-on workflow events for PRs created with
`GITHUB_TOKEN`; human review and an ordinary maintainer-triggered CI run remain
required before merge.

A fresh fork without package-publish credentials can still run Layer 1 and, once
the artifact lock exists and Docker/network are available, Layer 2. Publishing
is a separate trusted event and is not part of PR success.
