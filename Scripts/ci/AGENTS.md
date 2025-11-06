# AGENT — Scripts/ci (smoke tests and helpers)

`Scripts/ci/**` contains CI‑oriented smoke tests and status probes, kept separate from developer‑facing helpers. These scripts stand up a minimal stack, verify health and route shapes, and tear down cleanly so failures are quick to isolate.

What’s included
`ci-smoke.sh` brings up the core services with readiness checks, probes metrics (JSON for gateway), and tears everything down. Set `CI_TG_SMOKE=1` to also register the Teatro Prompt Field Guide tools and exercise one endpoint via FunctionCaller, writing an ETag + response under `.fountain/artifacts/`. `ci-toolserver-smoke.sh` optionally exercises the tool‑server when `CI_TOOLSERVER_SMOKE=1`. For Metal validations, `metal-lib-smoke.sh` builds SDLKit and validates that prebuilt metallibs load via `MTLDevice.makeLibrary(URL:)`; set `SDLKIT_SMOKE_LIBS` to filter and `SDLKIT_ALLOW_INLINE_FALLBACK=1` to accept inline fallback on macOS. `metal-lib-build.sh` compiles native `.metal` sources into `.metallib` outside the SwiftPM plugin sandbox (accepts `--package-path` and `--out`; honors `MACOSX_DEPLOYMENT_TARGET`).

- mvk-runtime-smoke — `bash Scripts/ci/mvk-runtime-smoke.sh` builds and runs the lightweight `mvk-runtime-tests` executable to exercise the MetalViewKit runtime locally. It verifies: health (`GET /health`), live loopback MVK listing (`GET /v1/midi/endpoints`), and event forwarding (`POST /v1/midi/events`). Writes JSON summary to `.fountain/logs/mvk-runtime-smoke-*.json` and exits non‑zero on failure.

How to run
Workspace smoke: `bash Scripts/ci/ci-smoke.sh`. Tool‑server smoke: `CI_TOOLSERVER_SMOKE=1 bash Scripts/ci/ci-toolserver-smoke.sh`. Metal checks: `bash Scripts/ci/metal-lib-smoke.sh` (macOS with Metal). Build metallibs: `bash Scripts/ci/metal-lib-build.sh`. MVK runtime smoke: `bash Scripts/ci/mvk-runtime-smoke.sh`.

Compatibility
Legacy wrappers exist at `Scripts/ci-smoke.sh` and `Scripts/ci-toolserver-smoke.sh` and delegate to these canonical paths to keep CI configs stable.
