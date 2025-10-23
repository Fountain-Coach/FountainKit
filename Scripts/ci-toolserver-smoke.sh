#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)
exec "$ROOT/Scripts/ci/ci-toolserver-smoke.sh" "$@"
