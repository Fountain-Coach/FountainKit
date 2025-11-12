#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PKG_PATH="$ROOT_DIR/Packages/FountainApps"

shopt -s nullglob
files=("$ROOT_DIR"/agents/*.yaml "$ROOT_DIR"/agents/*.yml "$ROOT_DIR"/agents/*.json)
if [[ ${#files[@]} -eq 0 ]]; then
  echo "[validate-agents] no agent descriptors found under agents/ — skipping"
  exit 0
fi

echo "[validate-agents] building validator…"
swift build --package-path "$PKG_PATH" -c debug --target agent-validate >/dev/null

echo "[validate-agents] validating ${#files[@]} file(s)…"
failed=0
for f in "${files[@]}"; do
  if ! swift run --package-path "$PKG_PATH" -c debug agent-validate "$f"; then
    echo "[validate-agents] ERROR: validation failed for $f" >&2
    failed=1
  fi
done

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi
echo "[validate-agents] ✅ all descriptors valid"

