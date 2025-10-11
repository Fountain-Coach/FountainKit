#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)

# Gather OpenAPI documents (supports *.yaml / *.yml naming).
OPENAPI_SPECS=()
while IFS= read -r spec; do
  OPENAPI_SPECS+=("$spec")
done < <(
  find "$ROOT" \
    \( -path "$ROOT/.build" -o -path "$ROOT/.swiftpm" -o -path '*/.build' -o -path '*/.swiftpm' \) -prune -o \
    -name 'openapi.yaml' -print -o \
    -name 'openapi.yml' -print -o \
    -name '*.openapi.yaml' -print -o \
    -name '*.openapi.yml' -print
)

if [[ ${#OPENAPI_SPECS[@]} -eq 0 ]]; then
  echo "[openapi-lint] No OpenAPI documents found; skipping."
  exit 0
fi

echo "[openapi-lint] Found ${#OPENAPI_SPECS[@]} OpenAPI document(s)."

if [[ -n "${OPENAPI_LINT_CLI:-}" ]]; then
  echo "[openapi-lint] Using custom linter: ${OPENAPI_LINT_CLI}"
  exec ${OPENAPI_LINT_CLI} "${OPENAPI_SPECS[@]}"
fi

if ! command -v npx >/dev/null 2>&1; then
  echo "[openapi-lint] npx not available. Install Node.js or set OPENAPI_LINT_CLI."
  exit 1
fi

echo "[openapi-lint] Running Redocly CLI (@redocly/cli@1)."
npx --yes @redocly/cli@1 lint "${OPENAPI_SPECS[@]}"
