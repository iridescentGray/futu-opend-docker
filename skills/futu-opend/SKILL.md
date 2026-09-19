---
name: futu-opend
description: |
  Install and operate this fork's FutuOpenD 10.10.7008 Docker or Podman
  service on Linux/amd64, or Docker Desktop service on an Apple Silicon Mac.
  Use for setup, initialization,
  remembered startup, restart, reauthentication, version changes,
  troubleshooting, or teardown requests.
---

# FutuOpenD fork operator

This fork targets one personal Linux/amd64 OpenD 10.10.7008 container under
Docker Compose or native rootless Podman. Source-free bundles support native Linux/amd64 hosts;
Apple Silicon Macs retain Docker Desktop amd64 emulation. Read `AGENTS.md`,
`README.md`, `docs/deployment.md`, and `docs/fork-hardening.md` before acting.

## Non-negotiable login boundary

- Agents must never request, retrieve, hash, enter, output, or transmit a real password,
  password MD5, verification code, private key, or login-cache content.
- Never use a password manager or account connector to find credentials.
- Never run a real OpenD login. The user alone performs interactive login and
  verification in a private local terminal.
- The reviewed host-side `interactive-login.exp` may prefill the configured
  account, submit wrapper-only `FUTU_LOGIN_PASSWORD` once, answer the remember
  choice with `Y`, and expand a user-entered bare six-digit phone code. Agents
  never read or supply the password. It must not put the value in Docker/OpenD
  argv, environment, XML, or logs. Telnet and file-drop automation remain
  prohibited.
- Never clear, rename, migrate, or inspect the contents of the
  `futu-opend-data` volume as a login-recovery action.
- Never run Compose `down -v` or global Docker/Podman cleanup.

## Login model

`FUTU_LOGIN_MODE` is implemented by this repository, not by OpenD.

- `interactive`: official first-run or reauthentication flow. It requires an
  attached stdin/stdout TTY and passes only `-cfg_file` to OpenD.
- `remember`: routine startup. It requires `FUTU_ACCOUNT_ID` and passes
  `-login_account`, optional documented `-area_code`, and
  `-login_by_remember=1` as separate arguments.

OpenD 10.10.7008 removed login account/password settings from XML. Legacy
`FUTU_ACCOUNT_PWD` and `FUTU_ACCOUNT_PWD_MD5` values are migration errors; do
not restore or transform them.

Official sources:

- <https://openapi.futunn.com/futu-api-doc/en/opend/opend-cmd.html>
- <https://openapi.futunn.com/futu-api-doc/en/changelog/changelog.html>

## Safe Compose guidance

For normal consumers, prefer the source-free release bundle. It contains a
digest-pinned image-only `compose.yaml`, `env.example`, the login proxy, and a
small `futu-opend` launcher. After the user copies `env.example` to `.env` and
configures it, use `./futu-opend init` for the user-only first login or
reauthentication and `./futu-opend start` for later remembered background
startup. `stop`, `status`, and `logs` are also available. The bundle never
builds locally and its stop command preserves both named volumes.

Select the archive matching the host: `linux-amd64` for a Linux x86-64 host or
`macos-apple-silicon` for an M-series Mac. The macOS archive is a host
compatibility package, not a native arm64 OpenD image. It requires Docker
Desktop in Linux-container mode with Compose v2; Apple Virtualization framework
with Rosetta is recommended. Do not bypass the launcher's host or engine checks.
The Linux launcher defaults `FUTU_CONTAINER_ENGINE` to `auto`, preferring a
working `docker compose` and otherwise using native rootless Podman. The
release Podman path does not require a Compose provider.
Explicit `docker` and `podman` selections do not fall back. Rootless Podman is
the supported Podman path; do not use sudo, aliases, privileged containers,
`:U`, or `--userns=keep-id`. The macOS bundle remains Docker-only.

Do not tell a release-bundle consumer to run the source-tree scripts below.
Those remain the maintainer/developer path.

For first initialization or reauthentication, tell the user to run
`bash script/initialize-and-start.sh` in a private terminal. This single user
command safely prepares a missing key, stops the routine service without `-v`,
runs the key initializer to successful completion, then runs one `interactive`
container with service ports in the foreground and keeps that same OpenD
process as the API service after official login. It does
not start a second container or infer login success from an exit code or file.
The host-side Expect proxy fills the configured account and `Y`, optionally
submits a non-empty local `FUTU_LOGIN_PASSWORD` once, and accepts a bare
six-digit phone code only after the official command hint. Empty/unset password
configuration preserves direct terminal input. Authentication transcripts must
not be recorded.

If `FUTU_OPEND_SHA256` is empty, the same command invokes
`script/lock-artifact.sh`: it downloads only a temporary copy from the fixed
official HTTPS origin, validates it, displays the candidate, and atomically
updates the local `.env` without another prompt. Executing initialization is
the user's explicit choice to accept this TOFU behavior; it is not publisher
authentication. Agents never invent a digest.

Use exactly one complete base Compose file:

- `docker-compose.yaml`: default bridge network, API published only on host
  loopback, outbound networking retained.
- `docker-compose.host.yaml`: explicit host-network fallback, no `ports`, API
  bound to host loopback.

Never layer those two base files. `docker-compose.integration.yaml` is the only
supported override and may layer only on the default bridge file. A non-empty
`FUTU_SHARED_NETWORK` makes the source initializer and release launcher add it
automatically; the deployment environment must pre-create that external
network, and Compose teardown must not delete it. On a server that also has
Docker, force `FUTU_CONTAINER_ENGINE=podman` so both projects use the same
rootless Podman network.

Always keep the selected `--env-file` and `-f` flags
on `config`, `down`, `run`, `up`, and `logs` commands. Do not claim either mode
has authenticated successfully without the user's real-login result.

Telnet and WebSocket are disabled when their port variables are unset or empty.
Telnet has a separate bind-address variable. Same-network bridge containers
can reach the API and must be treated as trusted.

The host key must be a mode-`0600` unencrypted PKCS#1 PEM. `futu-key-init` is a
one-shot, networkless, non-restarting root helper that prepares a mode-`0400`,
actual-`futu`-owned copy in the key volume. OpenD remains non-root and mounts
that volume read-only. Never bypass failures by loosening permissions.

Routine operation uses `FUTU_LOGIN_MODE=remember`. With the release bundle,
always use `./futu-opend start`; it resolves the
engine, prepares the key volume explicitly, and starts OpenD only after that
step succeeds. Source initialization accepts
`FUTU_CONTAINER_ENGINE=podman bash script/initialize-and-start.sh`.
If remembered state is missing or rejected, stop and point back to the manual
reauthentication procedure. Do not infer login success from a directory or
wrapper lock file, and do not promise that Futu will keep the session valid.

## Verification

Safe Layer 1 verification:

```bash
npm run test:offline
```

This uses only temporary files and a fake OpenD. It proves argument, config,
TTY/stdin, signal, exit-status, and wrapper-lock behavior only. It does not
prove a real login, remembered-session validity, API readiness, or OpenD's own
monitor behavior.

Layer 2 is `npm run test:smoke`; it uses only unique resources and no
credentials, but still does not prove login or readiness. Layer 3 is
`npm run test:live` and defaults to `SKIPPED`. Never set `RUN_LIVE_TESTS=1` as
an agent; only the user may run the encrypted read-only acceptance after private
initialization. Do not deploy, publish, push, or mutate remote settings unless
the user separately asks.
