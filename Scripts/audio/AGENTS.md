# AGENT — Scripts/audio (Audio utilities)

Scope: `Scripts/audio/**`.

Purpose
- Small, reproducible audio helpers for development and demos.
- Current: tone generator to create test WAVs for local render and MIDI 2.0 pipelines.

Conventions
- Idempotent and safe. All scripts use `set -euo pipefail` and print `Usage:` help.
- Outputs default under `Public/Audio/` (created if missing).

Tools
- `tonegen.sh` — generate short WAV files.
  - Sine, square, saw, or noise.
  - Sample‑rate, duration, amplitude, channels configurable.
  - Implementation uses Python (stdlib `wave`, no external deps).

Examples
- Generate a 1s A440 sine (mono):
  - `bash Scripts/audio/tonegen.sh --type sine --freq 440 --dur 1.0`
- Generate a 2s square 220 Hz stereo at 48 kHz:
  - `bash Scripts/audio/tonegen.sh --type square --freq 220 --dur 2 --sr 48000 --ch 2 --amp 0.25`

