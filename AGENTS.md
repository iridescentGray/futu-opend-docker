# PROJECT KNOWLEDGE BASE

**Generated:** 2026-04-26T08:48:32Z
**Commit:** b800b90
**Branch:** main
**Companion file:** see [CLAUDE.md](CLAUDE.md) for Claude Code workflow tips, daily commands, and operational gotchas; this file owns the structure tables, conventions, and reference data.

## OVERVIEW

Docker/Podman containerization for Futu OpenD — a trading API gateway for Futu Securities. The maintained build is one pinned Ubuntu-based Linux/amd64 target with automated version tracking and CI/CD to GHCR. Source-free releases support Docker or rootless Podman on Linux/amd64 and Docker Desktop amd64 emulation on Apple Silicon Macs.

> **For agents operating in this repo**: when the user asks to install, set up, deploy, restart, re-login, send an SMS code to, bump the version of, or troubleshoot FutuOpenD, follow [`skills/futu-opend/SKILL.md`](skills/futu-opend/SKILL.md). The skill collapses the scattered procedures in this file, [README.md](README.md), [k8s/README.md](k8s/README.md), [CLAUDE.md](CLAUDE.md), and [docs/E2E.md](docs/E2E.md) into one runbook covering compose / `docker run` / Kubernetes targets.

## STRUCTURE

```text
.
├── Dockerfile              # Pinned linux/amd64 fetch + runtime stages; final target is runtime
├── docker-compose.yaml     # Standalone default: bridge + loopback API publication
├── docker-compose.integration.yaml # Optional deployment-owned external trusted-client network
├── docker-compose.host.yaml # Standalone host-network compatibility mode; never merge with default
├── FutuOpenD.xml           # Login-free config template rendered safely at runtime
├── opend_version.json      # Version/artifact/base lock proposed through review PRs
├── package.json            # Layer 1, container smoke, default-skipped live acceptance
├── .env.example            # Tracked template — copy to ignored .env and set local account/config values
├── docs/
│   ├── deployment.md       # Detailed build, login, key, network and state-volume guide
│   └── E2E.md              # Three test layers, proof boundaries, CI and cleanup
├── release/                # Source-free operator bundle templates; image-only Compose + launcher
├── k8s/                    # Reference k8s deployment + harness backend (kind/existing)
│   ├── README.md           # Deploy + first-run SMS/CAPTCHA via kubectl, plus local-dev kind flow
│   ├── deployment.yaml     # Single-replica, hostNetwork, init-chown, 0644 RSA, pgrep liveness
│   ├── pvc.yaml            # 1Gi RWO PVC for /home/futu/.com.futunn.FutuOpenD
│   ├── namespace.yaml      # futu-opend namespace
│   ├── secret.example.yaml # Reference Secret template (NOT applied via kustomize)
│   ├── kustomization.yaml  # namespace + pvc + deployment
│   └── kind-config.yaml    # Local-dev kind cluster (used by npm run test:k8s)
├── skills/                 # Agent-neutral runbook — install + day-2 ops for compose/docker run/k8s
│   └── futu-opend/
│       ├── SKILL.md        # Entry point with YAML frontmatter; load this first
│       └── references/     # Per-target / per-task detail pulled in on demand
├── script/
│   ├── start.sh            # Entrypoint — validates login mode, renders XML, execs OpenD
│   ├── container-engine.sh # Shared Docker/Podman Compose auto/explicit resolver
│   ├── container-engine.test.sh # Fake-binary engine-selection matrix
│   ├── podman_smoke.test.sh # Rootless Podman build/Compose/key-volume smoke
│   ├── build-release-bundle.sh # Creates digest-pinned Linux and Apple Silicon host archives + checksums
│   ├── release_bundle.test.sh # Offline release contents/launcher regression checks
│   ├── start.test.sh       # Offline fake-OpenD wrapper tests
│   ├── initialize-and-start.sh # Automatic local lock/key setup + port-published interactive service
│   ├── initialize-and-start.test.sh # Fake Docker/OpenSSL orchestration tests
│   ├── interactive-login.exp # Host-side prompt proxy: account/Y defaults + bare phone code
│   ├── interactive-login.test.sh # Fake OpenD prompt, redaction and transformation tests
│   ├── lock-artifact.sh    # Fixed-origin TOFU download and atomic local .env SHA lock
│   ├── lock-artifact.test.sh # Fake-download artifact-lock tests
│   ├── init-key.sh         # One-shot root helper: mode-0600 host key → futu-owned mode-0400 key volume
│   ├── init-key.test.sh    # Offline fake-key failure/metadata tests
│   ├── compose.test.sh     # docker compose config assertions with an explicit fake env file
│   ├── container_smoke.test.sh # Isolated no-credential Linux/amd64 image smoke
│   ├── live_readonly.py    # User-enabled encrypted GetGlobalState acceptance
│   ├── download_futu_opend.sh  # HTTPS-only, bounded download + archive/SHA-256 validation
│   ├── check_version.js    # Version scraper with retry, timeout, validation
│   ├── check_version.test.js   # Unit tests (node:test, CJS)
│   ├── e2e.test.mjs        # Explicit skip for the removed unsafe real-login harness
│   ├── e2e.k8s.test.mjs    # K8s manifest-equivalence harness (ESM, kind|existing backend)
│   └── lib/
│       ├── docker.mjs      # compose / inspect / telnet helpers (ESM)
│       ├── k8s.mjs         # kind / kubectl / port-forward helpers (ESM)
│       └── _pending/       # Parked: futu-api SDK round-trip experiment (not active)
└── .github/workflows/      # Read-only PR CI, trusted publish, lint, review-only version PR
```

