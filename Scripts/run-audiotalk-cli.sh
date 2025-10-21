#!/bin/bash
set -euo pipefail

# Provide the expected launcher signature unless supplied by the caller (kept for parity).
export LAUNCHER_SIGNATURE=${LAUNCHER_SIGNATURE:-B86D7CEE-24C4-4C4C-A107-8D0542D1965B}

# Optional base URL for convenience (CLI also supports --base-url).
export AUDIOTALK_BASE_URL=${AUDIOTALK_BASE_URL:-http://127.0.0.1:8080}

swift run --package-path Packages/FountainApps audiotalk-cli "$@"

