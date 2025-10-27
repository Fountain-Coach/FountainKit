#!/usr/bin/env bash
set -euo pipefail
# Check that InstrumentKind enums match across curated, service, and app specs.

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CURATED="$ROOT_DIR/Packages/FountainSpecCuration/openapi/v1/patchbay.yml"
SERVICE="$ROOT_DIR/Packages/FountainApps/Sources/patchbay-service/openapi.yaml"
APP="$ROOT_DIR/Packages/FountainApps/Sources/patchbay-app/openapi.yaml"

extract_kinds() (
  local file="$1"
  # Grab the enum list that appears within ~15 lines after 'InstrumentKind:'
  local start line enum
  start=$(rg -n "^\s*InstrumentKind:\s*$" "$file" | cut -d: -f1 | head -n1)
  if [[ -z "$start" ]]; then
    echo ""; return 0
  fi
  line=$(sed -n "${start},$((start+20))p" "$file" | rg -n "^\s*enum:\s*\[(.*)\]" -r '$1' -N | head -n1)
  if [[ -z "$line" ]]; then
    # Fallback for block style (one per line)
    # Collect lines starting with '-' under an 'enum:' line
    line=$(sed -n "${start},$((start+40))p" "$file" | awk '/^\s*enum:\s*$/{flag=1; next} /^\s*[A-Za-z]/ && flag==1 {exit} flag==1 && /^\s*-/{gsub("^-\\s*","",$0); printf "%s,", $0} END{}')
  fi
  # Normalize: split by comma/space and sort unique
  echo "$line" | tr -d '"' | tr ',' '\n' | sed 's/^\s*//; s/\s*$//' | rg -v '^$' | sort -u
)

cur=$(extract_kinds "$CURATED")
svc=$(extract_kinds "$SERVICE")
app=$(extract_kinds "$APP")

tmpd=$(mktemp -d)
trap 'rm -rf "$tmpd"' EXIT
printf "%s\n" "$cur" > "$tmpd/cur.txt"
printf "%s\n" "$svc" > "$tmpd/svc.txt"
printf "%s\n" "$app" > "$tmpd/app.txt"

echo "Curated InstrumentKind:" && cat "$tmpd/cur.txt" && echo
echo "Service InstrumentKind:" && cat "$tmpd/svc.txt" && echo
echo "App InstrumentKind:" && cat "$tmpd/app.txt" && echo

diff -u "$tmpd/cur.txt" "$tmpd/svc.txt" || { echo "ERROR: Curated vs Service InstrumentKind mismatch"; exit 2; }
diff -u "$tmpd/cur.txt" "$tmpd/app.txt" || { echo "ERROR: Curated vs App InstrumentKind mismatch"; exit 3; }
echo "OK: InstrumentKind enums are in sync."

