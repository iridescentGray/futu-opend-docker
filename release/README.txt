Futu OpenD release bundle (Linux/amd64 host)

Requirements: Linux/amd64, OpenSSL, Expect, and either Docker Engine with
Docker Compose or Podman with Podman Compose. Rootless Podman is supported and
does not require sudo.

1. cp env.example .env
2. Edit .env and keep it private.
3. First login or reauthentication: ./futu-opend init
4. Routine background startup: ./futu-opend start

Other commands:
  ./futu-opend status
  ./futu-opend logs
  ./futu-opend stop

FUTU_CONTAINER_ENGINE defaults to auto (Docker first, then Podman). To force
an engine, prefix a command with FUTU_CONTAINER_ENGINE=docker or
FUTU_CONTAINER_ENGINE=podman. A Docker-compatible alias is not required.

Do not run compose down -v with either engine. The named data volume holds
remembered login state. Login and verification must be completed in a private
terminal.
