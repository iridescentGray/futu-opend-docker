# Futu OpenD Docker

[![Docker Pulls](https://img.shields.io/github/package-json/v/manhinhang/futu-opend-docker)](https://github.com/manhinhang/futu-opend-docker/packages)
[![GitHub](https://img.shields.io/github/license/manhinhang/futu-opend-docker)](https://github.com/manhinhang/futu-opend-docker/blob/main/LICENSE)

Docker Compose packaging for one personal Linux/amd64 command-line FutuOpenD
instance.

## Reproducible build and artifact lock

The supported build is one Ubuntu-based `linux/amd64` target named `runtime`.
CentOS 7 is no longer a default or maintained release path. The official OpenD
package is still labelled for Ubuntu 18.04, so the runtime retains a pinned
Ubuntu 18.04 amd64 image as a compatibility baseline even though that release
is outside standard Ubuntu support. Moving the binary to Ubuntu 22.04 or newer
requires dependency inspection and no-credential startup validation on
Linux/amd64; a successful image build alone is not acceptance.

`opend_version.json` is the build source of truth. Its current OpenD artifact
SHA-256 is intentionally `null`: no publisher signature or checksum for this
artifact was found, and the artifact could not be downloaded in this review
environment. Consequently the default Compose build and publish CI fail closed
until a human reviews and records a first-trust value. Do not copy a digest
from an unreviewed third party.

On a private machine with network access, the maintainer can download from the
fixed official HTTPS origin into a temporary file, validate its versioned
archive paths, and print a candidate digest without installing the file:

```bash
bash script/download_futu_opend.sh --report-tofu \
  10.10.7008 Futu_OpenD_10.10.7008_Ubuntu18.04.tar.gz
```

Review the official release page/changelog, the HTTPS origin, archive contents,
and the candidate digest. Recording that value under
`stableArtifact.sha256`, changing `integrityStatus` to `tofu-reviewed`, and
copying it to local `.env` as `FUTU_OPEND_SHA256` locks later downloads to the
reviewed bytes. Computing a hash from this first download is trust on first use
(TOFU), not publisher-authenticated provenance. Later matching checks prove
consistency with that decision, not independent authenticity.

After the lock is committed, build without any floating Dockerfile version:

```bash
docker build --platform linux/amd64 --target runtime \
  --build-arg FUTU_OPEND_VER=10.10.7008 \
  --build-arg FUTU_OPEND_SHA256="${FUTU_OPEND_SHA256:?not locked}" \
  --tag futu-opend:ubuntu-10.10.7008 .
```

The runtime user is explicitly `10001:10001`; application files stay
root-owned under `/opt/futu-opend` rather than changing ownership of `/bin`.
The existing `futu-opend-data` volume name and mount path are unchanged. If an
older volume is not writable by UID/GID 10001, stop and design a reviewed,
backed-up metadata migration; this project does not automatically chown or
clear production state.

These identifiers are separate and should be recorded together for an accepted
deployment:

- OpenD version: `10.10.7008` and its locked artifact SHA-256.
- Base-image versions and amd64 manifest digests: `opend_version.json` and the
  pinned `FROM` lines.
- Project source: the exact Git commit used for the build.
- Final image: a registry content digest produced after publishing the accepted
  image.

For long-term deployment, use the explicit version tag, inspect its registry
digest, then pin that exact returned value in your private deployment config:

```bash
docker pull ghcr.io/OWNER/futu-opend-docker:ubuntu-10.10.7008
docker image inspect --format '{{index .RepoDigests 0}}' \
  ghcr.io/OWNER/futu-opend-docker:ubuntu-10.10.7008
# Use the returned ghcr.io/...@sha256:<digest>; no digest is fabricated here.
```

Do not use `stable` or `latest` for unattended upgrades. On ARM/macOS, this is
still an amd64 image and may run only through an operator-provided emulation
environment. The project does not install binfmt, start privileged containers,
or claim native arm64 support.

## Supported login model

The wrapper supports OpenD `10.10.7008`. `FUTU_LOGIN_MODE` is this project's
switch, not a native OpenD environment variable:

- `interactive`: user-only initialization or reauthentication in a private
  attached terminal.
- `remember`: routine service startup with the official `-login_account`,
  optional `-area_code`, and `-login_by_remember=1` arguments.

OpenD 10.10.7008 removed account/password settings from XML. Legacy
`FUTU_ACCOUNT_PWD` and `FUTU_ACCOUNT_PWD_MD5` values are rejected without
printing them. The wrapper never automates a password or verification code.

References:

- [Command Line OpenD](https://openapi.futunn.com/futu-api-doc/en/opend/opend-cmd.html)
- [OpenD 10.10.7008 changelog](https://openapi.futunn.com/futu-api-doc/en/changelog/changelog.html)
- [Encrypted communication](https://openapi.futunn.com/futu-api-doc/en/ftapi/protocol.html)
- [SDK encryption configuration](https://openapi.futunn.com/futu-api-doc/en/ftapi/init.html)

## Prepare configuration and key

Copy the tracked template and edit only the ignored local `.env`:

```bash
cp .env.example .env
```

Set `FUTU_ACCOUNT_ID`. For phone-number remembered login, set the phone number
as the account and a separate country code such as
`FUTU_ACCOUNT_AREA_CODE=+86`, matching the official command-line example.

If no key exists, generate it yourself in a private terminal. OpenD's official
protocol documentation specifies an unencrypted PKCS#1 RSA private key and
documents 1024-bit operation; this keeps the project's existing algorithm and
size:

```bash
openssl genrsa -traditional -out futu.pem 1024
chmod 0600 futu.pem
```

Do not overwrite an existing key: local SDK clients must use the same private
key as OpenD. The one-shot `futu-key-init` service mounts the host key read-only,
checks that it is a regular readable mode-`0600` PKCS#1 PEM, and copies it into
the `futu-opend-key` volume as mode `0400` owned by the image's actual `futu`
UID/GID. The main OpenD service runs as `futu` and mounts that key volume
read-only. Key initialization does not generate or display key material and has
`restart: "no"` plus no network namespace.

For Compose, `FUTU_OPEND_RSA_FILE_PATH` must be a direct child of `/.futu`
(the default is `/.futu/futu.pem`) so it remains inside the prepared key volume.

The existing `futu-opend-data` session volume is unchanged.

## Default network: bridge

[`docker-compose.yaml`](docker-compose.yaml) is a complete standalone default:

- ordinary Compose bridge networking;
- the default network is explicitly not internal, so OpenD can make outbound
  connections;
- OpenD binds API to its container interface (`0.0.0.0` by default);
- only the API port is published, fixed to host `127.0.0.1`;
- Telnet and WebSocket are absent from generated XML unless explicitly enabled.

Containers joined to this Compose network can connect directly to
`futu-opend:<FUTU_OPEND_PORT>` and must be treated as trusted API clients. Host
loopback publication does not isolate OpenD from malicious same-network
containers.

Render and review the effective model in a private terminal:

```bash
docker compose --env-file .env -f docker-compose.yaml config
```

This can display the configured account identifier, so do not paste its output
into shared logs.

### First initialization

Stop the routine container without deleting volumes, then run the same service
with a real terminal. Compose starts the key initializer dependency first:

```bash
docker compose --env-file .env -f docker-compose.yaml down
docker compose --env-file .env -f docker-compose.yaml run --rm --interactive \
  -e FUTU_LOGIN_MODE=interactive \
  futu-opend
```

Complete OpenD's prompts yourself and select its password-remembrance option if
you want later `remember` starts. After OpenD reports login success, stop the
foreground process normally. Neither a directory nor the wrapper lock file is
treated as proof of login. This `run --rm` initialization container is one-shot
and has no automatic restart loop.

### Routine startup

```bash
docker compose --env-file .env -f docker-compose.yaml up -d
docker compose --env-file .env -f docker-compose.yaml logs -f futu-opend
```

The routine service has no stdin/TTY and uses `restart: "on-failure:3"`. This
gives a short bounded retry for unexpected non-zero exits but avoids an
unlimited authentication loop. It does not guarantee automatic recovery after
a host reboot; restart behavior also depends on the Docker daemon startup
policy. An operator-requested stop is not treated as a failure restart.

If remembered state is missing or expired, use the same non-destructive
initialization commands again. Do not delete, rename, or migrate the state
volume, and do not retry indefinitely.

## Explicit compatibility network: host

[`docker-compose.host.yaml`](docker-compose.host.yaml) is a second complete
standalone file. It is not an override. Never pass both Compose files in one
command.

The host-mode OpenD service has `network_mode: host`, has no `ports` section,
and binds API to `FUTU_OPEND_HOST_IP=127.0.0.1` by default. Use the same project
directory and do not supply a different project name if you expect it to reuse
the existing state and key volumes.

Review and run it only with the host file named explicitly:

```bash
docker compose --env-file .env -f docker-compose.host.yaml config
docker compose --env-file .env -f docker-compose.host.yaml down
docker compose --env-file .env -f docker-compose.host.yaml run --rm --interactive \
  -e FUTU_LOGIN_MODE=interactive \
  futu-opend
docker compose --env-file .env -f docker-compose.host.yaml up -d
```

Host mode is retained only as a compatibility fallback. Default bridge-mode
authentication and host-mode authentication have not been exercised in this
hardening work; real login remains a user-only verification.

## Optional listeners

For both optional listener ports, unset and explicitly empty have the same
meaning: the corresponding elements are omitted from runtime XML and the
feature is disabled.

```dotenv
FUTU_OPEND_TELNET_PORT=
FUTU_OPEND_WEBSOCKET_PORT=
```

Telnet has its own bind address. To opt in locally:

```dotenv
FUTU_OPEND_TELNET_IP=127.0.0.1
FUTU_OPEND_TELNET_PORT=22222
```

In bridge mode this loopback address is local to the OpenD container and is not
published to the host. Setting it to `0.0.0.0` makes it reachable to trusted
containers on the Compose network, but it is still not host-published by the
provided file. In host mode keep it on `127.0.0.1`.

WebSocket is likewise disabled by default and never host-published by the
bridge file. Non-local WebSocket/TLS configuration is intentionally not added
in this phase; official documentation requires SSL for a non-local WebSocket
listener.

RSA protocol encryption applies to the OpenAPI connection only. It is not a
claim that Telnet or WebSocket traffic is encrypted.

## Liveness, readiness, shutdown, and logs

The Compose healthcheck verifies the PID-1 name via `/proc` and confirms that
the generated XML contains the configured API port. It proves process/config
consistency only. It does not prove login success, remembered-session validity,
API readiness, encryption negotiation, or an SDK round trip. Docker does not
restart a container merely because health becomes `unhealthy`; the bounded
restart policy applies when PID 1 exits non-zero.

The service gives `SIGTERM` up to 30 seconds before forced termination. The
wrapper uses `exec`, so OpenD is PID 1 and receives the signal directly. Actual
OpenD monitor/daemon and graceful-state behavior still require Linux/amd64
runtime verification.

The `json-file` log driver is bounded to three 10 MiB files. No read-only root
filesystem, privileged mode, broad capability changes, firewall changes, or
daemon changes are applied in this phase.

Readiness must be established separately with an SDK connection and actual
OpenD result, not container health alone.

## SDK connection examples

Official SDK encryption requires OpenD and the client to use the same private
key and enables encryption before creating the context.

Local SDK on the Docker host:

```python
from futu import OpenQuoteContext, SysConfig

SysConfig.enable_proto_encrypt(True)
SysConfig.set_init_rsa_file("/absolute/path/to/futu.pem")
quote_ctx = OpenQuoteContext(host="127.0.0.1", port=11111)
quote_ctx.close()
```

SDK in another trusted container on the same Compose default network:

```python
from futu import OpenQuoteContext, SysConfig

SysConfig.enable_proto_encrypt(True)
SysConfig.set_init_rsa_file("/run/secrets/futu.pem")
quote_ctx = OpenQuoteContext(host="futu-opend", port=11111)
quote_ctx.close()
```

Mount the same host key read-only at `/run/secrets/futu.pem` in that client
container, and ensure that client's actual UID can read it without broadening
the host file beyond `0600` (use an equivalent UID-aware secret staging step
when needed). Do not copy it into an image. If `FUTU_OPEND_PORT` changes,
update the SDK port; the provided Compose file updates both the container port
and host-loopback publication together.

These examples perform an encrypted InitConnect when run against a ready
OpenD. They are documentation only and were not executed here.

## Existing state-volume metadata

This phase does not inspect or change existing session data. A user may perform
a metadata-only check while the service is stopped:

```bash
docker compose --env-file .env -f docker-compose.yaml down
docker compose --env-file .env -f docker-compose.yaml run --rm --no-deps \
  --user root --entrypoint stat futu-opend \
  -c '%u:%g %a %F' /home/futu/.com.futunn.FutuOpenD
```

If ownership does not match the image's `futu` user, stop and prepare a
reviewed, backed-up migration plan. Do not recursively chown or clear a
production volume as an automatic fix.

## Layered tests

```bash
# Layer 1: no Docker daemon, credentials, or networked OpenD
npm ci
npm run test:layer1

# Layer 2: isolated no-credential image/container smoke
npm run test:smoke

# Layer 3 default: explicit SKIPPED, never run by public CI
npm run test:live

# Layer 1 shell/config subset when Node dependencies are unavailable
npm run test:offline
```

Layer 1 uses only fake values and temporary resources. Layer 2 builds the locked
image and exercises a controlled fake PID 1, but still proves no login or
business readiness. Layer 3 is the only SDK/login-state acceptance and requires
the user to set `RUN_LIVE_TESTS=1` after private initialization; agents and
public CI do not run it. See [`docs/E2E.md`](docs/E2E.md) for prerequisites,
proof boundaries, timeouts, cleanup, and the optional trading-login condition.

## Disclaimer

This project is not affiliated with
[Futu Securities International (Hong Kong) Limited](https://www.futuhk.com/).
The original license and upstream attribution are preserved in `LICENSE`.
