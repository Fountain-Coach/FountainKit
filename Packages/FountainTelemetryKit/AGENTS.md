# AGENT — FountainTelemetryKit (MIDI/streaming diagnostics)

What: `Packages/FountainTelemetryKit/**` provides the MIDI 2.0 stack, SSE‑over‑MIDI, and diagnostics. Keep performance constraints explicit and buffers sized deterministically to prevent regressions.

Where code lives
- MIDI 2.0: `Packages/FountainTelemetryKit/Sources/MIDI2*`
- SSE over MIDI: `Packages/FountainTelemetryKit/Sources/SSEOverMIDI`
- Flex bridge/CLI: `Packages/FountainTelemetryKit/Sources/FlexBridge`, `Tools/flexctl`

Build/test
- Build: `swift build --package-path Packages/FountainTelemetryKit -c debug`
- Tests: `swift test --package-path Packages/FountainTelemetryKit -c debug`

Testing
Cover encoders/decoders and timebase consistency. When hardware isn’t available, simulate long‑running streams to probe resilience. CI builds/tests this package; telemetry tests may be skipped without supported hardware.

Baseline policy (cross‑package)
- The default UI baseline is Baseline‑PatchBay (grid‑dev‑app). MIDI‑driven invariants and instrument semantics tested there (MRTS prompt + robot tests) are the reference when adjusting telemetry adapters and transports. Keep identifiers stable and ensure loopback/CoreMIDI modes continue to satisfy the Baseline robot suites (`Scripts/ci/baseline-robot.sh`).
