#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Resolve launcher signature from macOS Keychain (service=FountainAI, account=LAUNCHER_SIGNATURE)
# Fallback to embedded dev signature when not present.
SIG="$(security find-generic-password -s FountainAI -a LAUNCHER_SIGNATURE -w 2>/dev/null || true)"
if [[ -z "${SIG}" ]]; then
  SIG="B86D7CEE-24C4-4C4C-A107-8D0542D1965B"
fi

# Default store dir to repo-local .fountain/store unless overridden by env
STORE_DIR="${FOUNTAINSTORE_DIR:-${REPO_ROOT}/.fountain/store}"

echo "› Running memchat-app (store: ${STORE_DIR})"
LAUNCHER_SIGNATURE="${SIG}" FOUNTAINSTORE_DIR="${STORE_DIR}" \
swift run --package-path Packages/FountainApps memchat-app

