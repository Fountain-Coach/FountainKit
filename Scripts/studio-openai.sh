#!/usr/bin/env bash
set -euo pipefail

echo "[studio-up] Engraver Studio • OpenAI (direct via SecretStore)"
echo "[studio-up] Tip: Studio reads OPENAI_API_KEY from macOS Keychain (service=FountainAI, account=OPENAI_API_KEY)."

export ENGRAVER_PROVIDER=openai
export ENGRAVER_BYPASS_GATEWAY=1
export LAUNCHER_DISABLE_LOCAL_AGENT=1
export DEV_UP_NO_START_LOCAL_AGENT=1

echo "[studio-up] Launching Engraver Studio (provider=openai)…"
exec swift run --package-path Packages/FountainApps engraver-studio-app
