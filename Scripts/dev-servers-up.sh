#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") [--release] [--no-extras]

Description:
  Prebuild all Fountain servers, then start them with readiness checks.
  Defaults to debug configuration and includes extras (semantic-browser, tools-factory, tool-server, publishing-frontend).

Options:
  --release    Use release configuration (DEV_UP_CONFIGURATION=release)
  --no-extras  Do not build/start optional extras (core services only)
USAGE
}

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec "$REPO_ROOT/Scripts/dev/dev-servers-up.sh" "$@"