## WHERE TO LOOK

| Task                                   | Location                                                               | Notes                                                                                             |
| -------------------------------------- | ---------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| Add build arg                          | `Dockerfile` (FUTU_OPEND_VER ARG sites)                                | Default matches supported `10.10.7008`; CI passes an explicit value                               |
| Modify startup                         | `script/start.sh`                                                      | Login validation, safe XML rendering, state lock, and `exec` happen here                          |
| Change CI triggers                     | `.github/workflows/publish.yml`                                        | Locked stable Ubuntu/amd64 image → GHCR                                                           |
| Update config template                 | `FutuOpenD.xml`                                                        | Login-free template with explicit `###FUTU_OPEND_*###` placeholders                               |
| Test startup wrapper                   | `script/start.test.sh`                                                 | Offline fake OpenD; never proves real login                                                       |
| Initialize or reauthenticate           | `script/initialize-and-start.sh`                                       | Docker/Podman auto-selection; user-only private TTY; current process serves API after login       |
| Build consumer release bundle          | `script/build-release-bundle.sh`, `release/`                           | Produces Linux/amd64 and macOS Apple Silicon host archives using one registry-digest-pinned image |
| Operate from release bundle            | `release/futu-opend`, `release/compose*.yaml`                          | `init` for first login; `start` for remembered background startup; optional trusted network       |
| Modify interactive conveniences        | `script/interactive-login.exp`                                         | Wrapper-only env password is single-use; fake OpenD tests required; no Telnet                     |
| Lock local first-trust artifact        | `script/lock-artifact.sh`                                              | Fixed official HTTPS temp download and atomic `.env` update; TOFU, not publisher authentication   |
| Test Compose and key preparation       | `script/compose.test.sh`, `script/init-key.test.sh`                    | Offline/fake inputs; Compose config only, no daemon                                               |
| Version detection                      | `script/check_version.js`                                              | Scraper with retry, timeout, validation                                                           |
| Run unit tests                         | `script/check_version.test.js`                                         | `npm run test:unit`                                                                               |
| Run layered verification               | `package.json`, `docs/E2E.md`                                          | Layer 1 offline; Layer 2 no-credential container; Layer 3 user-only live                          |
| Review detailed deployment behavior    | `docs/deployment.md`                                                   | Build lock, key handling, login lifecycle, networks, health and state volumes                     |
| Run k8s e2e                            | `script/e2e.k8s.test.mjs`                                              | `npm run test:k8s` (kind = manifest-only) or `K8S_E2E_BACKEND=existing npm run test:k8s`          |
| Deploy on k8s                          | `k8s/`                                                                 | `kubectl apply -k k8s/`; SMS/CAPTCHA flow at [k8s/README.md](k8s/README.md)                       |
| Compose helpers (Node)                 | `script/lib/docker.mjs`                                                | `composeUp`, `sendTelnetCommand`, `tailLogs`, `inspectHealth`                                     |
| K8s helpers (Node)                     | `script/lib/k8s.mjs`                                                   | `createKindCluster`, `kindLoadImage`, `tailKubectlLogs`, `startPortForward`                       |
| Enable WebSocket                       | `script/start.sh` (websocket section)                                  | Set `FUTU_OPEND_WEBSOCKET_PORT` (default disabled)                                                |
| Persist login session                  | `docker-compose.yaml` `futu-opend-data`                                | Mounted at `/home/futu/.com.futunn.FutuOpenD`                                                     |
| Tweak compose env                      | ignored `.env` copied from `.env.example`                              | Always pass `--env-file .env`; offline tests create explicit fake env files                       |
| Add npm script                         | `package.json`                                                         | Preserve `test:layer1`, `test:smoke`, `test:live`, and explicit legacy skip                       |
| Propose first-trust artifact hash      | `bash script/download_futu_opend.sh --report-tofu <version> <tarball>` | Temporary official-HTTPS download; not publisher authenticity proof                               |
| Drive install / day-2 ops via an agent | `skills/futu-opend/SKILL.md`                                           | Fork-safe Compose runbook; real login and verification remain user-only                           |

