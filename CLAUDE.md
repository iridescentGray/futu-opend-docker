# CLAUDE.md

Agent workflow notes for this FutuOpenD fork. Read `AGENTS.md`, `README.md`,
and `docs/fork-hardening.md` first; their safety boundaries apply here.

## Current target and login model

The maintained target is one personal Linux/amd64 Docker Compose instance with
OpenD 10.10.7008.

- `FUTU_LOGIN_MODE=interactive` is a wrapper mode for first initialization or
  reauthentication. Only the user runs it in a private attached terminal.
- `FUTU_LOGIN_MODE=remember` passes the documented `-login_account`, optional
  `-area_code`, and `-login_by_remember=1` arguments.
- Account/password fields must not exist in XML. Legacy password environment
  variables are rejected and must never be retrieved or transformed by an
  agent.
- Both modes use the same `futu` user, `/home/futu` HOME, and unchanged
  `futu-opend-data` volume. Never run them simultaneously and never clear the
  volume as automatic recovery.

The exact user-run commands are in `README.md`. Do not execute them for the
user because they can enter the real login and verification flow.

## Safe development commands

```bash
# Complete Layer 1 with installed Node dependencies
npm run test:layer1

# Shell/config subset without Node dependencies
npm run test:offline

# Layer 2 requires Docker plus the reviewed artifact lock
npm run test:smoke

# Layer 3 default status only; agents never enable RUN_LIVE_TESTS
npm run test:live

# Node unit tests, when Node/npm are available
npm run test:unit

# Shell syntax only
bash -n script/start.sh script/start.test.sh \
  script/download_futu_opend.sh script/download_futu_opend.test.sh

# Scrape the version page (networked; do not run unless requested)
node script/check_version.js
```

`npm run test:e2e` remains the legacy skip. The current operator-only read-only
acceptance command is `npm run test:live`, which agents must leave disabled.
See `docs/E2E.md`.

## Runtime structure

1. `Dockerfile` packages the upstream OpenD binary and creates the non-root
   `futu` UID/GID 10001 and state directory. It has one final `runtime` target,
   requires version plus pre-recorded artifact SHA-256, and pins both amd64 base
   manifests. There is no maintained CentOS target or Dockerfile version fallback.
2. `script/start.sh` validates wrapper inputs, acquires the shared-state lock,
   XML-escapes explicit template values, writes mode-`0600` runtime config,
   builds an argument array, and `exec`s OpenD as PID 1.
3. `docker-compose.yaml` is the complete bridge default: API is published only
   on host loopback, while outbound and same-network access remain possible.
   `docker-compose.host.yaml` is a separate complete host-mode fallback with no
   `ports`; never layer the files.
4. `script/init-key.sh` is the only root helper. It is networkless and
   non-restarting, copies a host mode-`0600` key into the key volume as the
   actual `futu` UID/GID and mode `0400`; OpenD mounts it read-only as `futu`.
5. Tests are split into offline unit/config, isolated no-credential container
   smoke, and user-only encrypted read-only SDK acceptance. Only the last layer
   can establish `qot_logined`; it is never enabled by agents or public CI.

The current artifact lock is deliberately empty because no publisher checksum
was found and the package was unavailable from this environment. Build/CI must
fail until a human follows README's explicit TOFU review and records the digest;
never manufacture or silently refresh it during a build.

Do not pass `-no_monitor` until the actual Linux/amd64 10.10.7008 binary's
parent/monitor behavior has been observed in isolation. CI checks that
`FutuOpenD -help` lists the login parameters used by the wrapper, but a local
target-runtime run is still required before claiming the binary behavior is
verified.
