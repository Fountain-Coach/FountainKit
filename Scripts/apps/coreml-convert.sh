#!/usr/bin/env bash
set -euo pipefail

# Core ML conversion helper (CREPE / BasicPitch / generic Keras/TFLite)
#
# Usage:
#   Scripts/apps/coreml-convert.sh crepe --saved-model <dir> [--frame 1024] [--out Public/Models/CREPE.mlmodel]
#   Scripts/apps/coreml-convert.sh basicpitch --saved-model <dir> [--out Public/Models/BasicPitch.mlmodel]
#   Scripts/apps/coreml-convert.sh keras --h5 <file.h5> [--frame 1024] [--out Public/Models/Model.mlmodel]
#   Scripts/apps/coreml-convert.sh tflite --tflite <file.tflite> [--frame 1024] [--out Public/Models/Model.mlmodel]
#
# Notes:
# - Creates/uses a local virtualenv at .coremlvenv and installs coremltools + deps on first run.
# - Input shapes default to a 1x1024 frame for 1D audio models; adjust with --frame.
# - SavedModel and Keras require TensorFlow installed in the venv. We pin to TF 2.15 for compatibility.

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
venv="$root/.coremlvenv"

usage() {
  sed -n '1,80p' "$0" | sed -n '1,30p'
}

ensure_venv() {
  if [[ ! -d "$venv" ]]; then
    echo "[coreml-convert] creating venv at $venv"
    python3 -m venv "$venv"
  fi
  # shellcheck disable=SC1091
  source "$venv/bin/activate"
  python3 -m pip install --upgrade pip >/dev/null
  # core deps; keep versions compatible with Xcode toolchains
  python3 -m pip install --quiet coremltools==7.1 numpy
  if [[ "${1:-}" == "tf" ]]; then
    python3 -m pip install --quiet tensorflow==2.15.0
  fi
}

cmd=${1:-}
shift || true

case "$cmd" in
  crepe)
    saved=""
    frame=1024
    out="$root/Public/Models/CREPE.mlmodel"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --saved-model) saved="$2"; shift 2;;
        --frame) frame="$2"; shift 2;;
        --out) out="$2"; shift 2;;
        -h|--help) usage; exit 0;;
        *) echo "Unknown arg: $1"; usage; exit 2;;
      esac
    done
    if [[ -z "$saved" ]]; then echo "[error] --saved-model required"; usage; exit 2; fi
    ensure_venv tf
    python3 "$here/coreml_convert.py" crepe --saved-model "$saved" --frame "$frame" --out "$out"
    ;;
  basicpitch)
    saved=""
    out="$root/Public/Models/BasicPitch.mlmodel"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --saved-model) saved="$2"; shift 2;;
        --out) out="$2"; shift 2;;
        -h|--help) usage; exit 0;;
        *) echo "Unknown arg: $1"; usage; exit 2;;
      esac
    done
    if [[ -z "$saved" ]]; then echo "[error] --saved-model required"; usage; exit 2; fi
    ensure_venv tf
    python3 "$here/coreml_convert.py" basicpitch --saved-model "$saved" --out "$out"
    ;;
  keras)
    h5=""
    frame=1024
    out="$root/Public/Models/Model.mlmodel"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --h5) h5="$2"; shift 2;;
        --frame) frame="$2"; shift 2;;
        --out) out="$2"; shift 2;;
        -h|--help) usage; exit 0;;
        *) echo "Unknown arg: $1"; usage; exit 2;;
      esac
    done
    if [[ -z "$h5" ]]; then echo "[error] --h5 required"; usage; exit 2; fi
    ensure_venv tf
    python3 "$here/coreml_convert.py" keras --h5 "$h5" --frame "$frame" --out "$out"
    ;;
  tflite)
    tfl=""
    frame=1024
    out="$root/Public/Models/Model.mlmodel"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --tflite) tfl="$2"; shift 2;;
        --frame) frame="$2"; shift 2;;
        --out) out="$2"; shift 2;;
        -h|--help) usage; exit 0;;
        *) echo "Unknown arg: $1"; usage; exit 2;;
      esac
    done
    if [[ -z "$tfl" ]]; then echo "[error] --tflite required"; usage; exit 2; fi
    ensure_venv
    python3 "$here/coreml_convert.py" tflite --tflite "$tfl" --frame "$frame" --out "$out"
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    echo "Unknown command: $cmd"; usage; exit 2
    ;;
esac

