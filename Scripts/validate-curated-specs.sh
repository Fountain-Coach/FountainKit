#!/usr/bin/env bash
set -euo pipefail

# Tiny validator for curated OpenAPI spec list.
# - Ensures every curated path exists (and symlink targets exist).
# - Ensures coverage of all server specs: Packages/FountainServiceKit-*/Sources/*Service/openapi.yaml
#   and Packages/FountainApps/Sources/gateway-server/openapi.yaml

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CURATED_JSON="${ROOT_DIR}/Configuration/curated-openapi-specs.json"

if [[ ! -f "${CURATED_JSON}" ]]; then
  echo "[ERROR] Missing curated spec list: ${CURATED_JSON}" >&2
  exit 2
fi

# Use Python for robust JSON parsing (available on CI runners and macOS devs).
PYTHON_BIN="python3"
if ! command -v "${PYTHON_BIN}" >/dev/null 2>&1; then
  echo "[ERROR] python3 not found; required to parse ${CURATED_JSON}" >&2
  exit 2
fi

CURATED_PATHS=()
while IFS= read -r line; do
  [[ -n "$line" ]] && CURATED_PATHS+=("$line")
done < <(CURATED_JSON_PATH="${CURATED_JSON}" "${PYTHON_BIN}" - <<'PY'
import json, os
with open(os.environ['CURATED_JSON_PATH'], 'r', encoding='utf-8') as f:
    data = json.load(f)
for item in data:
    print(os.path.normpath(item['path']))
PY
)

errors=()

note() { echo -e "\033[1;34m[validate]\033[0m $*"; }
warn() { echo -e "\033[33m[warn]\033[0m $*"; }
fail() { echo -e "\033[31m[error]\033[0m $*"; }

# 1) Validate each curated path exists and resolves if symlink
for rel in "${CURATED_PATHS[@]}"; do
  abs="${ROOT_DIR}/${rel}"
  if [[ ! -e "${abs}" ]]; then
    errors+=("Curated spec missing: ${rel}")
    continue
  fi
  if [[ -L "${abs}" ]]; then
    target="$(readlink "${abs}")"
    # If target is relative, resolve relative to directory of the symlink
    dir="$(cd "$(dirname "${abs}")" && pwd)"
    targ_abs="${target}"
    if [[ "${target}" != /* ]]; then
      targ_abs="${dir}/${target}"
    fi
    if [[ ! -e "${targ_abs}" ]]; then
      errors+=("Symlink target missing for ${rel} -> ${target}")
    fi
  fi
  # Also require generator config next to the openapi.yaml
  gen_cfg="$(dirname "${abs}")/openapi-generator-config.yaml"
  if [[ ! -f "${gen_cfg}" ]]; then
    errors+=("Missing openapi-generator-config.yaml next to ${rel}")
  fi
done

# 2) Ensure curated list covers all server specs (no scans at runtime; but verify coverage here)
DISCOVERED=()
while IFS= read -r line; do
  [[ -n "$line" ]] && DISCOVERED+=("$line")
done < <(cd "${ROOT_DIR}" && \
  find Packages \
    -path "Packages/FountainServiceKit-*/Sources/*Service/openapi.yaml" -o \
    -path "Packages/FountainApps/Sources/gateway-server/openapi.yaml" \
    -print | sort)

# Normalize for comparison using Python (macOS bash lacks some helpers)
normalize_path() {
  python3 - << 'PY' "$1"
import os, sys
print(os.path.normpath(sys.argv[1]))
PY
}

# Write curated normalized paths to a temp file for membership checks
tmp_curated="$(mktemp)"
trap 'rm -f "${tmp_curated}"' EXIT
for p in "${CURATED_PATHS[@]}"; do
  echo "$(normalize_path "$p")" >>"${tmp_curated}"
done

for d in "${DISCOVERED[@]}"; do
  rel="${d#${ROOT_DIR}/}"
  n="$(normalize_path "$rel")"
  if ! grep -Fxq -- "$n" "${tmp_curated}"; then
    errors+=("Unlisted server spec (should be curated): ${rel}")
  fi
done

if (( ${#errors[@]} > 0 )); then
  for e in "${errors[@]}"; do fail "$e"; done
  echo "\nValidation failed. Update ${CURATED_JSON} or fix paths/symlinks." >&2
  exit 1
fi

note "Curated OpenAPI specs OK (paths + coverage)"
