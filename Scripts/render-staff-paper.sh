#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LY_FILE="${ROOT_DIR}/Design/staff-paper.ly"
OUT_PREFIX="${ROOT_DIR}/Design/staff-paper"

if ! command -v lilypond >/dev/null 2>&1; then
  echo "[error] lilypond not found. Install LilyPond 2.24+ from https://lilypond.org/download.html" >&2
  exit 1
fi

echo "› Rendering PDF…"
lilypond -dno-point-and-click -o "${OUT_PREFIX}" "${LY_FILE}" >/dev/null

echo "› Rendering SVG…"
lilypond -dno-point-and-click -dbackend=svg -o "${OUT_PREFIX}" "${LY_FILE}" >/dev/null

echo "Done. Outputs:"
echo "  • ${OUT_PREFIX}.pdf"
echo "  • ${OUT_PREFIX}.svg"
if command -v open >/dev/null 2>&1; then
  open "${OUT_PREFIX}.pdf" || true
fi

