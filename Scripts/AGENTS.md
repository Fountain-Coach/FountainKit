# AGENT — Scripts (lifecycle and tooling)

The `Scripts/**` tree is first‑class product code: lifecycle helpers for the control plane, CI smoke tests, OpenAPI utilities, and app‑adjacent tools. Scripts are safe to re‑run, explain themselves via a short `Usage:` section, and never depend on a checked‑in `.env` — secrets come from the Keychain with sensible defaults.

How we write scripts
Scripts are idempotent and defensive. We check ports and stale PIDs before starting servers, and always set `LAUNCHER_SIGNATURE` (reading from Keychain with a default). Prefer POSIX sh or bash with `set -euo pipefail`. Tests live next to the scripts under `Scripts/tests/**` and drive CI readiness/route probes.

Where things live
Canonical subdirectories: `Scripts/design/` (source of truth is `Design/`), `Scripts/openapi/` (lint/curated‑list), `Scripts/ci/` (smoke), `Scripts/dev/` (workspace lifecycle), and `Scripts/apps/` (app launchers and helpers). Keep local hooks in `Scripts/git-hooks/`.

Migration
New scripts must land in the correct subdirectory. If legacy paths are referenced by external tools or CI, keep a thin wrapper at `Scripts/` that delegates to the canonical path.

Core ML helpers (apps)
`Scripts/apps/coreml-convert.sh` bootstraps `.coremlvenv` and calls `Scripts/apps/coreml_convert.py` to produce `.mlmodel` files. Examples: `… crepe --saved-model <dir> [--frame 1024]`, `… basicpitch --saved-model <dir>`, `… keras --h5 <file.h5>`, `… tflite --tflite <file.tflite>`. Outputs default to `Public/Models/` (git‑ignored).

Curated OpenAPI
Use `Scripts/openapi/validate-curated-specs.sh` to keep `Configuration/curated-openapi-specs.json` in sync. Install local hooks once via `Scripts/install-git-hooks.sh`.

Register external OpenAPI as tools
- `Scripts/openapi/register-teatro-guide-as-tools.sh` normalizes the Teatro Prompt Field Guide OpenAPI and registers its operations via ToolsFactory. Dev‑up integration: set `REGISTER_TEATRO_GUIDE=1` to auto‑register on boot when ToolsFactory is reachable. Envs: `TOOLS_FACTORY_URL` (default `http://127.0.0.1:8011`), `TEATRO_GUIDE_CORPUS` (default `teatro-guide`), `TEATRO_GUIDE_BASE_URL` (resolves absolute `http_path` when the spec lacks `servers[0].url`).

CI smoke for Prompt Field Guide
- `Scripts/ci/teatro-guide-smoke.sh` registers tools (idempotent), invokes one via FunctionCaller, and writes an ETag under `.fountain/artifacts/`. Inputs: `TOOLS_FACTORY_URL`, `FUNCTION_CALLER_URL`, `TEATRO_GUIDE_CORPUS`, `TEATRO_GUIDE_SPEC`, `TEATRO_GUIDE_BASE_URL` (optional; sensible defaults).
