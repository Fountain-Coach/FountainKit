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

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONFIG="${DEV_UP_CONFIGURATION:-debug}"
INCLUDE_EXTRAS=1
ALL_FLAG=()

for a in "$@"; do
  case "$a" in
    --help|-h) usage; exit 0 ;;
    --release) CONFIG=release ;;
    --no-extras) INCLUDE_EXTRAS=0 ;;
    *) echo "Unknown option: $a" >&2; usage; exit 1 ;;
  esac
done

export DEV_UP_CONFIGURATION="$CONFIG"
echo "[dev-servers-up] Using configuration: $DEV_UP_CONFIGURATION"

if [[ "$INCLUDE_EXTRAS" == "1" ]]; then ALL_FLAG=(--all); fi

echo "[dev-servers-up] Prebuilding server binaries…"
bash "$REPO_ROOT/Scripts/dev/dev-up" prebuild ${ALL_FLAG[@]:-}

echo "[dev-servers-up] Starting servers with checks…"
DEV_UP_USE_BIN=1 DEV_UP_CHECKS=1 bash "$REPO_ROOT/Scripts/dev/dev-up" ${ALL_FLAG[@]:-}

echo "[dev-servers-up] Done. Logs: $REPO_ROOT/.fountain/logs  |  PIDs: $REPO_ROOT/.fountain/pids"
echo "[dev-servers-up] Tip: tail -f $REPO_ROOT/.fountain/logs/gateway.log"

