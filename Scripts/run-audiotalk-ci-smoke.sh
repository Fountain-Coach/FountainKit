#!/bin/bash
set -euo pipefail

export LAUNCHER_SIGNATURE=${LAUNCHER_SIGNATURE:-B86D7CEE-24C4-4C4C-A107-8D0542D1965B}
export AUDIOTALK_BASE_URL=${AUDIOTALK_BASE_URL:-http://127.0.0.1:8080}

swift run --package-path Packages/FountainApps audiotalk-ci-smoke "$@"

