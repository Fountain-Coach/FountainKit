#!/usr/bin/env bash
set -euo pipefail

# Simple curl-based smoke test for Gateway well-known endpoints.
# Usage:
#   Scripts/ci/gateway-well-known-smoke.sh
# Env:
#   GATEWAY_BASE_URL (default http://127.0.0.1:8010)
#   GATEWAY_ALLOW_MISSING_FACTS=1 to not fail when /.well-known/agent-facts is 404

BASE_URL=${GATEWAY_BASE_URL:-http://127.0.0.1:8010}
ALLOW_MISSING_FACTS=${GATEWAY_ALLOW_MISSING_FACTS:-0}

echo "[gateway-smoke] base=${BASE_URL}"

# Ready
code=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/ready" || true)
if [[ "$code" != "200" ]]; then
  echo "[gateway-smoke] ERROR: /ready returned ${code}" >&2
  exit 1
fi
echo "[gateway-smoke] /ready ok"

# Descriptor
desc=$(curl -fsS "${BASE_URL}/.well-known/agent-descriptor" || true)
if [[ -z "$desc" ]]; then
  echo "[gateway-smoke] ERROR: empty descriptor body" >&2
  exit 1
fi
if ! grep -q '"x-agent-id"' <<< "$desc" ; then
  echo "[gateway-smoke] ERROR: descriptor missing x-agent-id" >&2
  echo "$desc" >&2
  exit 1
fi
echo "[gateway-smoke] /.well-known/agent-descriptor ok"

# Facts (optional)
fact_code=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/.well-known/agent-facts" || true)
if [[ "$fact_code" == "200" ]]; then
  facts=$(curl -fsS "${BASE_URL}/.well-known/agent-facts" || true)
  if [[ -z "$facts" ]]; then
    echo "[gateway-smoke] ERROR: facts got 200 but empty body" >&2
    exit 1
  fi
  echo "[gateway-smoke] /.well-known/agent-facts ok"
else
  if [[ "$ALLOW_MISSING_FACTS" == "1" && "$fact_code" == "404" ]]; then
    echo "[gateway-smoke] /.well-known/agent-facts missing (allowed)"
  else
    echo "[gateway-smoke] ERROR: /.well-known/agent-facts returned ${fact_code}" >&2
    exit 1
  fi
fi

echo "[gateway-smoke] ✅ success"

