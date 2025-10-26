# AGENT — FountainTelemetryKit (MIDI/streaming diagnostics)

`Packages/FountainTelemetryKit/**` provides the MIDI 2.0 stack, SSE‑over‑MIDI, and diagnostics. Performance constraints must be explicit and buffers sized deterministically so streaming doesn’t regress as we evolve the stack.

Tests cover encoders/decoders and timebase consistency; where hardware isn’t available, simulate long‑running streams to probe resilience. CI builds and tests this package; telemetry tests may be skipped when hardware is absent.
