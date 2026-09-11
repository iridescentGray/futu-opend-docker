Futu OpenD release bundle (macOS Apple Silicon host)

This bundle runs the pinned Linux/amd64 OpenD image through Docker Desktop
emulation. It is not a native arm64 OpenD image.

Requirements:
- An Apple Silicon Mac (M1 or newer)
- Docker Desktop with the Linux container engine and Compose v2
- Apple Virtualization framework with Rosetta enabled is recommended
- OpenSSL/LibreSSL and Expect (the macOS system versions are supported)

Podman support is currently limited to the Linux/amd64 bundle; this macOS
bundle retains its tested Docker Desktop path.

1. Start Docker Desktop and wait until the engine is ready.
2. cp env.example .env
3. Edit .env and keep it private.
4. First login or reauthentication: ./futu-opend init
5. Routine background startup: ./futu-opend start

Other commands:
  ./futu-opend status
  ./futu-opend logs
  ./futu-opend stop

Do not run docker compose down -v. The named data volume holds remembered
login state. Login and verification must be completed in a private terminal.
