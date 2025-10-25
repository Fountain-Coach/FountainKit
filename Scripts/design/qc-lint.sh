#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat << 'EOF'
Usage: Scripts/design/qc-lint.sh [--kit Design/QC_Prompt_Kit]

Validates QC Prompt Kit files:
  - JSON schema and consistency
  - Optional DSL header parity (canvas/autolayout)
  - Optional SVG presence

Options:
  --kit   Path to a QC Prompt Kit directory (default: Design/QC_Prompt_Kit)

Examples:
  bash Scripts/design/qc-lint.sh --kit Design/QC_Prompt_Kit
EOF
}

KIT="Design/QC_Prompt_Kit"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --kit) KIT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

JSON="$KIT/qc_prompt.json"
DSL="$KIT/qc_prompt.dsl"
SVG="$KIT/qc_prompt.svg"

if [[ ! -f "$JSON" ]]; then echo "Missing $JSON" >&2; exit 1; fi
python3 Scripts/design/qclint.py --json "$JSON" --dsl "$DSL" --svg "$SVG"
echo "QC Prompt Kit lint OK: $KIT"

