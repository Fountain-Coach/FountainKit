# AGENT — Scripts/dev (workspace lifecycle)

Scope: `Scripts/dev/**`.

This area manages the local Fountain stack: start/stop/status, prebuild helpers, and one‑time Keychain seeding. The scripts are idempotent and safe to re‑run; they surface a clear `Usage:` and avoid interactive prompts.

Included tools
- `dev-up` — Starts core services (add `--all` for extras); readiness checks with `--check`.
- `dev-down` — Stops background services; `--force` also kills listeners on dev ports.
- `dev-status` — Shows ports, up/down state, and known PIDs.
- `dev-servers-up.sh` — Prebuilds then starts with checks (one‑shot convenience).
- `seed-secrets-keychain.sh` — Seeds `GATEWAY_BEARER` and `OPENAI_API_KEY` into macOS Keychain.

Conventions
- Logs under `.fountain/logs/*.log`; PIDs under `.fountain/pids/*.pid` at repo root.
- Always set `LAUNCHER_SIGNATURE` (defaults to an embedded value); prefer Keychain‑backed secrets and avoid prompting.
