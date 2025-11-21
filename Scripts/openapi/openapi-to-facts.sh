#!/usr/bin/env bash
set -euo pipefail

echo "[openapi-to-facts] DISABLED." >&2
echo "[openapi-to-facts] This batch script previously regenerated facts for every mapped spec." >&2
echo "[openapi-to-facts] That path is now forbidden for dev/interactive use." >&2
echo "[openapi-to-facts] Generate facts per agent instead, for example:" >&2
echo "  swift build --package-path Packages/FountainTooling -c debug --target openapi-to-facts" >&2
echo "  FOUNTAINSTORE_DIR=.fountain/store swift run --package-path Packages/FountainTooling -c debug openapi-to-facts Packages/FountainSpecCuration/openapi/v1/<spec>.yml --agent-id fountain.coach/agent/<name>/service --seed --allow-tools-only" >&2
exit 1
