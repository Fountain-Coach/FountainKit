# AGENT — SDLExperiment (Composer + SDLKit)

`Packages/SDLExperiment/**` is a standalone SwiftPM package for SDL‑based rendering experiments. It’s active for experiments only and is not part of the root workspace build — build it directly via `--package-path`.

The goals are simple: validate SDLKit for high‑refresh rendering, input latency, and windowing relevant to Composer Studio, and prototype fast visualizations (cue timelines, score previews, audio meters). Ensure the SDLKit submodule is present (`git submodule update --init --recursive External/SDLKit`), then build and run with `swift run --package-path Packages/SDLExperiment sdl-composer-experiment`.

The code opens a resizable window and animates at 60 fps (`Sources/SDLComposerExperiment/main.swift`); `Package.swift` pins a local dependency on `External/SDLKit`. This package is intentionally isolated so missing submodules don’t break the main workspace or CI. If you promote a feature into Composer Studio, create a dedicated module under FountainApps and gate it behind a feature flag.

Next experiments include text rendering (SDL_ttf) for lyric/label tests, offscreen render targets and texture upload timings, a data→visual mapping prototype (cue plan overlay), and measuring keyboard/mouse→render latency.
