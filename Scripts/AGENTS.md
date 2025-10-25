# AGENT — Scripts (lifecycle + tooling)

Scope: `Scripts/**` — lifecycle scripts, smoke tests, registration helpers, and design tooling.

Principles
- Idempotent and safe: port/PID cleanup before start; LAUNCHER_SIGNATURE from Keychain or default.
- Keychain‑only secrets policy; do not use `.env` in repo.

Testing
- Add bash smoke tests under `Scripts/tests/**` where feasible.
- CI smoke uses these scripts to bring up full stack and probe health/routes.

Subdirectories (ownership)
- `design/` — GUI/engraving assets tooling (SVG ↔ PNG, LilyPond rendering). Source of truth lives in `Design/`.
- `git-hooks/` — pre-commit and local hooks.
- `tests/` — ad‑hoc bash smoke tests used locally and referenced by CI.
- `apps/` — app launchers and app-adjacent helpers (e.g., Core ML model fetch/convert utilities).

Migration plan
- New scripts should live in an appropriate subdirectory.
- Keep thin wrappers in `Scripts/` if external tools or CI refer to legacy paths.

Maintenance
- Keep usage/help up to date; prefer POSIX sh or bash with `set -euo pipefail`.

Apps helpers (Core ML)
- `Scripts/apps/coreml-convert.sh`
  - Idempotent wrapper that bootstraps `.coremlvenv` and runs Python converter:
    - CREPE: `Scripts/apps/coreml-convert.sh crepe --saved-model <dir> [--frame 1024] [--out Public/Models/CREPE.mlmodel]`
    - BasicPitch: `Scripts/apps/coreml-convert.sh basicpitch --saved-model <dir> [--out Public/Models/BasicPitch.mlmodel]`
    - Keras: `Scripts/apps/coreml-convert.sh keras --h5 <file.h5> [--frame 1024] [--out <path>]`
    - TFLite: `Scripts/apps/coreml-convert.sh tflite --tflite <file.tflite> [--frame 1024] [--out <path>]`
  - Python entry lives at `Scripts/apps/coreml_convert.py` (uses coremltools; TF installed for SavedModel/Keras).
  - Models are written under `Public/Models/` by default and are git-ignored.

Curated OpenAPI validation
- Validator: `Scripts/validate-curated-specs.sh` ensures curated spec list stays in sync with repo paths.
- Pre‑commit: run `Scripts/install-git-hooks.sh` once to enforce locally.
