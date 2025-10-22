#!/usr/bin/env bash
set -euo pipefail

# Seeds secrets into the macOS Keychain with "Allow all applications" access,
# avoiding repeated authorization prompts across dev tools.
#
# Usage examples:
#   Scripts/seed-secrets-keychain.sh --gateway-bearer "$TOKEN" --openai-key "$OPENAI"
#   OPENAI_API_KEY=sk-... Scripts/seed-secrets-keychain.sh
#   Scripts/seed-secrets-keychain.sh --interactive
#
# Items are stored under service "FountainAI" with accounts:
#   - GATEWAY_BEARER
#   - OPENAI_API_KEY

SERVICE="FountainAI"
GATEWAY_BEARER="${GATEWAY_BEARER:-}"
OPENAI_API_KEY="${OPENAI_API_KEY:-}"
INTERACTIVE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --service) SERVICE="$2"; shift 2 ;;
    --gateway-bearer) GATEWAY_BEARER="$2"; shift 2 ;;
    --openai-key) OPENAI_API_KEY="$2"; shift 2 ;;
    --interactive) INTERACTIVE=1; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ "$INTERACTIVE" == "1" ]]; then
  if [[ -z "$GATEWAY_BEARER" ]]; then
    read -r -s -p "GATEWAY_BEARER: " GATEWAY_BEARER; echo
  fi
  if [[ -z "$OPENAI_API_KEY" ]]; then
    read -r -s -p "OPENAI_API_KEY: " OPENAI_API_KEY; echo
  fi
fi

if ! command -v security >/dev/null 2>&1; then
  echo "security tool not found (macOS only)." >&2
  exit 1
fi

function put_item() {
  local account="$1"; local value="$2"
  if [[ -z "$value" ]]; then return 0; fi
  # -A: allow all applications, -U: update if exists
  security add-generic-password -a "$account" -s "$SERVICE" -w "$value" -A -U >/dev/null
  echo "Stored $account in Keychain (service=$SERVICE) with allow-all access."
}

put_item GATEWAY_BEARER "$GATEWAY_BEARER"
put_item OPENAI_API_KEY "$OPENAI_API_KEY"

echo "Done. You can now run the Studio without repeated prompts."

