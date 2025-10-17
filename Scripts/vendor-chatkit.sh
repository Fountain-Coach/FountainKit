#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT/Public/vendor/chatkit"
SRC_DIR="$ROOT/Workspace/deps/chatkit-js"

mkdir -p "$VENDOR_DIR"

echo "[vendor] Preparing ChatKit vendor bundle..."

if [[ -d "$SRC_DIR" ]]; then
  # If upstream provides a dist/umd build in the repo, copy it; otherwise keep stub.
  CANDIDATES=(
    "$SRC_DIR/packages/*/dist/chatkit.umd.js"
    "$SRC_DIR/packages/*/dist/*.umd.js"
  )
  FOUND=""
  for pattern in "${CANDIDATES[@]}"; do
    for f in $pattern; do
      if [[ -f "$f" ]]; then FOUND="$f"; break; fi
    done
    [[ -n "$FOUND" ]] && break
  done

  if [[ -n "$FOUND" ]]; then
    cp -f "$FOUND" "$VENDOR_DIR/chatkit.umd.js"
    echo "[vendor] Copied upstream bundle: $FOUND"
  else
    echo "[vendor] No upstream UMD bundle found; leaving stub in place."
  fi
else
  echo "[vendor] Upstream repo not present at $SRC_DIR; leaving stub in place."
fi

if [[ -f "$VENDOR_DIR/chatkit.umd.js" ]]; then
  shasum -a 256 "$VENDOR_DIR/chatkit.umd.js" | awk '{print $1}' > "$VENDOR_DIR/chatkit.umd.js.sha256"
  echo "[vendor] Wrote checksum to chatkit.umd.js.sha256"
fi

echo "[vendor] Done."