## CONVENTIONS

- **Multi-stage Docker**: `fetch` downloads the locked Ubuntu 18.04 artifact; `runtime` is both the explicit and default final Linux/amd64 stage. There is no `BASE_IMG` switch or maintained CentOS target.
- **Non-root OpenD**: The main process runs as `futu`. The isolated `futu-key-init` service runs once as root, with no network and `restart: "no"`, only to copy a read-only mode-`0600` host key into the key volume as the actual `futu` UID/GID and mode `0400`.
- **Container engine selection**: `FUTU_CONTAINER_ENGINE=auto` prefers a working `docker compose` and otherwise uses a working `podman compose`; explicit `docker|podman` never falls back. Source and release launchers explicitly finish `futu-key-init` before starting OpenD with `--no-deps`.
- **Login modes (OpenD 10.10.7008 only)**: `FUTU_LOGIN_MODE=interactive` preserves an attached private TTY for official first-run login; `remember` requires `FUTU_ACCOUNT_ID` and passes the documented `-login_account` / `-login_by_remember=1` arguments. Phone accounts may set wrapper input `FUTU_ACCOUNT_AREA_CODE=+NN`; these environment variables are not native OpenD settings.
- **Passwords**: OpenD 10.10.7008 removed account/password XML settings. Never write them to XML. Non-empty legacy `FUTU_ACCOUNT_PWD` / `FUTU_ACCOUNT_PWD_MD5` inputs fail with a value-free migration message. User-local `FUTU_LOGIN_PASSWORD` belongs only to the host login wrapper; agents never read or supply it.
- **Scoped Expect proxy**: the host-side proxy may fill `FUTU_ACCOUNT_ID`, submit non-empty wrapper-only `FUTU_LOGIN_PASSWORD` once, answer the remember choice with `Y`, and expand a bare user-entered six-digit phone code only after the official hint. It removes the password before spawning Docker/OpenD and never writes a transcript, enables Telnet, retries a rejected password, or claims login success.
- **Env var injection**: `FUTU_LOGIN_MODE`, `FUTU_ACCOUNT_ID`, optional `FUTU_ACCOUNT_AREA_CODE`, `FUTU_OPEND_RSA_FILE_PATH`, `FUTU_OPEND_IP`, `FUTU_OPEND_PORT` (11111), optional independent `FUTU_OPEND_TELNET_IP` / `FUTU_OPEND_TELNET_PORT`, and optional WebSocket variables. Unset or empty optional ports mean disabled.
- **Compose network files**: `docker-compose.yaml` is the complete bridge default and publishes API only on host `127.0.0.1`; `docker-compose.host.yaml` is a complete host-mode fallback with no `ports` and loopback bind. Never layer the two base files. `docker-compose.integration.yaml` is the sole optional override, layers only on bridge mode, and joins a deployment-owned external trusted-client network when `FUTU_SHARED_NETWORK` is non-empty.
- **Listener guards**: non-loopback API binds require a readable RSA key. Non-loopback WebSocket is rejected until the repository supports the TLS certificate configuration required by official documentation.
- **Version tracking**: scheduled CI proposes review-only PRs for `opend_version.json`; it never auto-merges, publishes, or deploys.
- **ESM boundary**: e2e code is `.mjs` (ESM); `check_version.test.js` stays CJS. Don't add `"type": "module"` to `package.json` until that migrates.
- **Module conventions**: `script/lib/_pending/` holds parked experiments; never import from there in shipping code.

