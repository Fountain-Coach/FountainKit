# AGENT — Scripts (lifecycle and tooling)

The `Scripts/**` tree holds our day‑to‑day tooling: lifecycle scripts that start and stop the control plane, smoke tests used by CI, registration helpers, and design utilities. Treat these as part of the product — they should be safe to run repeatedly, explain themselves with a short `Usage:` section, and never rely on a checked‑in `.env`.

How we write scripts
Scripts are idempotent and defensive. Before starting servers, we check ports and stale PIDs; when we need a launcher signature, we read it from the Keychain (and fall back to a sane default). Keep to POSIX sh when possible, or bash with `set -euo pipefail`. Tests belong next to the scripts they exercise under `Scripts/tests/**` and are used by CI to bring up the stack and probe readiness/routes.

Where things live
Design and engraving helpers sit in `Scripts/design/` (the source of truth remains `Design/`). Local hooks live in `Scripts/git-hooks/`. Ad‑hoc bash smoke tests live in `Scripts/tests/`. App‑adjacent helpers (e.g., Core ML model fetch/convert) live under `Scripts/apps/`.

Migration
New scripts should land in the right subdirectory from day one. When legacy paths are still referenced by external tools or CI, keep a thin wrapper in `Scripts/` that delegates to the canonical location.

Core ML helpers (apps)
The converter wrapper `Scripts/apps/coreml-convert.sh` bootstraps `.coremlvenv` and runs a Python entry (`Scripts/apps/coreml_convert.py`) to produce `.mlmodel` files. Examples: `… crepe --saved-model <dir> [--frame 1024]`, `… basicpitch --saved-model <dir>`, `… keras --h5 <file.h5>`, `… tflite --tflite <file.tflite>`. Models default to `Public/Models/` and are git‑ignored.

Curated OpenAPI
Keep the curated spec list in sync with the repo using `Scripts/validate-curated-specs.sh`. Install pre‑commit hooks once via `Scripts/install-git-hooks.sh` to enforce checks locally.

Register external OpenAPI as tools
- Script: `Scripts/openapi/register-teatro-guide-as-tools.sh` normalizes the Teatro Prompt Field Guide OpenAPI and registers its operations via ToolsFactory.
- Dev‑up integration: set `REGISTER_TEATRO_GUIDE=1` to auto‑register on boot when ToolsFactory is reachable. Optional envs:
  - `TOOLS_FACTORY_URL` (default `http://127.0.0.1:8011`)
  - `TEATRO_GUIDE_CORPUS` (default `teatro-guide`)
  - `TEATRO_GUIDE_BASE_URL` used to resolve absolute `http_path` if the spec lacks `servers[0].url`.

CI smoke for Prompt Field Guide
- Script: `Scripts/ci/teatro-guide-smoke.sh` registers the guide tools (idempotent), picks one function, invokes it via FunctionCaller, and writes an ETag under `.fountain/artifacts/`.
- Inputs: `TOOLS_FACTORY_URL`, `FUNCTION_CALLER_URL`, `TEATRO_GUIDE_CORPUS`, `TEATRO_GUIDE_SPEC`, `TEATRO_GUIDE_BASE_URL` (all optional; have sensible defaults).
