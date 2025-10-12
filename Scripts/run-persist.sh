#!/bin/bash
set -euo pipefail

export LAUNCHER_SIGNATURE=${LAUNCHER_SIGNATURE:-B86D7CEE-24C4-4C4C-A107-8D0542D1965B}
export FOUNTAINSTORE_PORT=${FOUNTAINSTORE_PORT:-8005}

echo "[persist] launching persist-server on port ${FOUNTAINSTORE_PORT} (signature ${LAUNCHER_SIGNATURE})"
echo "[persist] press Ctrl+C to stop. To change the port, export FOUNTAINSTORE_PORT before running."
exec swift run --package-path Packages/FountainApps persist-server "$@"
