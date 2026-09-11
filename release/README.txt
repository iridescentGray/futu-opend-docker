Futu OpenD release bundle (Linux/amd64 host)

Requirements: Linux/amd64, a running Docker Linux engine with Compose v2,
OpenSSL, and Expect.

1. cp env.example .env
2. Edit .env and keep it private.
3. First login or reauthentication: ./futu-opend init
4. Routine background startup: ./futu-opend start

Other commands:
  ./futu-opend status
  ./futu-opend logs
  ./futu-opend stop

Do not run docker compose down -v. The named data volume holds remembered
login state. Login and verification must be completed in a private terminal.
