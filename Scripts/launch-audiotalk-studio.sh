#!/usr/bin/env bash
set -euo pipefail

# DEPRECATED: Legacy Control app launcher (FountainLauncherUI).
# This script is kept for compatibility but will not launch the legacy app by default.
# Use `Scripts/launch-composer-studio.sh` for the fresh Composer Studio.
#
# Usage (legacy only):
#   Scripts/launch-audiotalk-studio.sh [--autostart] [--use-keychain] [--force-legacy]

AUTOSTART=0
FORCE_LEGACY=0
USE_KEYCHAIN=1
for a in "$@"; do
  case "$a" in
    --autostart) AUTOSTART=1 ;;
    --use-keychain) USE_KEYCHAIN=1 ;;
    --no-keychain) USE_KEYCHAIN=0 ;;
    --force-legacy) FORCE_LEGACY=1 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export FOUNTAINKIT_ROOT="$REPO_ROOT"
if [[ "$USE_KEYCHAIN" != "1" ]]; then export FK_NO_KEYCHAIN=1; fi

# Enforce macOS Keychain secrets (no .env files). Seed once with allow-all access.
if [[ "$USE_KEYCHAIN" == "1" ]]; then
  ensure_kc() {
    local account="$1"
    local val
    if security find-generic-password -s FountainAI -a "$account" -w >/dev/null 2>&1; then
      return 0
    fi
    # Use env var if provided, otherwise prompt once.
    val="${!account:-}"
    if [[ -z "$val" ]]; then
      printf "%s" "Enter secret for $account: "
      stty -echo
      read -r val
      stty echo
      printf "\n"
    fi
    if [[ -n "$val" ]]; then
      security add-generic-password -a "$account" -s FountainAI -w "$val" -A -U >/dev/null
      echo "Stored $account in Keychain (Allow All)."
    fi
  }
  ensure_kc GATEWAY_BEARER
  ensure_kc OPENAI_API_KEY
  # Optional: seed LAUNCHER_SIGNATURE; fall back to embedded default if not set
  if ! security find-generic-password -s FountainAI -a LAUNCHER_SIGNATURE -w >/dev/null 2>&1; then
    DEFAULT_SIG="B86D7CEE-24C4-4C4C-A107-8D0542D1965B"
    security add-generic-password -a LAUNCHER_SIGNATURE -s FountainAI -w "$DEFAULT_SIG" -A -U >/dev/null || true
  fi
fi

# Always export a valid launcher signature for signed servers
export LAUNCHER_SIGNATURE="${LAUNCHER_SIGNATURE:-$(security find-generic-password -s FountainAI -a LAUNCHER_SIGNATURE -w 2>/dev/null || echo B86D7CEE-24C4-4C4C-A107-8D0542D1965B)}"
if [[ "$AUTOSTART" == "1" ]]; then
  export AUDIO_TALK_AUTOSTART=1
  export FOUNTAINSTORE_DIR="${FOUNTAINKIT_ROOT}/.fountain/store"
  export FUNCTION_CALLER_BASE_URL="http://127.0.0.1:8080/audiotalk/v1"
fi

if [[ "$FORCE_LEGACY" == "1" ]]; then
  echo "[legacy] Launching deprecated FountainLauncherUI (use --force-legacy again to suppress this notice)"
  swift run --package-path "$REPO_ROOT/Packages/FountainApps" FountainLauncherUI
else
  echo "[deprecated] The legacy Studio is deprecated. Use: Scripts/launch-composer-studio.sh"
  exit 1
fi
