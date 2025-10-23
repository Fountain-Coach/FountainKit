#!/usr/bin/env bash
set -euo pipefail

# Convert an SVG to PNG with common tools available on macOS/Linux.
# Usage: Scripts/svg-to-png.sh <input.svg> [width_px] [height_px]

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <input.svg> [width_px] [height_px]" >&2
  exit 2
fi

IN="$1"
WIDTH="${2:-2480}"
HEIGHT="${3:-3508}"
if [[ ! -f "$IN" ]]; then
  echo "[error] Not found: $IN" >&2
  exit 1
fi

DIR="$(cd "$(dirname "$IN")" && pwd)"
BASE="$(basename "$IN" .svg)"
OUT="$DIR/$BASE.png"

try_qlmanage() {
  # macOS QuickLook generator
  command -v qlmanage >/dev/null 2>&1 || return 1
  local tmp
  tmp="$(mktemp -d)"
  # qlmanage outputs a PNG thumbnail when -t is used; -s controls longest side
  local max_side
  max_side=$(( WIDTH > HEIGHT ? WIDTH : HEIGHT ))
  qlmanage -t -s "$max_side" -o "$tmp" "$IN" >/dev/null 2>&1 || return 1
  local gen
  gen="$(ls -1 "$tmp"/*.png 2>/dev/null | head -n1 || true)"
  [[ -n "$gen" ]] || return 1
  mv "$gen" "$OUT"
  rm -rf "$tmp"
  return 0
}

try_inkscape() {
  command -v inkscape >/dev/null 2>&1 || return 1
  inkscape "$IN" --export-type=png --export-filename="$OUT" -w "$WIDTH" -h "$HEIGHT" >/dev/null 2>&1
}

try_rsvg() {
  command -v rsvg-convert >/dev/null 2>&1 || return 1
  rsvg-convert -w "$WIDTH" -h "$HEIGHT" "$IN" -o "$OUT" >/dev/null 2>&1
}

try_convert() {
  command -v convert >/dev/null 2>&1 || return 1
  # Use density to get reasonable resolution
  convert -density 300 "$IN" -resize ${WIDTH}x${HEIGHT} "$OUT" >/dev/null 2>&1
}

if try_qlmanage || try_inkscape || try_rsvg || try_convert; then
  echo "Wrote $OUT"
  exit 0
fi

echo "[error] Could not find a supported converter (qlmanage, inkscape, rsvg-convert, convert)." >&2
exit 1

