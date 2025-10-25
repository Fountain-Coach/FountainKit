#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat << 'EOF'
Usage: Scripts/audio/tonegen.sh [--type sine|square|saw|noise] [--freq Hz] [--dur seconds] [--sr rate]
                                [--amp 0..1] [--ch 1|2] [--out path]

Generates a short WAV file for testing audio and MIDI 2.0 render paths.

Options:
  --type   Waveform type (sine|square|saw|noise). Default: sine
  --freq   Frequency in Hz (ignored for noise). Default: 440
  --dur    Duration in seconds. Default: 1.0
  --sr     Sample rate. Default: 44100
  --amp    Amplitude 0..1. Default: 0.3
  --ch     Channels 1 or 2. Default: 1
  --out    Output WAV path. Default: Public/Audio/tone_<type>_<freq>_<dur>s.wav

Examples:
  bash Scripts/audio/tonegen.sh --type sine --freq 440 --dur 1.0
  bash Scripts/audio/tonegen.sh --type square --freq 220 --dur 2 --sr 48000 --ch 2 --amp 0.25
EOF
}

type="sine"
freq="440"
dur="1.0"
sr="44100"
amp="0.3"
ch="1"
out=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --type) type="$2"; shift 2 ;;
    --freq) freq="$2"; shift 2 ;;
    --dur) dur="$2"; shift 2 ;;
    --sr) sr="$2"; shift 2 ;;
    --amp) amp="$2"; shift 2 ;;
    --ch) ch="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" 1>&2; usage; exit 1 ;;
  esac
done

mkdir -p Public/Audio

if [[ -z "$out" ]]; then
  base="tone_${type}_${freq}_${dur}s.wav"
  [[ "$type" == "noise" ]] && base="tone_${type}_${dur}s.wav"
  out="Public/Audio/${base}"
fi

python3 - "$type" "$freq" "$dur" "$sr" "$amp" "$ch" "$out" << 'PY'
import sys, wave, struct, math, random, os

typ, freq, dur, sr, amp, ch, out = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), int(sys.argv[4]), float(sys.argv[5]), int(sys.argv[6]), sys.argv[7]
N = int(sr * dur)
amp = max(0.0, min(1.0, amp))

def sample(n):
    t = n / sr
    if typ == 'sine':
        return math.sin(2*math.pi*freq*t)
    if typ == 'square':
        return 1.0 if math.sin(2*math.pi*freq*t) >= 0 else -1.0
    if typ == 'saw':
        # naive saw (band-limited not needed for short test tones)
        return 2.0 * (t*freq - math.floor(0.5 + t*freq))
    if typ == 'noise':
        return random.uniform(-1.0, 1.0)
    raise SystemExit(f"unknown type: {typ}")

with wave.open(out, 'w') as wf:
    wf.setnchannels(ch)
    wf.setsampwidth(2)
    wf.setframerate(sr)
    for n in range(N):
        v = int(32767 * amp * sample(n))
        frame = struct.pack('<h', v)
        if ch == 2:
            wf.writeframes(frame + frame)
        else:
            wf.writeframes(frame)

print(os.path.abspath(out))
PY

echo "OK: wrote $out"

