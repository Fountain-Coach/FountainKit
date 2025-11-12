#!/usr/bin/env bash
set -euo pipefail
echo "[lint-coremidi] verifying CoreMIDI is not referenced"
if rg -n "\\bimport\\s+CoreMIDI\\b|\\bMIDI(Client|Source|Destination|Port|Send|Received)" \
  --hidden --glob '!**/.git/**' --glob '!**/.build/**' --glob '!**/.fountain/**' --glob '!**/External/**' ; then
  echo "[lint-coremidi] ERROR: CoreMIDI references found above" >&2
  exit 1
else
  echo "[lint-coremidi] OK: no CoreMIDI references found"
fi

