#!/usr/bin/env bash
set -euo pipefail

CORPUS_ID="${1:-memchat-app}"

# Resolve store root (same logic as DiskFountainStoreClient)
if [[ -n "${FOUNTAINSTORE_DIR:-}" ]]; then
  ROOT="$FOUNTAINSTORE_DIR"
elif [[ -n "${ENGRAVER_STORE_PATH:-}" ]]; then
  ROOT="$ENGRAVER_STORE_PATH"
else
  ROOT="$HOME/.fountain/engraver-store"
fi

# Expand tilde if present
ROOT="${ROOT/#\~/$HOME}"

TARGET="$ROOT/$CORPUS_ID"
echo "Purging corpus at: $TARGET"
if [[ -d "$TARGET" ]]; then
  rm -rf "$TARGET"
  echo "Deleted $TARGET"
else
  echo "No existing corpus directory found."
fi

mkdir -p "$TARGET"
echo "Recreated empty corpus directory."

echo "Done."
