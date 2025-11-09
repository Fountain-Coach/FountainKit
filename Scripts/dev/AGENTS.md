# AGENT — Scripts/dev (workspace lifecycle)

Scope: `Scripts/dev/**`.

What/Why
Manage the local Fountain stack: start/stop/status, prebuild helpers, and one‑time Keychain seeding. Scripts are idempotent, safe to re‑run, include a `Usage:` section, and avoid interactive prompts.

Included tools
- `dev-up` — Starts core services (add `--all` for extras); readiness checks with `--check`.
- `dev-down` — Stops background services; `--force` also kills listeners on dev ports.
- `dev-status` — Shows ports, up/down state, and known PIDs.
- `dev-servers-up.sh` — Prebuilds then starts with checks (one‑shot convenience).
- `editor-min` — Minimal, targeted build/run for the editor server (no smoke).
- `gateway-min` — Minimal, targeted build/run for Gateway.
- `pbvrt-min` — Minimal, targeted build/run for PBVRT.
- `planner-min` — Minimal, targeted build/run for Planner.
- `function-caller-min` — Minimal, targeted build/run for Function‑Caller.
- `persist-min` — Minimal, targeted build/run for Persist.
- `baseline-awareness-min` — Minimal, targeted build/run for Awareness.
- `bootstrap-min` — Minimal, targeted build/run for Bootstrap.
- `tools-factory-min` — Minimal, targeted build/run for Tools‑Factory.
- `tool-server-min` — Minimal, targeted build/run for Tool‑Server.
- `seed-secrets-keychain.sh` — Seeds `GATEWAY_BEARER` and `OPENAI_API_KEY` into macOS Keychain.
- `codex-danger` — Sentinel‑gated Codex launcher. Safe by default; danger mode (`-s danger-full-access -a never`) activates only when a sentinel is present, `FK_CODEX_DANGER=1`, or `--danger` is passed. Reuses `gh auth token` at runtime (no secrets committed).
- `install-codex` — One‑time installer that writes a `Codex` launcher into `~/.local/bin` (or given `--bin-dir`) so you can run `Codex` from anywhere.

Tips
- Use `Codex --relogin` to force a fresh GitHub session (the wrapper logs out and then runs `gh auth login --web`).

Danger activation (opt‑in)
- Create `.codex-allow-danger` at repo root (git‑ignored), or set `FK_CODEX_DANGER=1`, or pass `--danger` once.
- Force safe mode regardless of sentinel: `--safe`.

Quick usage
- Safe (default): `codex` or `Scripts/dev/codex-danger` → `/status` shows workspace‑write + approvals on‑failure.
- Danger (opt‑in): add sentinel, then `codex` or `Scripts/dev/codex-danger` → `/status` shows danger‑full‑access + approvals never.

Conventions
- No `.env` in repo; secrets come from Keychain. Always set `LAUNCHER_SIGNATURE` (default provided).
- Logs under `.fountain/logs/*.log`; PIDs under `.fountain/pids/*.pid` at repo root.
- Defensive shell (`set -euo pipefail`) and deterministic behaviour across re‑runs.

Baseline default
- Dev‑up launches the Baseline‑PatchBay UI by default (product `baseline-patchbay`). Any change to this baseline app must be paired with a matching MRTS Teatro prompt. On boot, the baseline prints both prompts (creation + MRTS). Persist the MRTS via `baseline-robot-seed`; run the invariants with `Scripts/ci/baseline-robot.sh`.

Targeted builds (editor‑minimal)
Use `Scripts/dev/editor-min` to focus builds on the editor service only. The wrapper exports `FK_EDITOR_MINIMAL=1`, `FK_SKIP_NOISY_TARGETS=1`, and `FOUNTAIN_SKIP_LAUNCHER_SIG=1`, then:
- `build` compiles only `fountain-editor-service-server`.
- `run` launches the server in debug.

Note: There is no `smoke` subcommand — server mains are real HTTP servers; in‑process smoke codepaths are prohibited to avoid hangs.

Targeted builds (gateway/pbvrt)
- `Scripts/dev/gateway-min` exports `FK_MIN_TARGET=gateway`, `FK_SKIP_NOISY_TARGETS=1`, `FOUNTAIN_SKIP_LAUNCHER_SIG=1` and builds/runs only `gateway-server`.
- `Scripts/dev/pbvrt-min` exports `FK_MIN_TARGET=pbvrt`, `FK_SKIP_NOISY_TARGETS=1`, `FOUNTAIN_SKIP_LAUNCHER_SIG=1` and builds/runs only `pbvrt-server`.

Wrappers index (service‑minimal)
- editor: `Scripts/dev/editor-min`
- gateway: `Scripts/dev/gateway-min`
- pbvrt: `Scripts/dev/pbvrt-min`
- quietframe: `Scripts/dev/quietframe-min`
- planner: `Scripts/dev/planner-min`
- function-caller: `Scripts/dev/function-caller-min`
- persist: `Scripts/dev/persist-min`
- baseline-awareness: `Scripts/dev/baseline-awareness-min`
- bootstrap: `Scripts/dev/bootstrap-min`
- tools-factory: `Scripts/dev/tools-factory-min`
- tool-server: `Scripts/dev/tool-server-min`

Pattern
- Core owns OpenAPI generation (`<service>-service` library target) with filters; server depends on core and never declares the generator plugin.
- Manifest remains stable; wrappers set env to narrow build scope. No in‑app smoke or test codepaths in servers.
