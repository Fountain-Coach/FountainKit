# AGENT — Scripts/dev (workspace lifecycle)

Scope: `Scripts/dev/**`.

What/Why
Manage the local Fountain stack: start/stop/status, prebuild helpers, and one‑time Keychain seeding. Scripts are idempotent, safe to re‑run, include a `Usage:` section, and avoid interactive prompts.

Included tools
- `dev-up` — Starts core services (add `--all` for extras); readiness checks with `--check`.
- `dev-down` — Stops background services; `--force` also kills listeners on dev ports.
- `dev-status` — Shows ports, up/down state, and known PIDs.
- `dev-servers-up.sh` — Prebuilds then starts with checks (one‑shot convenience).
- `seed-secrets-keychain.sh` — Seeds `GATEWAY_BEARER` and `OPENAI_API_KEY` into macOS Keychain.
- `codex-danger` — Launches Codex with a non‑sandboxed, non‑interactive profile; pulls a GitHub token from `gh auth token` at runtime (no secrets committed).
- `install-codex` — One‑time installer that writes a `Codex` launcher into `~/.local/bin` (or given `--bin-dir`) so you can run `Codex` from anywhere.

Tips
- Use `Codex --relogin` to force a fresh GitHub session (the wrapper logs out and then runs `gh auth login --web`).

Conventions
- No `.env` in repo; secrets come from Keychain. Always set `LAUNCHER_SIGNATURE` (default provided).
- Logs under `.fountain/logs/*.log`; PIDs under `.fountain/pids/*.pid` at repo root.
- Defensive shell (`set -euo pipefail`) and deterministic behaviour across re‑runs.

Baseline default
- Dev‑up launches the Baseline‑PatchBay UI by default (product `baseline-patchbay`). Any change to this baseline app must be paired with a matching MRTS Teatro prompt. On boot, the baseline prints both prompts (creation + MRTS). Persist the MRTS via `baseline-robot-seed`; run the invariants with `Scripts/ci/baseline-robot.sh`.
