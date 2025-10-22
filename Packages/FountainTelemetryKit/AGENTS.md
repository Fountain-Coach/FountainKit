# AGENT — FountainTelemetryKit (MIDI/Streaming Diagnostics)

Scope: `Packages/FountainTelemetryKit/**` — MIDI 2.0 stack, SSE over MIDI, diagnostics.

Principles
- Performance constraints documented; streaming buffers sized deterministically.

Testing & TDD
- Unit: encoder/decoder; timebase consistency.
- Integration: streaming resilience tests (where feasible, simulated).

CI gates
- Build + tests; telemetry tests can be skipped on CI where hardware is missing.

