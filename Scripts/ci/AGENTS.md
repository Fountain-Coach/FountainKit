# AGENT — Scripts/ci (smoke tests and helpers)

Scope: `Scripts/ci/**`.

Purpose
- Keep CI‑oriented scripts (smoke tests, status probes) separate from developer tooling.

Included tools
- `ci-smoke.sh` — Brings up core services with readiness checks; probes metrics; tears down.
- `ci-toolserver-smoke.sh` — Optional smoke for tool-server when `CI_TOOLSERVER_SMOKE=1`.
- `metal-lib-smoke.sh` — Builds SDLKit and validates prebuilt Metal libraries load via `MTLDevice.makeLibrary(URL:)` (fails on incompatible metallibs).
  - Env: `SDLKIT_SMOKE_LIBS` (comma‑separated names to filter; empty = all), `SDLKIT_ALLOW_INLINE_FALLBACK=1` to accept inline Metal fallback on macOS and keep the job green while still printing failures.
- `metal-lib-build.sh` — Compiles native `.metal` sources into `.metallib` outside the SwiftPM plugin sandbox.
  - Args: `--package-path <path>` (defaults to `External/SDLKit`), `--out <dir>` (defaults to `Sources/SDLKit/Generated/metal`).
  - Honors `MACOSX_DEPLOYMENT_TARGET` (defaults to `13.0`), and auto-discovers `metal`/`metallib` via `xcrun -f` when not on PATH.

Usage
- Workspace smoke: `bash Scripts/ci/ci-smoke.sh`
- Toolserver smoke: `CI_TOOLSERVER_SMOKE=1 bash Scripts/ci/ci-toolserver-smoke.sh`
- Metal libraries: `bash Scripts/ci/metal-lib-smoke.sh` (macOS with Metal)
- Build metallibs: `bash Scripts/ci/metal-lib-build.sh` (macOS with Metal tools installed)

Compatibility
- Legacy wrappers remain at `Scripts/ci-smoke.sh` and `Scripts/ci-toolserver-smoke.sh` and delegate to these canonical paths.
