# AGENT — SDLExperiment (Composer + SDLKit)

Scope: `Packages/SDLExperiment/**` — standalone SwiftPM package for SDL‑based rendering experiments.

Status: ACTIVE (experiments only). Not part of the workspace build; build directly via `--package-path`.

Goals
- Validate SDLKit for high‑refresh rendering, input latency, and windowing for Composer Studio.
- Prototype fast visualizations (e.g., cue timelines, score previews, audio meters).

How to run
- Ensure the SDLKit submodule is present:
  - `git submodule update --init --recursive External/SDLKit`
- Build + run:
  - `swift run --package-path Packages/SDLExperiment sdl-composer-experiment`

Code structure
- `Sources/SDLComposerExperiment/main.swift` — opens a resizable window and animates a bouncing rectangle at 60 fps.
- `Package.swift` — local dependency on `External/SDLKit`.

Notes
- This package is intentionally isolated to avoid breaking the root workspace/CI if `External/SDLKit` is not checked out.
- When promoting features into Composer Studio, create a dedicated module under FountainApps and gate behind a feature flag.

Next experiments
- Text rendering (SDL_ttf) for lyric/label tests.
- Offscreen render targets and texture upload timings.
- Data→visual mapping prototype (cue plan → overlay visualization).
- Event bridging: measure latency for keyboard/mouse → render.

