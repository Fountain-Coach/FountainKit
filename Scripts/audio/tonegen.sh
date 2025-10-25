#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat << 'EOF'
Usage: Scripts/audio/tonegen.sh [--type sine|square|saw|triangle|noise|chirp-lin|chirp-log]
                                [--freq Hz] [--dur seconds] [--sr rate]
                                [--amp 0..1] [--ch 1|2]
                                [--chord f1,f2,...] [--start Hz] [--end Hz]
                                [--out path]

Generates a short WAV file for testing audio and MIDI 2.0 render paths.

Options:
  --type   Waveform (sine|square|saw|triangle|noise|chirp-lin|chirp-log). Default: sine
  --freq   Frequency in Hz (ignored for noise/chirp). Default: 440
  --dur    Duration in seconds. Default: 1.0
  --sr     Sample rate. Default: 44100
  --amp    Amplitude 0..1. Default: 0.3
  --ch     Channels 1 or 2. Default: 1
  --chord  Comma-separated freqs for chord mix (overrides --freq for tone types).
  --start  Start freq for chirps. Default: 200
  --end    End freq for chirps. Default: 2000
  --out    Output WAV path. Default: Public/Audio/tone_<type>_<freq>_<dur>s.wav

Examples:
  bash Scripts/audio/tonegen.sh --type sine --freq 440 --dur 1.0
  bash Scripts/audio/tonegen.sh --type square --freq 220 --dur 2 --sr 48000 --ch 2 --amp 0.25
  bash Scripts/audio/tonegen.sh --type triangle --freq 330 --dur 1.5
  bash Scripts/audio/tonegen.sh --type chirp-lin --start 200 --end 2000 --dur 2.5
  bash Scripts/audio/tonegen.sh --type sine --chord 261.63,329.63,392.00 --dur 1.5
EOF
}

type="sine"
freq="440"
dur="1.0"
sr="44100"
amp="0.3"
ch="1"
out=""
chord=""
startf="200"
endf="2000"

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
    --chord) chord="$2"; shift 2 ;;
    --start) startf="$2"; shift 2 ;;
    --end) endf="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" 1>&2; usage; exit 1 ;;
  esac
done

mkdir -p Public/Audio

if [[ -z "$out" ]]; then
  base="tone_${type}_${freq}_${dur}s.wav"
  [[ "$type" == "noise" ]] && base="tone_${type}_${dur}s.wav"
  [[ "$type" == "chirp-lin" || "$type" == "chirp-log" ]] && base="tone_${type}_${startf}-${endf}_${dur}s.wav"
  if [[ -n "$chord" ]]; then base="tone_${type}_chord_${dur}s.wav"; fi
  out="Public/Audio/${base}"
fi

python3 - "$type" "$freq" "$dur" "$sr" "$amp" "$ch" "$out" "$chord" "$startf" "$endf" << 'PY'
import sys, wave, struct, math, random, os

typ, freq, dur, sr, amp, ch, out, chord, startf, endf = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), int(sys.argv[4]), float(sys.argv[5]), int(sys.argv[6]), sys.argv[7], sys.argv[8], float(sys.argv[9]), float(sys.argv[10])
N = int(sr * dur)
amp = max(0.0, min(1.0, amp))
mix_freqs = []
if chord:
    try:
        mix_freqs = [float(x.strip()) for x in chord.split(',') if x.strip()]
    except Exception as e:
        raise SystemExit(f"invalid --chord: {e}")

def wave_sine(f,t): return math.sin(2*math.pi*f*t)
def wave_square(f,t): return 1.0 if math.sin(2*math.pi*f*t) >= 0 else -1.0
def wave_saw(f,t): return 2.0 * (t*f - math.floor(0.5 + t*f))
def wave_triangle(f,t): return 2.0*abs(2.0*(t*f - math.floor(0.5 + t*f))) - 1.0

def sample_tone(n):
    t = n / sr
    w = None
    if typ == 'sine': w = wave_sine
    elif typ == 'square': w = wave_square
    elif typ == 'saw': w = wave_saw
    elif typ == 'triangle': w = wave_triangle
    elif typ == 'noise': return random.uniform(-1.0, 1.0)
    elif typ in ('chirp-lin','chirp-log'):
        # instantaneous freq
        if typ == 'chirp-lin':
            inst = startf + (endf-startf)*(t/dur)
        else:
            if startf <= 0 or endf <= 0: return 0.0
            k = math.log(endf/startf)/dur
            inst = startf * math.exp(k*t)
        return math.sin(2*math.pi*inst*t)
    else:
        raise SystemExit(f"unknown type: {typ}")
    if mix_freqs:
        s = sum(w(f,t) for f in mix_freqs)
        return s / max(1,len(mix_freqs))
    return w(freq,t)

with wave.open(out, 'w') as wf:
    wf.setnchannels(ch)
    wf.setsampwidth(2)
    wf.setframerate(sr)
    for n in range(N):
        v = max(-1.0, min(1.0, amp * sample_tone(n)))
        i = int(32767 * v)
        frame = struct.pack('<h', i)
        if ch == 2:
            wf.writeframes(frame + frame)
        else:
            wf.writeframes(frame)

print(os.path.abspath(out))
PY

echo "OK: wrote $out"
