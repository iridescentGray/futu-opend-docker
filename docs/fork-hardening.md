# Fork hardening audit

## Baseline and scope

- Audit date: 2026-09-10 (Asia/Shanghai).
- Baseline commit: `6d7401b9694402756bd7fb43b1858694cfcf073d`
  (`🤖 Update Futu OpenD version (#112)`).
- Branch and worktree at audit start: `main`, tracking `origin/main`, clean.
- Configured remote: `origin=https://github.com/iridescentGray/futu-opend-docker`.
  The repository README and `LICENSE` retain attribution to
  `manhinhang/futu-opend-docker` / manhinhang.
- Primary target: Linux/amd64, one OpenD instance, Docker Compose, maintained
  for personal long-term use.
- Non-targets for this hardening pass: ARM, macOS, Kubernetes, multiple
  instances, Web UI, database, administration service, and strategy trading.
- The audit host was Darwin/arm64. It is not treated as evidence about the
  target platform.

Only `AGENTS.md` and this document were changed in the audit phase. No `.env`,
password, password MD5, private key, verification code, or login-cache content
was read. No login, container start, deployment, volume operation, cleanup,
image push, or remote-repository change was performed.

## Status and priority vocabulary

- **已确认**: directly supported by repository source or current official
  documentation.
- **推测**: a plausible impact or behavior derived from evidence, but not yet
  demonstrated on the target runtime.
- **未验证**: requires a Linux/amd64 binary/container check or an explicitly
  operator-run acceptance step that was not performed.
- **P0**: blocks the documented login model or creates an immediate unsafe
  default; address before attempting normal use.
- **P1**: important security, reproducibility, lifecycle, or test-isolation gap.
- **P2**: correctness, documentation, or evidence-quality gap that should be
  fixed after P0/P1 items.

## Evidence reviewed

Repository evidence included `AGENTS.md`, `LICENSE`, `Dockerfile`,
`docker-compose.yaml`, `FutuOpenD.xml`, `.env.example`, `opend_version.json`,
`package.json`, `script/start.sh`, `script/download_futu_opend.sh`, version
scripts and unit tests, Compose and Kubernetes E2E sources and helpers,
`.github/workflows/*.yml`, `README.md`, `CLAUDE.md`, `docs/E2E.md`, and the
Kubernetes documentation. Kubernetes was reviewed only to understand existing
test claims; it remains out of scope for implementation.

Official references:

