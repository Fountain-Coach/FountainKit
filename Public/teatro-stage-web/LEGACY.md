Teatro Stage Web — Legacy Implementation
========================================

This folder previously contained the first Teatro Stage web host: a Vite + React + Three.js + Cannon‑ES app with a `PuppetRig`, `StageView`, and a simple time bar and snapshot inspector.

The original implementation now lives under:

- `Public/teatro-stage-web/src-legacy/**`

It remains useful as a reference for:

- integration patterns with Cannon‑ES and Three.js,
- early experiments in authoring UX (time bar + snapshots),
- rough parity checks against the Swift engine when the specs were younger.

We are rebuilding the web host from a clean slate under `Public/teatro-stage-web/src/**`, following the mapping and workflow in:

- `Design/TeatroStage-Instruments-Map.md` (FountainKit),
- `TeatroStageEngine/docs/TeatroStage-Instruments-Map.md` (engine‑side view).

Do not extend the legacy code path for new work; use it only as a visual or structural reference when implementing the new, spec‑first host.

