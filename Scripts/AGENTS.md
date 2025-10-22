# AGENT — Scripts (dev-up/down/status, smoke)

Scope: `Scripts/**` — lifecycle scripts, smoke tests, registration helpers.

Principles
- Idempotent and safe: port/PID cleanup before start; LAUNCHER_SIGNATURE from Keychain or default.
- Keychain‑only secrets policy; do not use `.env` in repo.

Testing
- Add bash smoke tests under `Scripts/tests/**` where feasible.
- CI smoke uses these scripts to bring up full stack and probe health/routes.

Maintenance
- Keep usage/help up to date; prefer POSIX sh or bash with `set -euo pipefail`.