## ANTI-PATTERNS (THIS PROJECT)

- **NEVER** run containers as root — `USER futu` enforced.
- **NEVER** hardcode credentials — use env vars or your local (gitignored) `.env` file. The tracked `.env.example` template must stay credential-free.
- **NEVER** put login account or password fields in `FutuOpenD.xml` — it is a login-free template rendered by `start.sh`.
- **NEVER** skip RSA key — required for API encryption.
- **NEVER** claim bridge or host login is verified without a user-run real login. Bridge is the default; host mode is an explicit standalone compatibility file.
- **NEVER** loosen the host key beyond `0600`. The main service reads a separate futu-owned `0400` copy from a read-only key volume.
- **NEVER** call process health API readiness. The Compose/Dockerfile PID-1 `/proc` check is liveness only, and Docker does not restart solely because health is `unhealthy`.
- **NEVER** render Compose config or inspect container environments in shared sessions — output may contain account or other private configuration.
- **NEVER** import `futu-api` from `script/lib/_pending/` — intentionally not in `package.json`.

## UNIQUE STYLES

- **XML templating**: `start.sh` XML-escapes values and substitutes explicit placeholders without `sed` or `eval`; runtime configuration is mode `0600` and contains no login fields.
- **Pinned bases**: Ubuntu 22.04 amd64 fetch stage plus Ubuntu 18.04 amd64 compatibility runtime, both by manifest digest. Bionic is out of standard support and remains pending real binary migration validation.
- **Apple Silicon host release**: The macOS package runs the same `linux/amd64` image through Docker Desktop emulation. It validates `Darwin/arm64` and Linux-container mode and never claims to be a native arm64 OpenD image.
- **Liveness/readiness split**: health checks PID 1's `/proc` process name; readiness requires an SDK result and is never inferred from health.
- **First login / reauthentication**: only the user runs `bash script/initialize-and-start.sh` in a private TTY. The helper records a missing local TOFU lock, prepares a missing key, and runs one port-published `interactive` container through the reviewed Expect proxy. The proxy fills account/`Y`, optionally submits the local wrapper password once, and accepts the user's verification code. After official login that same process serves the API; no second container is started.
- **Login session persistence**: Named volume `futu-opend-data` at `/home/futu/.com.futunn.FutuOpenD`; the Dockerfile pre-creates the path with `futu:futu` ownership for first-mount inheritance.

## COMMANDS

> Day-to-day safe development commands live in [CLAUDE.md](CLAUDE.md); exact user-run Compose/login commands live in [README.md](README.md).

## VERSIONS & PORTS

