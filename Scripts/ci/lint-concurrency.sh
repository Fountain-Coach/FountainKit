#!/usr/bin/env bash
set -euo pipefail

fail() { echo "[lint] $1" >&2; exit 2; }

# Block DispatchQueue.main.async in app/UI code (Swift files only)
if rg -t swift -n '\bDispatchQueue\.main\.async\b' -S Packages MIDI2InstrumentLab | rg -v '^External/' -n | grep -q .; then
  rg -t swift -n '\bDispatchQueue\.main\.async\b' -S Packages MIDI2InstrumentLab | rg -v '^External/' -n
  fail "Use await MainActor.run instead of DispatchQueue.main.async"
fi

# Block Task.detached in app/UI code (Swift files only)
if rg -t swift -n '\bTask\.detached\(' -S Packages MIDI2InstrumentLab | rg -v '^External/' -n | grep -q .; then
  rg -t swift -n '\bTask\.detached\(' -S Packages MIDI2InstrumentLab | rg -v '^External/' -n
  fail "Avoid Task.detached in app/UI code"
fi

# Prohibit CoreMIDI imports in this repo (Swift only; exclude Sidecar/External)
if rg -t swift -n '\bimport\s+CoreMIDI\b' -S | rg -v '^(Sidecar/|External/)' -n | grep -q .; then
  rg -t swift -n '\bimport\s+CoreMIDI\b' -S | rg -v '^(Sidecar/|External/)' -n
  fail "CoreMIDI usage detected in disallowed paths"
fi

echo "[lint] Concurrency/Focus/CoreMIDI checks passed"
