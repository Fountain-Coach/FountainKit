#!/usr/bin/env bash
set -euo pipefail

export CHATKIT_RESPONDER="${CHATKIT_RESPONDER:-llm}"
export CHATKIT_DEFAULT_MODEL="${CHATKIT_DEFAULT_MODEL:-gpt-4o-mini}"

"$(dirname "$0")/run-demo.sh"

