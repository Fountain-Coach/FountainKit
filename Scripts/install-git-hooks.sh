#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_DIR="${ROOT_DIR}/Scripts/git-hooks"

git config core.hooksPath "${HOOKS_DIR}"
echo "Installed git hooks path -> ${HOOKS_DIR}"

