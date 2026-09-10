---
name: futu-opend
description: |
  Install and operate this fork's FutuOpenD 10.10.7008 Docker Compose service.
  Use for setup, initialization, remembered startup, restart, reauthentication,
  version changes, troubleshooting, or teardown requests.
---

# FutuOpenD fork operator

This fork targets one personal Linux/amd64 OpenD 10.10.7008 instance under
Docker Compose. Read `AGENTS.md`, `README.md`, and
`docs/fork-hardening.md` before acting.

## Non-negotiable login boundary

- Never request, retrieve, hash, enter, output, or transmit a real password,
  password MD5, verification code, private key, or login-cache content.
- Never use a password manager or account connector to find credentials.
- Never run a real OpenD login. The user alone performs interactive login and
  verification in a private local terminal.
- Never automate prompts with `expect`, Telnet, file drops, or similar input.
- Never clear, rename, migrate, or inspect the contents of the
  `futu-opend-data` volume as a login-recovery action.
- Never run `docker compose down -v` or global Docker cleanup.

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

For first initialization or reauthentication, tell the user to run the exact
private-terminal procedure from `README.md`. It stops the routine service with
`docker compose down` (without `-v`) before a one-off `interactive` container,
so both flows use the same `futu` user, `/home/futu` HOME, and unchanged named
volume without simultaneous OpenD processes.

Use exactly one complete Compose file:

- `docker-compose.yaml`: default bridge network, API published only on host
  loopback, outbound networking retained.
- `docker-compose.host.yaml`: explicit host-network fallback, no `ports`, API
  bound to host loopback.

Never layer these files. Always keep the selected `--env-file` and `-f` flags
on `config`, `down`, `run`, `up`, and `logs` commands. Do not claim either mode
has authenticated successfully without the user's real-login result.

Telnet and WebSocket are disabled when their port variables are unset or empty.
Telnet has a separate bind-address variable. Same-network bridge containers
can reach the API and must be treated as trusted.

The host key must be a mode-`0600` unencrypted PKCS#1 PEM. `futu-key-init` is a
one-shot, networkless, non-restarting root helper that prepares a mode-`0400`,
actual-`futu`-owned copy in the key volume. OpenD remains non-root and mounts
that volume read-only. Never bypass failures by loosening permissions.

Routine operation uses `FUTU_LOGIN_MODE=remember` and `docker compose up -d`.
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
