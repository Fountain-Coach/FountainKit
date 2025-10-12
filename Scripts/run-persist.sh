#!/bin/bash
set -euo pipefail

export LAUNCHER_SIGNATURE=${LAUNCHER_SIGNATURE:-B86D7CEE-24C4-4C4C-A107-8D0542D1965B}
exec swift run --package-path Packages/FountainApps persist-server "$@"
