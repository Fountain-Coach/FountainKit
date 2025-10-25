#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat << 'EOF'
Usage: Scripts/design/qc-render.sh [--kit Design/QC_Prompt_Kit] [--out qc_preview.svg]

Renders a QC Prompt Kit JSON to an SVG preview with a numbered grid/axes,
nodes, ports, and qcBezier edges. Intended for coordinate authoring.

Options:
  --kit   Path to kit directory (default: Design/QC_Prompt_Kit)
  --out   Output SVG (default: <kit>/qc_preview.svg)
EOF
}

KIT="Design/QC_Prompt_Kit"
OUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --kit) KIT="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

JSON="$KIT/qc_prompt.json"
if [[ -z "$OUT" ]]; then OUT="$KIT/qc_preview.svg"; fi
if [[ ! -f "$JSON" ]]; then echo "Missing $JSON" >&2; exit 1; fi
python3 Scripts/design/qcrender.py --json "$JSON" --out "$OUT"
echo "Rendered $OUT"

