#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

swift run --package-path "$ROOT_DIR/Packages/FountainTooling" -c debug instrument-lint

