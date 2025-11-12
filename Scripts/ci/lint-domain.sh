#!/usr/bin/env bash
set -euo pipefail
echo "[lint-domain] verifying no 'fountain.ai' remains in repo"
if rg -n "fountain\\.ai" --hidden --glob '!**/.git/**' --glob '!**/.build/**' --glob '!**/.fountain/**' --glob '!**/External/**' ; then
  echo "[lint-domain] ERROR: found occurrences of fountain.ai above" >&2
  exit 1
else
  echo "[lint-domain] OK: no fountain.ai occurrences found"
fi