| Fact                      | Value                       | Source of truth                                                      |
| ------------------------- | --------------------------- | -------------------------------------------------------------------- |
| Stable OpenD              | 10.11.7108                  | `opend_version.json` <!-- futu-opend-version -->                     |
| Beta OpenD                | null                        | `opend_version.json`                                                 |
| Build version input       | required `FUTU_OPEND_VER`   | Compose/CI reads `opend_version.json`; Dockerfile has no fallback    |
| `.env.example` default    | 10.11.7108                  | `.env.example` (mirrors stable on bumps) <!-- futu-opend-version --> |
| Runtime base              | pinned `ubuntu:18.04` amd64 | `opend_version.json` + `Dockerfile`; compatibility baseline, EOL     |
| Build base                | pinned `ubuntu:22.04` amd64 | `opend_version.json` + `Dockerfile`                                  |
| Artifact integrity        | TOFU-reviewed SHA-256       | Fixed official-HTTPS archive; not publisher signature authentication |
| API port                  | 11111                       | env `FUTU_OPEND_PORT`                                                |
| Telnet port (optional)    | disabled                    | set both Telnet IP and port explicitly to opt in                     |
| WebSocket port (optional) | disabled                    | env `FUTU_OPEND_WEBSOCKET_PORT`; not host-published by default       |

## TEST LAYERS

- `npm run test:layer1`: unit/config tests with fake OpenD, key, curl, archives,
  SDK, Compose models, and CI policy. No Docker daemon or credentials.
- `npm run test:smoke`: isolated image build/container smoke with unique test
  resources and no credentials. It never proves login or readiness.
- `npm run test:live`: defaults to `SKIPPED`; only the user may enable
  `RUN_LIVE_TESTS=1` after private login. It performs encrypted read-only
  `get_global_state()` and requires quote login; trade login is optional.
- Agents never enable Layer 3. Fake results never count as real login.

## NOTES

- **RSA key required**: User-generated unencrypted PKCS#1 RSA key, retained at host mode `0600`; `futu-key-init` prepares the main service's read-only mode-`0400` copy. Never output the key.
- **Slow startup**: FutuOpenD takes 2–3 minutes to initialize; process liveness has a 180 s grace period and does not prove readiness.
- **Interactive verification**: OpenD may request verification during user-run initialization. Do not automate or perform it in an agent session.
- **Tests**: use the three commands above and report each layer separately. The legacy `test:e2e` skip is not a live acceptance signal.
- **Download**: normal mode requires version, exact tarball name, and a pre-recorded SHA-256. `--report-tofu` only proposes a reviewed first-trust digest and never installs the download.
- **Login session persistence**: interactive initialization and routine `remember` startup use the unchanged `futu-opend-data` volume, `futu` user, and `/home/futu` HOME. Never clear it as an automatic recovery step.
- **Disclaimer**: Not affiliated with Futu Securities.

## FORK HARDENING

This fork is maintained for long-term personal use. The primary target is a
single Linux/amd64 FutuOpenD instance managed with Docker Compose. Follow these
constraints for all hardening work:

- Make small, reviewable changes. Reuse the existing structure and test tools,
  and do not add runtime dependencies without a demonstrated need.
- Preserve `LICENSE` and upstream attribution.
- Never read or output real `.env` files, passwords, password MD5 values,
  private keys, verification codes, or login-cache contents.
- Do not query password managers or other external account connections for
  credentials.
- Do not perform a real login, unlock trading, place or cancel orders, move
  funds, or enable paid permissions.
- Do not erase or migrate existing production data volumes, and never run a
  global Docker cleanup.
- Tests must use explicitly created temporary directories, fake credentials,
  test keys, and isolated resources.
- Do not disable the sandbox, use privileged containers, or change host
  firewall or Docker daemon configuration.
- Do not automatically push commits, publish images, deploy services, or
  change remote-repository settings.
- Never fabricate test results. Report each check as `PASSED`, `FAILED`,
  `SKIPPED`, or `NOT RUN`.
- At the end of every phase, summarize changes, checks actually executed,
  results, and remaining unverified items, and update the task checklist.
- Advance login, security configuration, builds, and tests as separate phases;
  do not fold unrelated refactors into them.

The audit baseline, evidence, minimal change plan, acceptance criteria, and
phase checklist live in [`docs/fork-hardening.md`](docs/fork-hardening.md).
