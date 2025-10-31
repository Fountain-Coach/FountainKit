# AGENT — Scripts (lifecycle and tooling)

The `Scripts/**` tree is first‑class product code: lifecycle helpers for the control plane, CI smoke tests, OpenAPI utilities, and app‑adjacent tools. Scripts are idempotent, safe to re‑run, and explain themselves with a short `Usage:`; no checked‑in `.env` — secrets come from Keychain with sensible defaults.

Conventions
- Defensive by default: check ports and stale PIDs before starting servers; always set `LAUNCHER_SIGNATURE` (Keychain‑backed with a default).
- Shell: prefer POSIX sh or bash with `set -euo pipefail`.
- State: logs under `.fountain/logs`, PIDs under `.fountain/pids` at repo root.
- Tests: live under `Scripts/tests/**` to drive readiness/route probes.

Areas (canonical)
- `Scripts/design/` — GUI/engraving tooling (source of truth in `Design/`).
- `Scripts/openapi/` — spec lint and curated‑list validator.
- `Scripts/ci/` — workspace smoke and optional toolserver smoke.
- `Scripts/dev/` — workspace lifecycle (up/down/status/prebuild/keychain).
- `Scripts/audiotalk/` — AudioTalk stack runners and tool registration.
- `Scripts/apps/` — app launchers (composer, legacy studio, engraver, memchat).
- `Scripts/memchat/` — deprecated; runnable but not active product work.

Baseline policy
- `Scripts/apps/baseline-patchbay` launches the Baseline‑PatchBay UI. This baseline is authoritative for viewport/math invariants; any change to the baseline app must be paired with a matching MRTS Teatro prompt printed on boot and persisted via `baseline-robot-seed`. Run the invariants subset with `Scripts/ci/baseline-robot.sh`.

Migration
- New scripts must land under the correct subdirectory. If legacy root paths are referenced by external tools or CI, keep a thin wrapper at `Scripts/` that delegates to the canonical path. Do not add new functional scripts at the root.

Core ML helpers (apps)
`Scripts/apps/coreml-convert.sh` bootstraps `.coremlvenv` and calls `Scripts/apps/coreml_convert.py` to produce `.mlmodel` files. Examples: `… crepe --saved-model <dir> [--frame 1024]`, `… basicpitch --saved-model <dir>`, `… keras --h5 <file.h5>`, `… tflite --tflite <file.tflite>`. Outputs default to `Public/Models/` (git‑ignored).

Curated OpenAPI
Use `Scripts/openapi/validate-curated-specs.sh` to keep `Configuration/curated-openapi-specs.json` in sync. Install local hooks once via `Scripts/install-git-hooks.sh`.

Register external OpenAPI as tools
- `Scripts/openapi/register-teatro-guide-as-tools.sh` normalizes the Teatro Prompt Field Guide OpenAPI and registers its operations via ToolsFactory. Dev‑up integration: set `REGISTER_TEATRO_GUIDE=1` to auto‑register on boot when ToolsFactory is reachable. Envs: `TOOLS_FACTORY_URL` (default `http://127.0.0.1:8011`), `TEATRO_GUIDE_CORPUS` (default `teatro-guide`), `TEATRO_GUIDE_BASE_URL` (absolute `http_path` when the spec lacks `servers[0].url`).

CI smoke for Prompt Field Guide
- `Scripts/ci/teatro-guide-smoke.sh` registers tools (idempotent), invokes one via FunctionCaller, and writes an ETag under `.fountain/artifacts/`. Inputs: `TOOLS_FACTORY_URL`, `FUNCTION_CALLER_URL`, `TEATRO_GUIDE_CORPUS`, `TEATRO_GUIDE_SPEC`, `TEATRO_GUIDE_BASE_URL` (optional; sensible defaults).