- [Command Line OpenD, Futu API Doc v10.10](https://openapi.futunn.com/futu-api-doc/en/opend/opend-cmd.html)
- [命令行 OpenD，富途 API 文档 v10.10](https://openapi.futunn.com/futu-api-doc/opend/opend-cmd.html)
- [OpenD changelog](https://openapi.futunn.com/futu-api-doc/en/changelog/changelog.html)
- [OpenD operation commands](https://openapi.futunn.com/futu-api-doc/en/opend/opend-operate.html)

The v10.10 command-line page itself contains stale-looking prose saying that
ordinary use changes account/password in XML, while its configuration table no
longer lists those fields. The version-specific 10.10.7008 changelog explicitly
says account and password settings were removed from the command-line OpenD
configuration file. This conflict is recorded rather than silently resolved.

## Findings and minimal plans

### FH-01 — Login mechanism does not match the selected OpenD version

- Priority: **P0**
- Status: **已确认** for the documentation/configuration mismatch;
  **未验证** for the exact binary fallback behavior.
- Locations: `opend_version.json`; `FutuOpenD.xml:9-15`;
  `script/start.sh:5-12,30-31,50`; `docker-compose.yaml:29-33`;
  `README.md`; `docs/E2E.md`.
- Evidence: the project selects OpenD `10.10.7008`, injects
  `login_account` and `login_pwd_md5` into XML, and launches only with
  `-cfg_file`. Official v10.10 documentation says default startup is
  interactive; after a successful interactive login with password remembrance,
  subsequent startup uses `-login_account=... -login_by_remember=1`. The
  10.10.7008 changelog says account/password settings were removed from the
  command-line configuration file.
- Impact: the current entrypoint may ignore injected credentials and wait for
  interactive input, so unattended Compose startup may not log in. Treating an
  old undocumented fallback as supported would make version bumps unsafe.
- Minimum change: separate first-run interactive bootstrap from subsequent
  remembered-session startup; stop putting password material into generated
  XML; invoke only parameters listed by the matching official documentation;
  fail clearly when remembered state is unavailable. Do not automate or perform
  a real login as part of agent-run tests.
- Acceptance: on an isolated Linux/amd64 image, capture `FutuOpenD -help` and a
  no-credential startup transcript without entering credentials; assert that
  generated XML has no account/password fields. An operator may separately
  confirm the documented interactive/remembrance flow, and that result must
  remain `NOT RUN` until they report it. Any discrepancy between help output,
  docs, and behavior is recorded verbatim and not papered over.

### FH-02 — Listener defaults are broader than a personal single-host default

- Priority: **P0** for Telnet on all host interfaces; **P1** for API and the
  optional WebSocket path.
- Status: **已确认** from Compose and entrypoint configuration;
  **未验证** at runtime on Linux/amd64.
- Locations: `.env.example:5`; `docker-compose.yaml:17-39`;
  `script/start.sh:4,27-29,34-43`; `FutuOpenD.xml:1-6,32-38,56-71`.
- Evidence: Compose uses host networking and defaults `FUTU_OPEND_IP` to
  `0.0.0.0`; `start.sh` assigns that same address to both API and Telnet.
  Therefore API and the unauthenticated/plain Telnet operation surface are
  configured on every host interface. WebSocket is disabled by default, which
  is a safe default, but when enabled its entrypoint default is also
  `0.0.0.0`. Official docs say a non-local WebSocket listener requires SSL;
  this project exposes no Compose variables for its certificate/key settings.
- Impact: machines on reachable networks may access API/Telnet directly.
  Telnet operation commands include sensitive lifecycle and re-login actions.
  Host networking also bypasses the isolation implied by normal Compose port
  publishing.
- Minimum change: default API, Telnet, and WebSocket to loopback; add a distinct
  Telnet bind-address setting so widening API access does not widen Telnet;
  require explicit opt-in for non-loopback API access; reject non-loopback
  WebSocket configuration unless the documented TLS inputs are present. Keep
  WebSocket off unless explicitly needed.
- Acceptance: render a fake-value Compose model without printing secrets, then
  inspect the generated XML in an isolated container and use host-side socket
  checks to prove only the intended loopback listeners exist. Add negative
  tests for unsafe WebSocket combinations.

### FH-03 — Download transport and artifact integrity are not hardened

- Priority: **P1**
- Status: **已确认**.
- Locations: `script/download_futu_opend.sh:3-27`; `Dockerfile:11-29`.
- Evidence: the script calls `curl -k`, disabling TLS certificate
  verification. It does not use `--fail`, so HTTP error responses can be saved
  as successful downloads; extraction may fail later with a misleading error.
  It records `$?` after the `if` compound rather than preserving curl's status,
  so diagnostics are unreliable. No expected size, digest, or signature is
  checked before extraction.
- Impact: builds do not authenticate the download endpoint and cannot prove
  that the OpenD archive is the reviewed artifact. A changed or error response
  is detected late, if at all.
- Minimum change: require verified TLS, redirects, HTTP failure handling,
  bounded connect/overall timeouts, and a temporary output followed by atomic
  rename. Pin an audited SHA-256 per supported archive/version; fail closed when
  a digest is absent or mismatched.
- Acceptance: shell tests with a local HTTP fixture cover success, redirect,
  404/500, timeout, truncated content, and digest mismatch; a Linux/amd64 build
  records and verifies the expected archive digest.

### FH-04 — Version, base image, target selection, and platform are inconsistent

- Priority: **P1**
- Status: **已确认** for source inconsistencies and floating inputs;
  **未验证** for binary compatibility on the intended replacement base.
- Locations: `Dockerfile:3-43,116-121`; `docker-compose.yaml:3-12`;
  `.env.example:9`; `opend_version.json`; `README.md` build examples;
  `.github/workflows/publish.yml:46-111`.
- Evidence: Dockerfile `FUTU_OPEND_VER` defaults to `9.3.5308`, while the
  version file and example environment select `10.10.7008`. `BASE_IMG` is
  declared/passed but does not select the final stage; an unqualified build
  always ends at the Ubuntu `final` alias. CI is different because it passes an
  explicit `final-${BASE_IMG}-target`. Base image tags are mutable and package
  installation is unpinned. No build declaration enforces Linux/amd64. Ubuntu
  18.04 and CentOS 7 are legacy/EOL bases.
- Impact: the same source can build a different OpenD version or base than the
  command suggests, especially outside CI or on ARM hosts. Mutable bases and an
  unauthenticated, unhashed archive prevent reproducible review.
- Minimum change: narrow the maintained path to one explicit Linux/amd64
  Ubuntu target; derive the OpenD version from one reviewed source of truth;
  remove or fail on ineffective selectors; pin base images by digest and OpenD
  archives by digest. Retire CentOS from the primary path without removing
  attribution or unrelated history.
- Acceptance: two clean Linux/amd64 builds use identical declared inputs,
  report the same base/archive digests, contain the requested OpenD version,
  and pass an image-structure comparison. If byte-for-byte image identity is
  required, normalize all remaining build metadata and test that separately.

### FH-05 — Several environment variables do not have the advertised semantics

- Priority: **P1**
- Status: **已确认** from interpolation and shell logic;
  **未验证** for OpenD's response to every generated configuration.
- Locations: `docker-compose.yaml:29-39`; `script/start.sh:3-46`;
  `.env.example`; `Dockerfile:49-55,84-90`.
- Evidence:
  - `FUTU_OPEND_RSA_FILE_PATH` is accepted by Dockerfile/Compose but overwritten
    unconditionally to `/.futu/futu.pem` by `start.sh`.
  - Compose `${FUTU_OPEND_TELNET_PORT:-22222}` converts an explicitly empty
    value back to `22222`, so the entrypoint's empty-value disable branch cannot
    be reached through normal Compose configuration.
  - API address/port similarly replace empty values with broad/default values.
  - WebSocket port can be empty and is then omitted, so that optional feature
    can currently be disabled. When enabled, an empty WebSocket IP becomes
    `0.0.0.0` inside the entrypoint.
  - An absent password is silently MD5-hashed as the empty string instead of
    producing a configuration error.
- Impact: operators cannot reason reliably about the effective configuration;
  a value intended to disable or narrow a service may do the opposite.
- Minimum change: define required, optional, empty, and default semantics once;
  validate them before generating XML; preserve documented overrides; use
  separate bind-address variables; reject missing/invalid inputs without
  logging their values.
- Acceptance: table-driven tests generate configuration from fake inputs and
  assert exact XML/argv for unset, empty, valid, and invalid cases, including
  disabled Telnet/WebSocket and a non-default API port.

### FH-06 — Health checks, CI, and E2E claims exceed their evidence

- Priority: **P1**
- Status: **已确认** for test/workflow logic; **推测** for some log-marker
  meanings; **未验证** for current 10.10.7008 runtime behavior.
- Locations: `Dockerfile:75-76,110-111`; `docker-compose.yaml:46-51`;
  `.github/workflows/publish.yml:114-176`; `script/e2e.test.mjs`;
  `script/lib/docker.mjs`; `docs/E2E.md`.
- Evidence:
  - Image health checks only prove a process named `FutuOpenD` exists.
  - Compose health uses hard-coded `127.0.0.1:11111`, ignoring a configured API
    port. Existing docs call this check permanently broken, but current Compose
    generates `0.0.0.0`; whether OpenD actually excludes loopback is runtime
    behavior and remains unverified.
  - Publish CI sets `PROCESS_STARTED` but never gates on it. It accepts exit
    code 0 or an asserted login-failure code 14 without an official/versioned
    source for that code, then prints that the binary and health mechanism work.
    It does not run unit or E2E tests.
  - Compose E2E performs a real login, treats a WebSocket-listener log marker as
    proof of login, checks only an HTTP 101 upgrade rather than an OpenAPI
    request, and is local-only. The source header still claims a
    `GetGlobalState` exercise that is no longer present.
  - E2E uses fixed host ports/container names and cleanup calls
    `docker compose down -v --remove-orphans`, so it is not isolated and can
    delete a same-project named volume.
- Impact: green CI can mean only that an image built and exhibited an accepted
  process/exit shape. The current E2E is unsafe for routine agent execution and
  does not establish protocol correctness or reproducibility.
- Minimum change: define separate liveness, readiness, configuration, and
  protocol checks; make CI gate the signals it reports; remove undocumented
  exit-code assumptions; run credential-free unit/integration tests in CI; give
  E2E a unique project name, temporary volume, random/local ports, fake inputs,
  and deletion limited to resources it created. Keep any operator-only login
  check separate and opt-in.
- Acceptance: tests intentionally break process startup, API binding, custom
  ports, generated config, and archive integrity and observe the corresponding
  gate fail. Test teardown must list and delete only its generated resources.
  Report protocol/login checks as `NOT RUN` unless genuinely executed by the
  authorized operator.

### FH-07 — State, key permissions, and process lifecycle need stronger contracts

- Priority: **P1**
- Status: **已确认** for Compose/Dockerfile/shell structure; **推测** for
  signal and ownership failure modes; **未验证** for OpenD's session-file
  format, migration behavior, and monitor process topology.
- Locations: `Dockerfile:57-78,92-113`; `docker-compose.yaml:13-14,40-54`;
  `script/start.sh:18-50`; `script/lib/docker.mjs:27-34`; repository operations
  documentation.
- Evidence: a named volume is mounted at OpenD's state directory, whose initial
  image path is owned by an unpinned `futu` UID/GID. The RSA bind mount is not
  read-only, while repository guidance requires host mode `0644` to work around
  UID mismatch. The project has no tested ownership/upgrade contract for an
  existing volume. `start.sh` launches OpenD as a child instead of `exec`, so
  the shell remains PID 1 and has no explicit signal-forwarding/reaping logic.
  Compose defines no restart policy. Existing tests do not verify graceful
  termination, restart, state preservation, or key immutability.
- Impact: stop/restart may not reach OpenD as intended; an unexpected exit will
  not automatically recover; key exposure is broader than necessary; ownership
  changes can strand persistent state. Repository descriptions of the state
  directory's contents are not treated as an official session-format contract.
- Minimum change: pin the runtime UID/GID, mount the key read-only with the
  narrowest workable host permissions, validate state-directory ownership
  without reading contents, use `exec` or a minimal explicit supervisor model,
  and choose/document a bounded restart policy. Never auto-migrate or erase an
  existing volume.
- Acceptance: isolated temporary-volume tests send TERM/INT and verify bounded
  graceful exit and exit-code propagation; restart tests use a fake child
  process; ownership is checked by metadata only; a sentinel in a test volume
  survives recreate; the test key cannot be modified from the container.

## Audit-phase checks

| Check | Result | Notes |
| --- | --- | --- |
| Git status and baseline commit | PASSED | Worktree was clean at audit start; commit recorded above. |
| Required source/workflow/test/document review | PASSED | Files listed under Evidence reviewed were inspected without reading secret files. |
| Official v10.10 login/changelog review | PASSED | Documentation mismatch and internal documentation conflict recorded in FH-01. |
| `bash -n script/start.sh script/download_futu_opend.sh` | PASSED | Exit status 0. |
| Unit tests (`npm run test:unit`) | NOT RUN | `npm` is not installed/on `PATH` in this environment. |
| Node syntax checks | NOT RUN | `node` is not installed/on `PATH` in this environment. |
| OpenD binary `-help` on Linux/amd64 | NOT RUN | Audit host is Darwin/arm64 and Docker daemon access was unavailable; no target-runtime claim made. |
| Docker build / image inspection | NOT RUN | No accessible isolated Linux/amd64 Docker environment. |
| Compose E2E / real login / 2FA | NOT RUN | Prohibited by the hardening constraints; existing harness is destructive to its project volume. |
| Kubernetes tests | NOT RUN | Kubernetes is a non-target for this pass. |

## Phase checklist and progress

- [x] Phase 0 — baseline and evidence audit: document findings, constraints,
  minimal changes, and acceptance methods.
- [ ] Phase 1 — login mechanism: reconcile 10.10 startup with official docs and
  isolated Linux/amd64 help output; implement first-run versus remembered-state
  behavior without agent-run login.
- [ ] Phase 2 — security configuration: loopback defaults, independent Telnet
  binding/disable semantics, WebSocket safeguards, key mount and permissions.
- [ ] Phase 3 — reproducible build: one Linux/amd64 target, aligned version
  source, pinned base/archive digests, strict download handling.
- [ ] Phase 4 — test and CI isolation: fake-input config tests, local download
  fixtures, lifecycle/state tests with unique temporary resources, and honest
  CI gates.
- [ ] Phase 5 — documentation reconciliation and final acceptance matrix:
  remove stale claims, preserve upstream attribution, and report every target
  check as PASSED, FAILED, SKIPPED, or NOT RUN.

The phases deliberately keep login, security configuration, build hardening,
and test/CI work separate. Phase 1 is next; this audit phase does not start it.
