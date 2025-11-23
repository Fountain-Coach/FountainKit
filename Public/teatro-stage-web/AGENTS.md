## Teatro Stage Web — Agent Guide

This app is the browser implementation of the Teatro Stage Engine: a small Vite + TypeScript frontend that hosts the Teatro room and puppet as a web surface. We are rebuilding it from a clean slate: the original Cannon‑ES + Three.js implementation now lives under `Public/teatro-stage-web/src-legacy/**`, and the new `src/**` tree starts with a minimal SVG stage view that will be wired back up to the specs.

What
- Stage view (new path): Three‑sided Teatro room and a simple puppet silhouette rendered as SVG in React, following the paper‑stage style. The current implementation focuses on geometry and visual style; camera and rig controls will be reintroduced as the new engine wrapper lands.
- Stage engine (legacy path): `src-legacy/**` contains the original Cannon‑ES + Three.js host (`World`, `Body`, constraints, `PuppetRig`, `StageView`, `TimeBar`). Use it as a reference when rebuilding the new engine wrapper; do not extend it for new features.

Why
- Provide a portable, spec‑aligned reference implementation of the Teatro Stage Engine that runs without a macOS app. The rebuild aims to keep the web host very close to `TeatroStageEngine` specs and the Swift engine, with a clear separation between engine wrapper and UI.
- Act as the human‑facing playground for the stage: quick sketching of puppet motion and constellations, with snapshots that can be exported to other tools (e.g. FountainKit). During the rebuild, focus first on a clean stage view and then on authoring controls.

How
- Dev server: `npm install` then `npm run dev` inside `Public/teatro-stage-web`, with Vite serving `index.html`.
- Build: `npm run build` to emit a static bundle under `dist/`.
- Engine parity (target): as the new wrapper is implemented, TS engine types and constants must mirror the Swift equivalents in `TeatroStageEngine` (world scale, gravity, constraint stiffness, rig dimensions). Until then, the SVG stage acts as a visual sketch rooted in the same room/puppet geometry.

Conventions
- Specs‑first: room, rig, camera, and authoring behaviour follow the documents under `TeatroStageEngine/spec/**`. When behaviour changes, update specs first, then align both the Swift engine and this web host. The new engine wrapper should treat the specs as authoritative and avoid ad‑hoc parameters.
- No secrets: the app should not embed credentials or call private APIs; it runs purely client‑side or against public/demo endpoints.
- No generated clients: if the app later talks to a TeatroStageEngine HTTP surface, use lightweight hand‑rolled fetches or a small TS client, but do not commit generated code without a clear need.

For how this web app fits into the broader “Teatro Stage as instruments” story (Stage World, Puppet, Camera, Style, Recording), see `Design/TeatroStage-Instruments-Map.md`. That document explains how engine specs, FountainKit instruments, and hosts like this one line up.
