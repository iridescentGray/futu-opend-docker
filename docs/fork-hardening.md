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
- [Ubuntu 18.04 lifecycle status](https://ubuntu.com/18-04)
- [Ubuntu release lifecycle](https://ubuntu.com/about/release-cycle)
- [Ubuntu 18.04 amd64 image manifest](https://hub.docker.com/layers/library/ubuntu/18.04/images/sha256-dca176c9663a7ba4c1f0e710986f5a25e672842963d95b960191e2d9f7185ebe)
- [Ubuntu 22.04 amd64 image manifest](https://hub.docker.com/layers/library/ubuntu/22.04/images/sha256-281c5745f657873d78e5531fc5ba8575f46ab7769b94550ac99543f122679986)
- [Futu Python SDK installation](https://openapi.futunn.com/futu-api-doc/en/quick/demo.html)
- [Futu SDK encryption configuration](https://openapi.futunn.com/futu-api-doc/en/ftapi/init.html)
- [Futu `get_global_state()`](https://openapi.futunn.com/futu-api-doc/en/quote/get-global-state.html)
- [`actions/checkout` v4.2.2 release](https://github.com/actions/checkout/releases/tag/v4.2.2)
- [`actions/setup-node` v4.4.0 release](https://github.com/actions/setup-node/releases/tag/v4.4.0)

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
- Phase 1 resolution: **已实现（包装层）**. XML credentials were removed and
  the two documented flows are explicit. Real 10.10.7008 binary and session
  behavior remain **未验证**; see the Phase 1 checks below.

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
- Phase 2 resolution: **已实现（静态模型与包装层）**. Bridge is the standalone
  default with API published only on host loopback and outbound networking
  retained. Host mode is a separate complete file with no ports and loopback
  bind. Telnet/WebSocket default to absent XML. Actual packet flow and real
  authentication remain **未验证**.

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
- Phase 3 resolution: **已实现（下载器与失败关闭）**. The downloader now
  requires HTTPS for the initial request and redirects, fails on HTTP errors,
  bounds connect/total/retry time, validates exact version/name/digest/archive
  paths, and atomically replaces only after successful verification. Offline
  fake-curl/local-tar tests cover HTTP exit 22, timeout exit 28, malformed input,
  checksum mismatch, wrong archive root, and cleanup. No publisher checksum or
  signature was found and the official archive could not be resolved from this
  sandbox, so `stableArtifact.sha256` remains `null` and builds fail closed.
  `--report-tofu` prints a candidate from a validated temporary official-HTTPS
  download but explicitly does not claim publisher-authenticated provenance.

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
- Phase 1 progress: Dockerfile defaults were aligned to `10.10.7008` only as a
  prerequisite for the version-gated wrapper. Digest pinning, target narrowing,
  and reproducibility remain open for Phase 3.
- Phase 3 resolution: **已实现（声明与静态构建路径）**. The only final stage
  is `runtime`; it has no version fallback or `BASE_IMG` selector, and Compose
  plus CI select `linux/amd64` and target `runtime`. Ubuntu 22.04 build and
  Ubuntu 18.04 runtime amd64 manifests are digest-pinned. CentOS 7 and floating
  stable tags were removed from the maintained publish path. OpenD runs as
  explicit UID/GID `10001:10001`, application files are root-owned under
  `/opt/futu-opend`, and the existing state-volume name/path remain unchanged.
  Ubuntu 18.04 is knowingly retained as an out-of-standard-support binary
  compatibility baseline; binary dependencies and a newer-runtime migration
  remain **未验证**, as do actual image reproducibility and startup.

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
- Phase 1 progress: required/optional input validation, path overrides, empty
  Telnet/WebSocket handling, and value-free legacy-password rejection are
  covered by fake-OpenD tests. Listener hardening remains Phase 2.
- Phase 2 progress: Telnet now has an independent bind address; unset and empty
  optional ports both disable XML elements. Rendered Compose tests cover both
  cases and custom API-port propagation.

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
- Phase 1 progress: CI now runs the fake-OpenD wrapper suite and is configured
  to inspect actual image `-help` output instead of accepting an undocumented
  login exit code. The old real-login E2E is an explicit skip. The CI image
  check was not run locally and full isolated E2E design remains Phase 4.
- Phase 2 progress: Compose health is now process-only liveness and documentation
  explicitly separates it from SDK readiness. Bounded restart, shutdown grace,
  and log rotation are configured; daemon/runtime behavior remains unverified.
- Phase 3 progress: publish CI now runs unit/offline tests, rejects an absent or
  malformed artifact lock, builds only `linux/amd64`/`runtime`, checks image
  architecture, UID/GID, version label and actual help parameters, and exercises
  the wrapper with a fake executable. It publishes only an explicit version tag.
  None of those image gates ran locally in this phase.
- Phase 4 resolution: **已实现（分层测试与 CI 条件）**. Layer 1 always runs
  without credentials; Layer 2 builds and inspects the image with unique test
  resources and controlled fake OpenD startup; Layer 3 defaults to an explicit
  skip and performs only encrypted `get_global_state()` when the user enables
  it. PR CI is read-only and cannot publish. Its aggregate gate accepts a Layer
  2 skip only for an explicitly classified docs-only change. Trusted main/manual
  publishing reruns Layers 1 and 2 before registry authentication. Version
  automation now creates a review-only PR and never auto-merges or deploys.
  Layer 2 and real Layer 3 remain **未验证** locally; see Phase 4 checks.

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
- Phase 1 progress: `exec`, SIGTERM/exit propagation tests, restrictive runtime
  XML, a read-only Compose key mount, stable HOME/user/volume configuration,
  and wrapper locking are implemented. Actual OpenD monitor topology, pinned
  UID/GID, and target-volume lifecycle tests remain unverified/open.
- Phase 2 progress: the host key stays mode `0600` and read-only; a networkless,
  non-restarting key initializer creates a mode-`0400` copy owned by the actual
  image `futu` UID/GID in a separate key volume. The main service mounts it
  read-only. The existing state volume is unchanged and no migration ran.

## Audit-phase checks

| Check                                                   | Result  | Notes                                                                                              |
| ------------------------------------------------------- | ------- | -------------------------------------------------------------------------------------------------- |
| Git status and baseline commit                          | PASSED  | Worktree was clean at audit start; commit recorded above.                                          |
| Required source/workflow/test/document review           | PASSED  | Files listed under Evidence reviewed were inspected without reading secret files.                  |
| Official v10.10 login/changelog review                  | PASSED  | Documentation mismatch and internal documentation conflict recorded in FH-01.                      |
| `bash -n script/start.sh script/download_futu_opend.sh` | PASSED  | Exit status 0.                                                                                     |
| Unit tests (`npm run test:unit`)                        | NOT RUN | `npm` is not installed/on `PATH` in this environment.                                              |
| Node syntax checks                                      | NOT RUN | `node` is not installed/on `PATH` in this environment.                                             |
| OpenD binary `-help` on Linux/amd64                     | NOT RUN | Audit host is Darwin/arm64 and Docker daemon access was unavailable; no target-runtime claim made. |
| Docker build / image inspection                         | NOT RUN | No accessible isolated Linux/amd64 Docker environment.                                             |
| Compose E2E / real login / 2FA                          | NOT RUN | Prohibited by the hardening constraints; existing harness is destructive to its project volume.    |
| Kubernetes tests                                        | NOT RUN | Kubernetes is a non-target for this pass.                                                          |

## Phase checklist and progress

- [x] Phase 0 — baseline and evidence audit: document findings, constraints,
      minimal changes, and acceptance methods.
- [x] Phase 1 — login mechanism implementation: separate first-run interactive
      and remembered-state startup, remove XML credentials, harden the wrapper, and
      add fake-OpenD tests. Linux/amd64 binary and real-login acceptance remain
      explicitly unverified below.
- [x] Phase 2 — Compose/runtime security implementation: standalone bridge and
      host files, listener disable semantics, key preparation, bounded lifecycle,
      and rendered-model tests. Target packet flow and authentication remain
      explicitly unverified below.
- [x] Phase 3 — reproducible-build inputs: one Linux/amd64 target, aligned
      version source, pinned base manifests, strict download handling, and a
      fail-closed archive lock. The archive digest and target-runtime behavior
      remain deliberately unverified until operator review/acceptance.
- [x] Phase 4 — layered tests and CI isolation: deterministic unit/config tests,
      unique no-credential container resources, strict aggregate gates, and an
      explicit user-only encrypted read-only protocol check.
- [x] Phase 5 — documentation reconciliation and final acceptance matrix:
      remove stale claims, preserve upstream attribution, and report every target
      check as PASSED, FAILED, SKIPPED, or NOT RUN.
- [x] Phase 6 — concise Chinese README with detailed deployment material routed
      to `docs/`.
- [x] Phases 7–9 — iteration history for the local artifact lock, unified
      foreground initialization and scoped Expect proxy; superseded designs remain
      labeled as such below.
- [x] Phase 10 — optional wrapper-only environment password, single submission,
      no automatic retry, fake-secret redaction tests and synchronized docs.
- [x] Phase 11 — source-free release bundle, digest-pinned image-only Compose,
      operator launcher, checksum, and immutable tag-triggered release workflow.
- [x] Phase 12 — first-release artifact lock, user-facing README, and explicit
      `v10.10.7008-r1` release notes and tag policy.
- [x] Phase 13 — macOS Apple Silicon host bundle, platform/engine preflight,
      LibreSSL key-generation compatibility, dual-host release assets, and
      native-host plus emulated Linux/amd64 smoke verification.
- [x] Phase 14 — cross-platform release-test correction after the immutable r2
      tag failed safely, with portable checksum/mode checks and Ubuntu/amd64
      reproduction before preparing r3.

The phases deliberately keep login, security configuration, build hardening,
and test/CI work separate. Target-platform real login, SDK readiness, image
smoke, state compatibility and long-running behavior remain operator acceptance
items rather than completed implementation checks.

## Phase 1 — login adaptation

Phase baseline commit: `74170f34e570fcdcac9349e0ecfb8e4b5fb963af`.

### Changes

- Added wrapper-only `FUTU_LOGIN_MODE=interactive|remember` and limited the
  wrapper to OpenD `10.10.7008`.
- `interactive` requires attached stdin/stdout TTYs and passes no invented
  login parameters. `remember` requires `FUTU_ACCOUNT_ID` and passes official
  `-login_account`, optional `-area_code`, and `-login_by_remember=1` arguments
  using a shell array.
- Removed account/password elements from `FutuOpenD.xml`. Non-empty legacy
  password variables now stop with a value-free migration message.
- Replaced `sed` rendering with explicit placeholders and XML escaping; added
  strict shell mode, input validation, `umask 077`, runtime XML mode `0600`,
  documented path overrides, and `exec` for PID 1/stdin/signal/exit behavior.
- Initialization and routine startup retain the `futu-opend-data` volume,
  `futu` user, and `/home/futu` HOME. A non-blocking `flock` on the shared state
  directory rejects simultaneous wrapper-launched OpenD processes. The lock is
  not treated as a login-success marker and state contents are never read.
- Routine Compose startup no longer allocates stdin or a TTY. The one-off
  initialization uses `--interactive` from a local terminal, where Compose
  auto-allocates a TTY, so an accidental background `interactive` start fails
  instead of waiting on an unseen prompt.
- Added `script/start.test.sh` with a controlled fake OpenD and only temporary
  fake resources. Disabled the obsolete destructive real-login Compose E2E as
  an explicit skipped test.
- Updated Compose, README, `.env.example`, CI parameter-help validation,
  agent guidance, and E2E status documentation. The named volume was not
  renamed, cleared, inspected, or migrated.
- Aligned Dockerfile defaults to `10.10.7008` because the version-gated wrapper
  would otherwise make an unqualified build unusable. Full reproducible-build
  work remains Phase 3.

### Checks

| Check                                                       | Result  | Notes                                                                                                                             |
| ----------------------------------------------------------- | ------- | --------------------------------------------------------------------------------------------------------------------------------- |
| Official 10.10 command-line and 10.10.7008 changelog review | PASSED  | Supports interactive startup, remembered-login arguments, phone `area_code`, and removal of XML account/password fields.          |
| `bash -n script/start.sh script/start.test.sh`              | PASSED  | Strict-mode scripts parse successfully.                                                                                           |
| `bash script/start.test.sh`                                 | PASSED  | 16 fake-OpenD checks passed; no Docker, network, credentials, or real login.                                                      |
| Template XML parse with Python standard library             | PASSED  | `FutuOpenD.xml` is well-formed before wrapper substitution.                                                                       |
| `package.json` parse with Python standard library           | PASSED  | JSON is valid.                                                                                                                    |
| Compose and publish-workflow YAML parse with Ruby Psych     | PASSED  | Syntax trees parsed without accessing `.env` or rendering Compose values.                                                         |
| `docker compose run --help` outside the project directory   | PASSED  | Confirmed `--interactive` and automatic TTY behavior without loading project configuration or contacting the daemon.              |
| `git diff --check`                                          | PASSED  | No whitespace errors at the checkpoint.                                                                                           |
| ShellCheck, shfmt, and pre-commit hooks                     | NOT RUN | These tools are not installed/on `PATH` in the current environment.                                                               |
| Node unit tests and skipped E2E reporting                   | NOT RUN | Node/npm are unavailable in the current environment.                                                                              |
| Docker Compose model/build                                  | NOT RUN | Docker daemon is unavailable inside the sandbox; no deployment was attempted.                                                     |
| Linux/amd64 `FutuOpenD -help` parameter gate                | NOT RUN | Added to publish CI, but not executed locally. CI must confirm `login_account`, `login_by_remember`, `area_code`, and `cfg_file`. |
| OpenD monitor/daemon process topology                       | NOT RUN | No `no_monitor` assumption was added; must be observed on the target binary before changing argv.                                 |
| First interactive real login and remember selection         | NOT RUN | User-only private-terminal step; agents must not execute it.                                                                      |
| Routine startup from valid persisted state                  | NOT RUN | Requires the preceding user-only initialization and actual Futu session result.                                                   |
| Missing/expired remembered-state reauthentication           | NOT RUN | README provides the non-destructive manual flow; actual behavior remains user-verified.                                           |

### Remaining manual acceptance

On the intended private Linux/amd64 host, the user must confirm that the exact
10.10.7008 binary help matches the documented arguments, that interactive mode
accepts and preserves its TTY, that choosing OpenD's remember-password option
allows a later `remember` start from the same volume, and that expired state
returns a clear OpenD failure followed by successful manual reauthentication.
These checks must not inspect session-file contents and must remain `NOT RUN`
until the user actually performs and reports them. No permanent exemption from
password or verification prompts is promised.

## Phase 2 — Compose and runtime hardening

Phase baseline: HEAD `74170f34e570fcdcac9349e0ecfb8e4b5fb963af`
plus the existing uncommitted Phase 1 changes. Those changes were preserved.

### Changes

- Replaced host networking as the default. `docker-compose.yaml` is a complete
  bridge model with `internal: false`; API binds the container interface and is
  published only to host `127.0.0.1`. Same-network containers remain able to
  reach the API and are documented as trusted clients.
- Added complete standalone `docker-compose.host.yaml`. It uses host networking,
  has no `ports`, and defaults API to host loopback. Documentation forbids
  layering the bridge and host files and shows full `--env-file` / `-f` commands.
- Telnet now has independent `FUTU_OPEND_TELNET_IP`. Telnet and WebSocket ports
  default to empty; both unset and empty cause their XML elements to be omitted.
  Non-loopback API binds require a readable RSA key, and non-loopback WebSocket
  is rejected until its required TLS configuration exists.
- Added `futu-key-init`, `script/init-key.sh`, and offline tests. The one-shot
  helper has no network and no restart, reads a mode-`0600` host key through a
  read-only bind, checks regular-file/readability/PKCS#1 and unencrypted markers,
  verifies the copy matches without logging a checksum, and writes a
  mode-`0400` copy owned by the image's actual `futu` UID/GID. Main OpenD remains
  non-root and mounts the key volume read-only.
- Kept `futu-opend-data` unchanged. No state contents were inspected and no
  ownership migration, deletion, rename, or automatic account switch occurred.
- Added 30-second stop grace, `on-failure:3` bounded restart, process-only
  liveness, and three 10 MiB `json-file` logs. Documentation records that
  health is not readiness and an unhealthy state alone does not trigger Docker
  restart.
- Added official encrypted SDK connection examples for host loopback and the
  trusted Compose network. They configure the same private key and enable
  protocol encryption before opening the context. Examples were not executed.
- Did not add `read_only` root filesystems, privileged mode, broad capability
  changes, firewall changes, or Docker daemon changes without runtime evidence.

### Checks

| Check                                                              | Result  | Notes                                                                                                                |
| ------------------------------------------------------------------ | ------- | -------------------------------------------------------------------------------------------------------------------- |
| `bash -n` for startup, key-init, and Compose test scripts          | PASSED  | All five shell files parsed.                                                                                         |
| `bash script/start.test.sh`                                        | PASSED  | 19 fake-OpenD checks, including independent Telnet, unset/empty listeners, API-key requirement, and WebSocket guard. |
| `bash script/init-key.test.sh`                                     | PASSED  | 8 fake-key checks for metadata, encrypted/wrong formats, and requested failure paths.                                |
| `bash script/compose.test.sh`                                      | PASSED  | 6 assertions after four real `docker compose config --format json` renders using explicit fake env files.            |
| Default bridge effective model                                     | PASSED  | No host mode; only API published on `127.0.0.1`; network not internal; optional listeners empty.                     |
| Standalone host effective model                                    | PASSED  | Host network present, no ports, API bind `127.0.0.1`; optional listeners empty.                                      |
| Custom API port model                                              | PASSED  | `12345` reached container environment, target port, and loopback publication.                                        |
| State/key volume names across files                                | PASSED  | Same explicit test project resolved identical names in both standalone files.                                        |
| Docker daemon, image build, or container execution                 | NOT RUN | Compose rendering used the client only; sandbox daemon access remains unavailable.                                   |
| Actual key initializer inside the Linux/amd64 image                | NOT RUN | Offline test used fake material/current test UID/GID; image tools and mounts need target verification.               |
| Bridge outbound/authentication and SDK connection                  | NOT RUN | Requires user-controlled Linux/amd64 runtime and real login; no network behavior is claimed.                         |
| Host-network authentication and SDK connection                     | NOT RUN | Compatibility flow is documented but not executed.                                                                   |
| Same-network container SDK connection                              | NOT RUN | Example is documentation only; the trust boundary is explicit.                                                       |
| Shutdown grace, bounded restart, and Docker daemon reboot behavior | NOT RUN | Effective configuration is verified; real OpenD lifecycle behavior is not.                                           |
| Existing state-volume ownership/migration                          | NOT RUN | Only a metadata-check command is documented; no production volume was accessed.                                      |

### Remaining target acceptance

On the private Linux/amd64 host, the user must build the image, verify the key
initializer's actual `futu` ownership and OpenD key acceptance, exercise API
connectivity from host loopback and one explicitly trusted same-network test
container, and observe outbound login behavior separately in bridge and (only
if needed) host mode. Authentication, verification codes, and SDK checks remain
user-only. A bridge failure must be recorded rather than silently changing the
default or claiming host networking is universally required.

## Phase 3 — download, build, and version hardening

Phase baseline: HEAD `74170f34e570fcdcac9349e0ecfb8e4b5fb963af`
plus the existing uncommitted Phase 1 and Phase 2 changes. They were preserved.

### Changes

- Replaced the permissive downloader with a strict HTTPS-only wrapper. It uses
  verified TLS, HTTPS-only redirects, HTTP failure handling, connect/overall
  timeouts, two retries (three attempts maximum), and a finite retry-time cap.
  Downloads stay in a restrictive same-directory temporary file; SHA-256 and
  versioned archive paths are checked before an atomic rename. Failure removes
  the temporary file and leaves any prior accepted target unchanged.
- Added a separate `--report-tofu` path for the publisher-checksum gap. It
  validates a temporary download and reports a candidate digest without
  installing the artifact, while stating that the result is not publisher
  authenticity proof. Normal download/build paths still require a previously
  recorded digest.
- Extended `opend_version.json` to identify the version source, exact stable
  artifact URL/name/platform, integrity state, and pinned amd64 base manifests.
  The actual OpenD SHA-256 is `null`; it was not fabricated. Version discovery
  preserves a lock only for the exact unchanged artifact and deliberately
  invalidates it on a version bump. The documentation synchronizer also keeps
  `.env.example`'s digest input aligned without inventing a value.
- Reduced Dockerfile and publish CI to one Ubuntu-based `linux/amd64` runtime
  target. Removed `BASE_IMG`, CentOS 7 stages/matrix, hidden version defaults,
  and floating `stable` publication. Both base images are pinned by amd64
  manifest digest; Compose explicitly selects `platform: linux/amd64` and
  `target: runtime` and refuses an unset artifact lock.
- Pinned the application account to UID/GID `10001:10001`. OpenD lives under
  root-owned `/opt/futu-opend`, wrappers under `/usr/local/bin`, and the template
  under `/etc/futu-opend`; `/bin` is not recursively reassigned. The named state
  volume and mount path are unchanged, and no existing volume was inspected or
  migrated.
- Replaced the implicit `procps`/`pgrep` runtime dependency with a `/proc/1/comm`
  PID-1 liveness check. This still proves only process shape, not readiness.
- Retained pinned Ubuntu 18.04 only as the reproducible compatibility baseline
  for Futu's Ubuntu 18.04 package. Official lifecycle material confirms it is
  outside standard support. Migration to a supported runtime was not attempted
  without the actual binary, dependency inspection, help output, and
  no-credential startup evidence.
- Updated README, `.env.example`, agent notes, E2E coverage notes, Compose tests,
  version scripts/tests, and publish workflow. Deployment guidance distinguishes
  OpenD version/artifact hash, base manifests, source commit, and the final
  registry image digest, and uses only explicit version tags before digest pinning.

### Checks

| Check                                                                      | Result  | Notes                                                                                                                                                                                                |
| -------------------------------------------------------------------------- | ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Shell syntax for startup, key, download, build-config, and Compose scripts | PASSED  | All eight shell files parsed with the available Bash.                                                                                                                                                |
| `bash script/start.test.sh`                                                | PASSED  | 19 fake-OpenD wrapper assertions; no binary, credentials, network, or login.                                                                                                                         |
| `bash script/init-key.test.sh`                                             | PASSED  | 8 fake-key assertions; only temporary test material.                                                                                                                                                 |
| `bash script/download_futu_opend.test.sh`                                  | PASSED  | 12 local-fixture/fake-curl assertions, including HTTP 22, timeout 28, digest mismatch, illegal inputs, invalid/root-invalid archives, TOFU isolation, atomic preservation, and cleanup.              |
| `bash script/build_config.test.sh`                                         | PASSED  | 4 static assertions align artifact metadata, both base manifests, single target/no fallback, UID/layout, architecture, and version-only CI tag policy.                                               |
| `bash script/compose.test.sh`                                              | PASSED  | 7 effective-model assertions; missing digest fails closed, both files select `runtime`/amd64, and prior network/key checks remain green.                                                             |
| `script/update_docs_version.test.js`                                       | PASSED  | 19 assertions passed with bundled Node; includes digest sync/read validation.                                                                                                                        |
| `script/check_version.test.js`                                             | NOT RUN | Test process could not load the declared `jsdom` dependency because project dependencies are not installed in this environment. Source syntax passed; no network install was performed.              |
| JavaScript syntax checks                                                   | PASSED  | Both version scripts and both unit-test files parse with bundled Node.                                                                                                                               |
| Official OpenD archive download / SHA-256 lock                             | NOT RUN | DNS resolution failed inside the sandbox; no sandbox bypass was used. No publisher checksum/signature was found, so the lock remains explicitly `null`.                                              |
| Docker build / no-credential smoke / image inspection                      | NOT RUN | Docker daemon is unavailable and the artifact is intentionally unlocked. CI now gates exact version, SHA, amd64 architecture, UID/GID, label, help parameters, and fake wrapper startup once locked. |
| Ubuntu 18.04 binary dependency/startup compatibility                       | NOT RUN | Requires the exact locked official binary in Linux/amd64; build success alone will not satisfy this check.                                                                                           |
| Ubuntu 22.04-or-newer runtime migration                                    | NOT RUN | Requires `ldd`/loader/library review plus help and no-credential runtime behavior before changing the compatibility baseline.                                                                        |
| Byte-for-byte repeat build and final registry digest                       | NOT RUN | Requires two clean Linux/amd64 builds and, for a registry digest, an explicitly authorized publish/pull workflow.                                                                                    |
| Real login, remembered-state, SDK/API, and network acceptance              | NOT RUN | User-only private-terminal acceptance; unchanged from prior phases.                                                                                                                                  |

### Remaining target acceptance

An operator must first perform the documented TOFU review against the fixed
official HTTPS origin and commit the accepted artifact SHA-256. On a private
Linux/amd64 builder, build twice from the same source commit and inputs, inspect
architecture `amd64`, user `10001:10001`, OpenD version label, binary help and
dependencies, and run the no-credential wrapper smoke gate. Only after that may
the user perform the separate real-login/network acceptance. If a version bump
occurs, automation intentionally clears the prior artifact lock; a new review is
required. A final image digest exists only after producing/publishing the exact
accepted image and must never be guessed from the OpenD or base-image digest.

## Phase 4 — layered tests and trustworthy CI gates

Phase baseline: HEAD `74170f34e570fcdcac9349e0ecfb8e4b5fb963af`
plus the existing uncommitted Phase 1–3 changes. All were preserved.

### Changes

- Defined three separate commands and evidence boundaries in `docs/E2E.md`:
  `test:layer1` for unit/config, `test:smoke` for an isolated no-credential
  image/container check, and `test:live` for user-enabled encrypted read-only
  acceptance. The legacy E2E skip remains visibly distinct.
- Extended Layer 1 regression coverage for fake password/MD5/private-key
  output leakage, configuration-aware health checks, custom API port alignment,
  live-check encryption/timeout/cleanup behavior through a fake SDK, and CI
  permission/gate policy. Layer 1 never loads `.env`, contacts Futu, or invokes
  the Docker daemon.
- Added `container_smoke.test.sh`. It reads only the public version lock, creates
  unique image/container/volume names, bounds build/run/stop waits, uses
  `--network none` for binary/help and runtime checks, verifies architecture,
  UID/GID, version label and required files, and drives startup/TERM with a
  mounted fake OpenD. Cleanup removes only resources whose successful creation
  was recorded by that invocation. No Compose project or existing volume is used.
- Added `live_readonly.py`. With no opt-in it prints `SKIPPED` before importing
  the SDK. With `RUN_LIVE_TESTS=1`, it validates prerequisites, enables SDK
  encryption and sets the matching key before creating `OpenQuoteContext`,
  applies separate connection/request timeouts, calls only
  `get_global_state()`, requires `qot_logined=true`, optionally requires
  `trd_logined=true`, suppresses SDK exception details, and closes the context
  in `finally`. It ignores market-state values, so market closure is not failure.
- Split PR CI from publishing. `ci.yml` has only `contents: read`, persists no
  checkout credential, exposes no publish secret, always runs Layer 1, and runs
  Layer 2 for every non-docs-only PR. Its `always()` gate explicitly rejects
  upstream failure/cancellation/missing classification and accepts `skipped`
  only for the enumerated documentation paths.
- `publish.yml` has no PR trigger. Pushes to trusted `main` and explicit manual
  dispatch rerun Layer 1 and Layer 2 against the same explicit image tag;
  registry authentication and push occur only afterward. Public CI never runs
  Layer 3 and no workflow uploads environment, key, state, or log artifacts.
- Reworked version automation to use the repository `GITHUB_TOKEN`, minimum
  write permissions needed to push a proposal branch and open a PR, and no PAT,
  auto-merge, publish, deploy, or existing-PR deletion. Repository settings may
  still prevent PR creation or suppress follow-on events; those limitations are
  documented rather than bypassed.
- Pinned every external Action reference to a release-verified full commit:
  `actions/checkout` v4.2.2 at
  `11bd71901bbe5b1630ceea73d27597364c9af683` and `actions/setup-node` v4.4.0
  at `49933ea5288caeca8642d1e84afbd3f7d6820020`.

### Checks

| Check                                                    | Result              | Notes                                                                                                                                                                                                                                                        |
| -------------------------------------------------------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `bash script/layer1.test.sh`                             | PASSED              | 73 shell/config assertions: startup 19, key 8, download 12, build model 4, Compose 7, fake live SDK 10, CI policy 6, gate outcomes 7. No Docker daemon, networked OpenD, credentials, or real key.                                                           |
| Signal-test stabilization                                | FAILED, then PASSED | One full Layer 1 run exceeded the old one-second fake-process readiness window. The test now waits up to five seconds for an explicit post-trap marker; standalone startup and the following full Layer 1 rerun both passed. No production code was relaxed. |
| Legacy-value and key-content redaction                   | PASSED              | Fake password, fake MD5 and fake private-key canaries were absent from captured stdout/stderr.                                                                                                                                                               |
| Custom API-port consistency                              | PASSED              | Rendered Compose aligned runtime port, host-loopback target/publication and health command; fake SDK received client port `12345`.                                                                                                                           |
| Layer 3 default command                                  | SKIPPED             | `RUN_LIVE_TESTS` was not enabled; the script reports the explicit skip before SDK import.                                                                                                                                                                    |
| Layer 3 fake-SDK unit test                               | PASSED              | 10 checks cover quote-only success, optional trade condition, encryption, custom port, key permissions, redaction, missing prerequisites, both timeouts, `close()`, and close failure. This is not a real login result.                                      |
| `script/container_smoke.test.sh`                         | FAILED (preflight)  | Docker daemon was unavailable. No image, container, or volume was created; actual build/help/stop assertions were therefore NOT RUN.                                                                                                                         |
| Node version-unit suite                                  | NOT RUN             | The workspace still lacks installed `jsdom`; CI installs locked dependencies with `npm ci` before `test:layer1`. JavaScript source syntax is checked separately.                                                                                             |
| Workflow policy regression                               | PASSED              | 6 static checks cover full Action SHAs, PR read-only/no-publish policy, exact skip gate, publish ordering, review-only updater, and no sensitive artifacts.                                                                                                  |
| `bash script/ci_gate.test.sh`                            | PASSED              | 7 outcome combinations prove required success, the exact docs-only skip, and rejection of upstream failure, failure, cancellation, unexpected success, and missing classification.                                                                           |
| GitHub-hosted PR and publish workflows                   | NOT RUN             | Workflow files were validated locally only; no remote run, token use, push, package publication, or repository setting change occurred.                                                                                                                      |
| Real encrypted `get_global_state()`                      | NOT RUN             | Deliberately user-only. No password, OTP, login cache, private key, or account connection was accessed.                                                                                                                                                      |
| `qot_logined` / optional `trd_logined` on a real account | NOT RUN             | Fake SDK results do not count. The user must run Layer 3 and report the actual result.                                                                                                                                                                       |

### Remaining acceptance

After the artifact SHA-256 is reviewed and locked, a Linux/amd64 CI or private
builder must run Layer 2 and report its image build/help/controlled-stop result.
Separately, the user may initialize/login in a private terminal and explicitly
run Layer 3 with the same RSA key. Only that real SDK result can establish quote
login and, if requested, trade-server login. Neither result establishes trading
unlock, order capability, paid entitlements, or permanent authentication.

## Phase 5 — unified user initialization command

Status: **superseded by Phase 8**. This section records the earlier explicit
`START` transition design for audit history.

The user-facing first-login workflow is now one command:
`bash script/initialize-and-start.sh`. It validates Compose before mutation,
generates a missing default RSA key with restrictive permissions without
overwriting existing material, stops the normal service without deleting
volumes, runs the official interactive login, and starts the background
remembered-login service only after the interactive process exits successfully
and the user types `START`.

This is a user-interface consolidation, not an automatic-login mechanism. The
interactive and background containers remain sequential, use the same user,
HOME, key volume and state volume, and never run concurrently. No exit code,
directory or project marker is treated as proof of login. `.dockerignore` now
excludes `.env*`, PEM/key files and an accidentally copied OpenD state directory
from the build context.

Checks performed for this phase:

| Check                                                                        | Result  | Notes                                                                                                                                                                                                                                                     |
| ---------------------------------------------------------------------------- | ------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `bash -n script/initialize-and-start.sh script/initialize-and-start.test.sh` | PASSED  | Both scripts parse successfully.                                                                                                                                                                                                                          |
| `bash script/initialize-and-start.test.sh`                                   | PASSED  | 3 fake-Docker/fake-OpenSSL tests cover key generation and mode, operation ordering, explicit confirmation, interactive failure, and refusal to start the background service. No Docker daemon, OpenD, credentials, network, volume, or real key was used. |
| `bash script/layer1.test.sh`                                                 | PASSED  | 77 offline assertions passed after adding the unified workflow and build-context regression coverage. The Compose checks only rendered configuration; no container was started.                                                                           |
| `shellcheck`                                                                 | NOT RUN | `shellcheck` is not installed in the current environment. Bash syntax and behavioral tests passed instead.                                                                                                                                                |
| Real interactive login and transition to remembered startup                  | NOT RUN | User-only private-terminal acceptance remains required.                                                                                                                                                                                                   |

## Phase 6 — concise Chinese project entry point

`README.md` is now a concise Chinese project introduction and startup guide.
The detailed build-lock, login, RSA-key, network, lifecycle, SDK, state-volume
and test material was retained in `docs/deployment.md`; `docs/E2E.md` remains
the source for test-layer details. Commands and safety boundaries were not
removed or changed as part of this documentation split.

| Check                                          | Result  | Notes                                                                                                                  |
| ---------------------------------------------- | ------- | ---------------------------------------------------------------------------------------------------------------------- |
| README/document structure and code-fence check | PASSED  | Local checks confirm balanced Markdown code fences, required quick-start commands and links to all detailed documents. |
| Runtime code and Compose behavior              | NOT RUN | This phase changes documentation routing only.                                                                         |

## Phase 7 — confirmed automatic local artifact lock

Status: **superseded by Phase 8**. This section records the earlier explicit
`LOCK 10.10.7008` confirmation design for audit history.

`initialize-and-start.sh` now invokes `lock-artifact.sh` before Compose
interpolation. A valid existing `FUTU_OPEND_SHA256` is reused without network
access. If it is missing or invalid, the helper downloads only a temporary copy
from the fixed official HTTPS origin through the existing hardened downloader,
validates the archive, displays the candidate digest and requires the exact
user confirmation `LOCK 10.10.7008` before atomically replacing the local
`.env` with mode `0600`. It removes duplicate digest entries and preserves all
other lines without printing them.

This remains TOFU consistency locking, not publisher authentication. A rejected
confirmation, failed download or invalid archive leaves `.env` unchanged. The
same reviewed digest must still be committed to `opend_version.json` before
Layer 2 or publishing can pass. The unified launcher deliberately removes a
same-named shell override when invoking Compose so an exported empty variable
cannot hide the value just written to the explicit env file.

| Check                                              | Result  | Notes                                                                                                                             |
| -------------------------------------------------- | ------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `bash -n` for lock and unified-start scripts/tests | PASSED  | All four Bash files parse successfully.                                                                                           |
| `bash script/lock-artifact.test.sh`                | PASSED  | 3 fake-curl/local-archive checks cover confirmed atomic write and mode, rejection without changes, and reuse without downloading. |
| `bash script/layer1.test.sh`                       | PASSED  | 80 offline assertions passed. No real network, Docker container, credential, key or `.env` was used.                              |
| Real official artifact TOFU review                 | NOT RUN | The user must review and confirm the candidate in a private terminal.                                                             |
| Real image build and login                         | NOT RUN | Still require separate target-platform and user-only acceptance.                                                                  |

## Phase 8 — official prompts only during first foreground session

At the user's request, project-specific `LOCK` and `START` prompts were removed.
When the local SHA is missing, `lock-artifact.sh` now automatically records the
candidate produced by the existing fixed-origin HTTPS downloader after archive
validation. Running initialization is the explicit action that accepts this
TOFU behavior. The output continues to state that the digest is neither a
publisher signature nor independent authenticity proof. Download or validation
failure leaves `.env` unchanged, and a valid existing lock is reused.

`initialize-and-start.sh` now starts one interactive container with
`--service-ports` and keeps it in the foreground. After the user completes the
official OpenD prompts, that same process immediately serves the API. It does
not infer login success, start a second container, or require an OpenD `exit`
followed by project confirmation. This first session has no long-running
background restart policy; after it ends, later starts use the documented
remembered-state `docker compose up -d` flow.

| Check                                             | Result  | Notes                                                                                                                           |
| ------------------------------------------------- | ------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Bash syntax for lock/initialize scripts and tests | PASSED  | All four files parse successfully.                                                                                              |
| `bash script/lock-artifact.test.sh`               | PASSED  | 3 local-fixture/fake-curl checks cover automatic atomic mode-0600 write, failure without mutation, and existing-lock reuse.     |
| `bash script/initialize-and-start.test.sh`        | PASSED  | 3 fake-Docker/fake-OpenSSL checks cover `--service-ports`, a single foreground container, key generation, and exit propagation. |
| Official interactive prompts                      | NOT RUN | OpenD may still require account, password, remember-password selection or verification; only the user may perform them.         |
| Real API availability after interactive login     | NOT RUN | Requires user-run login plus encrypted SDK acceptance.                                                                          |

## Phase 9 — scoped Expect convenience proxy (superseded by Phase 10)

At the user's explicit request, the blanket prohibition on Expect-style prompt
assistance was replaced with a narrow reviewed exception. The host-side
`interactive-login.exp` may only fill the configured account, answer the
remember-password choice with `Y`, and expand a bare user-entered six-digit
phone code after OpenD prints its documented command hint. It does not accept a
password through argv, environment, file or agent input, does not source `.env`,
does not write a transcript and does not enable Telnet.

`initialize-and-start.sh` reads only `FUTU_ACCOUNT_ID` from the selected env
file when no shell override exists, disables local terminal echo around the
Expect process, and restores terminal settings on normal exit or signals. The
password passes directly between the user's terminal and OpenD. The phone code
exists briefly in Expect memory to construct the official operation command;
OpenD may echo that expanded command, so authentication sessions must not be
recorded or uploaded. Picture verification and unknown future prompts remain
manual.

| Check                                      | Result  | Notes                                                                                                                                                             |
| ------------------------------------------ | ------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `bash script/interactive-login.test.sh`    | PASSED  | 2 fake-OpenD checks prove account fill, automatic `Y`, bare six-digit expansion, missing-account rejection and absence of the fake password from captured output. |
| `bash script/initialize-and-start.test.sh` | PASSED  | The fake Compose login now exercises the Expect wrapper while preserving single-container and exit-status behavior.                                               |
| `bash script/layer1.test.sh`               | PASSED  | 82 offline assertions passed after adding the two Expect checks. No real account, password, verification code, OpenD, network download or container was used.     |
| Real 10.10.7008 prompt compatibility       | NOT RUN | Chinese prompt matching and actual login remain user-only acceptance.                                                                                             |

## Phase 10 — user-local environment password convenience

At the user's explicit request, the Phase 9 password-source restriction was
removed. The project now defines wrapper-only `FUTU_LOGIN_PASSWORD`; this is
not an OpenD-native setting and does not restore the removed XML account or
password fields. `initialize-and-start.sh` prefers a non-empty shell value and
otherwise reads the local `.env`; unset or empty keeps the manual password
path. The local env file is restricted to mode `0600` before login values are
read.

The wrapper disables xtrace and terminal echo, passes the value only to the
Expect process, and unsets its original environment variable. Expect copies
the value into memory, removes it from its environment before spawning
Docker/OpenD, submits it once at the recognized password prompt, then clears
the Tcl variable. A second password prompt exits with status `77` rather than
retrying. The value is not added to Docker/OpenD argv, environment, XML, or
captured test output. This narrows propagation but does not eliminate the
inherent local exposure of keeping a password in `.env` or a process
environment; same-UID inspection, backups, synchronization, or incorrect host
permissions remain operator risks.

Legacy `FUTU_ACCOUNT_PWD` and `FUTU_ACCOUNT_PWD_MD5` remain rejected because
they represented removed OpenD configuration, while `FUTU_LOGIN_PASSWORD` is
only input to the user-run host prompt proxy. No password or verification code
was supplied to a real OpenD process during this phase.

| Check                                          | Result  | Notes                                                                                                                                                    |
| ---------------------------------------------- | ------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `bash script/interactive-login.test.sh`        | PASSED  | 4 fake-OpenD checks cover manual/env password paths, special characters, single submission, no retry and output/child-env redaction.                     |
| `bash script/initialize-and-start.test.sh`     | PASSED  | 3 fake-Docker/OpenSSL checks cover `.env` and shell override precedence, mode `0600`, redaction and existing single-container behavior.                  |
| `bash script/layer1.test.sh`                   | PASSED  | 85 offline assertions passed; no real account, OpenD, network download or container was used. The Compose model also excludes the fake wrapper password. |
| `npm run test:offline`                         | NOT RUN | `npm` is not installed in the current host environment; its underlying `bash script/layer1.test.sh` command was run directly and passed.                 |
| Real 10.10.7008 prompt compatibility and login | NOT RUN | Must be performed by the user in a private terminal.                                                                                                     |

## Phase 11 — source-free release distribution

The normal consumer path no longer requires a source checkout. A release
template provides image-only Compose services for key initialization and OpenD,
plus a small `futu-opend` command that exposes explicit `init`, `start`, `stop`,
`status`, `logs`, and `reauth` operations. The first interactive process remains
the active API service after login; routine background startup remains a
separate remembered-state lifecycle. The launcher never uses `down -v`, never
inspects the login-state volume, and never passes its optional host-side login
password into the OpenD container.

`build-release-bundle.sh` accepts only a lowercase GHCR reference pinned by a
registry SHA-256 digest and produces a Linux/amd64 archive plus checksum. The
archive contains no Dockerfile, build context, package manifest, or tests. A
new tag-only workflow accepts immutable tags such as `v10.10.7008-r1`, runs
Layers 1 and 2 before registry authentication, pushes the exact revision image,
resolves its registry digest, builds the source-free bundle, and creates the
GitHub Release. No release, image push, tag, or remote setting was created or
changed locally.

| Check                                             | Result  | Notes                                                                                                                                       |
| ------------------------------------------------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `bash script/release_bundle.test.sh`              | PASSED  | 3 checks cover digest pinning, source-free contents, checksum, launcher start/stop arguments, secret exclusion, and volume-preserving stop. |
| Release Compose render                            | PASSED  | Docker Compose accepted a generated bundle using a fake digest and explicit temporary env file; no daemon or image pull was used.           |
| Release workflow YAML parse                       | PASSED  | Ruby parsed the new workflow successfully.                                                                                                  |
| `bash script/ci_config.test.sh`                   | PASSED  | 7 policy checks include tag-only release ordering, permissions, digest resolution, and source-free bundle publication.                      |
| `bash script/build_config.test.sh`                | PASSED  | Existing 5 build/platform/publication assertions remain green.                                                                              |
| `git diff --check`                                | PASSED  | No whitespace errors at the phase checkpoint.                                                                                               |
| Real tagged GitHub Release and GHCR digest        | NOT RUN | Requires an approved artifact lock and an explicit remote tag push; neither was performed.                                                  |
| Real login and remembered startup from the bundle | NOT RUN | User-only Linux/amd64 acceptance; no credentials, key, session, or verification code were accessed.                                         |

## Phase 12 — first release preparation

The exact OpenD 10.10.7008 Ubuntu 18.04 archive was downloaded temporarily
from the fixed official HTTPS origin through the hardened downloader. Its
archive structure passed validation and the resulting SHA-256 was recorded as
a TOFU-reviewed consistency lock in `opend_version.json` and `.env.example`.
This is not a publisher-provided checksum or signature and is described as such
in the README and release notes.

The README now treats the source-free Release asset as the normal user path,
explains that `init` is already the active foreground API service after login,
and lists the routine management commands. The explicit
`v10.10.7008-r1` notes document installation, security defaults, supported
platform, lifecycle, test boundary, Ubuntu 18.04 compatibility limitation, and
non-affiliation. The tag workflow consumes this checked-in notes file instead
of generating generic notes.

| Check                                                    | Result  | Notes                                                                                                          |
| -------------------------------------------------------- | ------- | -------------------------------------------------------------------------------------------------------------- |
| Official-HTTPS temporary download and archive validation | PASSED  | Candidate SHA-256 was calculated after the fixed-origin download and path validation; no archive was retained. |
| `bash script/layer1.test.sh`                             | PASSED  | Offline wrapper/config/release/CI suites passed without credentials or a Docker daemon.                        |
| Workflow YAML and JSON parsing                           | PASSED  | All workflow YAML plus `opend_version.json` and `package.json` parsed successfully.                            |
| `git diff --check`                                       | PASSED  | No whitespace errors before the release commit.                                                                |
| Full npm Layer 1                                         | NOT RUN | Node and npm are unavailable on this host; the release workflow installs dependencies and reruns it.           |
| Local Layer 2 image smoke                                | NOT RUN | Docker daemon is unavailable; the release workflow must pass it before registry authentication.                |
| Real login / SDK readiness                               | NOT RUN | Remains user-only and is not a release-workflow claim.                                                         |

## Phase 13 — macOS Apple Silicon host release

The maintained OpenD image remains the exact Linux/amd64 target; no Linux/arm64
or native macOS OpenD binary was introduced. The release builder now accepts an
explicit host platform and produces separate `linux-amd64` and
`macos-apple-silicon` source-free archives around the same registry-digest-pinned
image. The tag workflow publishes both archives and both SHA-256 files in one
GitHub Release.

Generated launchers embed immutable host metadata. Before Docker or any named
volume is accessed, the Linux package requires `Linux/x86_64` and the macOS
package requires `Darwin/arm64`. Both require Compose v2, an accessible Docker
engine, and Linux-container mode. The Apple Silicon documentation recommends
Docker Desktop's Apple Virtualization framework with Rosetta while explicitly
describing the package as amd64 emulation rather than a native arm64 build.

The release launcher's key generation now handles macOS LibreSSL, which emits
traditional PKCS#1 by default but rejects OpenSSL 3's `-traditional` option. It
tries the explicit OpenSSL 3 form first, falls back to the portable `genrsa`
form, and then independently rejects anything without the unencrypted PKCS#1
header. Existing keys are still never overwritten and host mode remains
`0600`.

The `v10.10.7008-r3` notes and user documentation describe both artifacts,
checksums, requirements, login lifecycle, emulation boundary, and unchanged
security defaults. The repo-local operator skill was narrowly updated so future
installation requests select the matching host archive without weakening its
credential or real-login boundaries.

| Check | Result | Notes |
| --- | --- | --- |
| `bash script/release_bundle.test.sh` | PASSED | 5 checks cover both archive/checksum pairs, source-free contents, embedded host metadata, mismatch rejection before Docker, Docker/secret/volume behavior, and the LibreSSL PKCS#1 fallback. |
| `bash script/layer1.test.sh` | PASSED | 91 offline shell/config assertions passed with fake credentials and isolated temporary resources; no real login or production state was accessed. |
| Apple Silicon Docker preflight | PASSED | On `Darwin/arm64`, Docker Desktop reported `linux/aarch64` and Compose v2. |
| Generated macOS bundle `status` | PASSED | The extracted bundle passed its real host/engine checks and rendered a read-only Compose status without pulling an image or starting a container. |
| `bash script/container_smoke.test.sh` | PASSED | On the Apple Silicon host, Docker Desktop built and ran the locked Linux/amd64 image under emulation, validating architecture, non-root identity, files, help arguments, fake wrapper configuration, and controlled PID-1 termination. |
| Workflow YAML and skill frontmatter parse | PASSED | Ruby parsed all workflow YAML and the skill's required frontmatter fields. |
| Skill Creator `quick_validate.py` | NOT RUN | The available Python lacks the validator's `yaml` module; the direct YAML parse and project behavior tests above were used without installing a new dependency. |
| Full `npm run test:layer1` | NOT RUN | `npm` is not installed on this host; its shell/config subset passed separately. |
| Real login, remembered session, and encrypted SDK readiness | NOT RUN | These remain user-only acceptance steps and were not inferred from the successful emulated smoke. |
| Tagged `v10.10.7008-r2` GitHub Release | FAILED | The immutable tag was pushed, but Ubuntu Layer 1 exposed a BSD-only `stat -f` assertion in the new release test. The workflow stopped before registry authentication, image push, bundle creation, or Release publication. |

## Phase 14 — portable release-test correction and r3 preparation

The failed r2 workflow was diagnosed as a test-only host portability error:
`release_bundle.test.sh` unconditionally used BSD/macOS `stat -f` when checking
the generated key mode. The production launcher already had a portable
GNU/BSD mode helper. The release test now uses the same fallback pattern and
also selects `sha256sum` or `shasum` according to the host. No runtime, login,
network, key-volume, or image behavior was relaxed.

The public r2 tag was left unchanged. User download examples and release notes
advance to `v10.10.7008-r3`; the next tag reruns every pre-publication gate and
publishes nothing unless they all pass.

| Check | Result | Notes |
| --- | --- | --- |
| macOS `bash script/release_bundle.test.sh` | PASSED | All 5 dual-host bundle checks passed on Darwin/arm64. |
| Ubuntu/amd64 release test reproduction | PASSED | The same 5 checks passed in a read-only-mounted `ubuntu:22.04` container with no network, credentials, or production resources. |
| r2 publication boundary | PASSED | Public workflow evidence shows Layer 2, registry authentication, image push, digest resolution, bundle build, and GitHub Release creation were all skipped after Layer 1 failed. |
| Tagged `v10.10.7008-r3` GitHub Release | NOT RUN | Requires the corrected commit and new immutable tag to be pushed. |
