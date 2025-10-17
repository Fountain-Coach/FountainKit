#!/usr/bin/env bash
set -euo pipefail

# Downloads Hermes 2 Pro Mistral 7B GGUF (Q4_K_M by default) into the LocalAgent Models directory.

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")"/../.. && pwd)
MODELS_DIR="$REPO_ROOT/External/LocalAgent/AgentService/Models"
mkdir -p "$MODELS_DIR"

MODEL_NAME=${MODEL_NAME:-Hermes-2-Pro-Mistral-7B.Q4_K_M.gguf}
HF_REPO=${HF_REPO:-https://huggingface.co/NousResearch/Hermes-2-Pro-Mistral-7B-GGUF}
URL="$HF_REPO/resolve/main/$MODEL_NAME?download=true"
DEST="$MODELS_DIR/$MODEL_NAME"

echo "[fetch-hermes] Downloading $MODEL_NAME → $DEST"
echo "[fetch-hermes] From: $URL"

curl -L --retry 4 --retry-delay 2 -C - -# -o "$DEST" "$URL"

echo "[fetch-hermes] Done: $DEST"
echo "[fetch-hermes] Set AgentService/agent-config.json modelPath to: AgentService/Models/$MODEL_NAME"
