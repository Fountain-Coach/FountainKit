#!/usr/bin/env bash
set -euo pipefail

echo "[studio-up] Engraver Studio • Ollama (local)"

# 1) Ensure Homebrew + Ollama
if ! command -v brew >/dev/null 2>&1; then
  echo "[studio-up] Homebrew is required. Install from https://brew.sh and rerun." >&2
  exit 1
fi

if ! command -v ollama >/dev/null 2>&1; then
  echo "[studio-up] Installing Ollama via Homebrew…"
  brew install ollama
fi

echo "[studio-up] Starting Ollama service…"
brew services start ollama >/dev/null 2>&1 || true

# 2) Wait for Ollama API
echo -n "[studio-up] Waiting for Ollama API "
for i in $(seq 1 30); do
  if curl -sf -m 1 http://127.0.0.1:11434/api/tags >/dev/null; then
    echo "ok"; break
  fi
  echo -n "."; sleep 1
  if [[ $i -eq 30 ]]; then echo " fail"; echo "[studio-up] Ollama API did not come up." >&2; exit 1; fi
done

# 3) Ensure a small instruct model is present
MODEL_TAG=""
echo "[studio-up] Selecting a small instruct model…"
if curl -s http://127.0.0.1:11434/api/tags | grep -q 'llama3.2:3b-instruct'; then
  MODEL_TAG="llama3.2:3b-instruct"
fi
if [[ -z "$MODEL_TAG" ]]; then
  CANDIDATES=(
    "phi3:mini" 
    "llama3.2:1b-instruct"
    "llama3.2:3b-instruct"
    "gemma2:2b-instruct"
    "mistral:7b-instruct"
  )
  for tag in "${CANDIDATES[@]}"; do
    echo "[studio-up] Pulling \"$tag\"…"
    if ollama pull "$tag"; then
      MODEL_TAG="$tag"; break
    else
      echo "[studio-up] Pull failed for $tag; trying next…" >&2
    fi
  done
fi
if [[ -z "$MODEL_TAG" ]]; then
  echo "[studio-up] Could not pull any small instruct model (phi3/llama3.2/gemma2/mistral). Check your network and retry." >&2
  exit 1
fi

# 4) Run Engraver Studio in direct-local mode (no gateway, no local-agent)
export ENGRAVER_PROVIDER=local
export ENGRAVER_BYPASS_GATEWAY=1
export LAUNCHER_DISABLE_LOCAL_AGENT=1
export DEV_UP_NO_START_LOCAL_AGENT=1
export ENGRAVER_LOCAL_LLM_URL="http://127.0.0.1:11434/v1/chat/completions"
export ENGRAVER_MODELS="$MODEL_TAG"
export ENGRAVER_DEFAULT_MODEL="$MODEL_TAG"

echo "[studio-up] Launching Engraver Studio (model=$MODEL_TAG)…"
exec swift run --package-path Packages/FountainApps engraver-studio-app
