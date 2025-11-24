Teatro Stage App hosts the Teatro engine as a MetalViewKit surface so we can reason about the stage in the same stack as PatchBay and Infinity. It is deliberately small: one window, one `MetalCanvasView`, one `TeatroStageMetalNode`, and a single `TeatroStageScene` with a few reps and a spotlight. There is no MIDI or Tools wiring yet; this app is for visual and geometric validation of the Teatro stage.

The visual baseline is the Three.js demos in `Design/teatro-engine-spec/demo1.html` and `demo2.html`, but MetalViewKit is the authority here. Keep the palette in the Teatro paper style (warm paper, black line work, soft light); avoid UI chrome beyond the standard window frame.

Run the app with `swift run --package-path Packages/FountainApps teatro-stage-app` and move the window next to the HTML demo when tuning shapes and light. If you extend the scene model (more lights, rigs, or timeline controls), update this app first so changes stay grounded in a visible stage before you wire them into instruments or services.

When turning this app into a proper FountainKit instrument host (camera/rig/world controls, recording, facts), follow the conceptual map in `Design/TeatroStage-Instruments-Map.md`. That document describes which parts of the Teatro stage become instruments and how the MetalViewKit view should relate to the engine specs and OpenAPI surfaces.
