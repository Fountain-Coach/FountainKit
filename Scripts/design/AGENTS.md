# AGENT — Scripts/design (GUI and engraving assets)

Scope: `Scripts/design/**` and related assets in `Design/**`.

Purpose
- House scripts that generate, convert, or preview design artifacts
  (SVG wireframes, PNG exports, LilyPond engraving, PDFs).
- Keep design tooling separate from dev/CI lifecycle scripts.

Conventions
- Inputs live in `Design/**` and are the source of truth.
- Outputs are written next to inputs (same basename, different extension).
- Scripts are idempotent and safe to run repeatedly.
- Prefer plain Bash with `set -euo pipefail`.

Included tools
- `render-staff-paper.sh` — Render `Design/staff-paper.ly` to PDF/SVG via LilyPond.
- `svg-to-png.sh` — Convert any SVG to PNG using one of: `qlmanage` (macOS), `inkscape`,
  `rsvg-convert`, or ImageMagick `convert`.
- `qc-lint.sh` — Lint QC Prompt Kit (DSL header parity, JSON schema, SVG presence).

Usage
- Render staff paper: `bash Scripts/design/render-staff-paper.sh`
- Convert SVG to PNG: `bash Scripts/design/svg-to-png.sh Design/file.svg 2480 3508`
- Lint QC Prompt Kit: `bash Scripts/design/qc-lint.sh --kit Design/QC_Prompt_Kit`

Maintenance
- Add new design scripts here; keep names descriptive.
- If a script must be called from CI, add a wrapper in `Scripts/` that forwards
  to the canonical path under `Scripts/design/` to avoid breaking existing jobs.
