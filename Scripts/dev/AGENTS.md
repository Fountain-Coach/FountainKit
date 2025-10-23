# AGENT — Scripts/dev (workspace lifecycle)

Scope: `Scripts/dev/**`.

Purpose
- Start/stop/status for local Fountain stack; prebuild helpers; keychain seeding.

Included tools
- `dev-up` — Start core services (and extras with `--all`), optional readiness checks (`--check`).
- `dev-down` — Stop background services; `--force` also kills listeners on dev ports.
- `dev-status` — Show ports, up/down, and known PIDs.
- `dev-servers-up.sh` — Prebuild then start with checks (one command convenience).
- `seed-secrets-keychain.sh` — Seed `GATEWAY_BEARER` and `OPENAI_API_KEY` into macOS Keychain.

Conventions
- Logs: `.fountain/logs/*.log`; PIDs: `.fountain/pids/*.pid` at repo root.
- `LAUNCHER_SIGNATURE` is always set (defaults to embedded value); do not prompt for secrets when avoidable.

