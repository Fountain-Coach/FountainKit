#!/usr/bin/env bash
set -euo pipefail

# Default to LLM responder and allow model override.
export CHATKIT_RESPONDER="${CHATKIT_RESPONDER:-llm}"
export CHATKIT_DEFAULT_MODEL="${CHATKIT_DEFAULT_MODEL:-gpt-4o-mini}"

"$(dirname "$0")/run-dev.sh"

