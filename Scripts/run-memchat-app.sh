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

# Resolve OpenAI API key from Keychain only
OPENAI_KEY="$(security find-generic-password -s FountainAI -a OPENAI_API_KEY -w 2>/dev/null || true)"
if [[ -z "${OPENAI_KEY}" ]]; then
  echo "[run-memchat] ERROR: No OPENAI_API_KEY found in Keychain (service=FountainAI, account=OPENAI_API_KEY)."
  echo "Set it in Keychain and re-run."
  exit 1
fi

echo "› Running memchat-app (store: ${STORE_DIR})"
LAUNCHER_SIGNATURE="${SIG}" FOUNTAINSTORE_DIR="${STORE_DIR}" \
swift run --package-path Packages/FountainApps memchat-app
