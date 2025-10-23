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

Migration plan
- New scripts should live in an appropriate subdirectory.
- Keep thin wrappers in `Scripts/` if external tools or CI refer to legacy paths.

Maintenance
- Keep usage/help up to date; prefer POSIX sh or bash with `set -euo pipefail`.

Curated OpenAPI validation
- Validator: `Scripts/validate-curated-specs.sh` ensures curated spec list stays in sync with repo paths.
- Pre‑commit: run `Scripts/install-git-hooks.sh` once to enforce locally.
