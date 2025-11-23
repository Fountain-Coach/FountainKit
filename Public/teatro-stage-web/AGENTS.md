## Teatro Stage Web — Agent Guide

This app is the browser implementation of the Teatro Stage Engine: a small Vite + TypeScript frontend that embeds a wrapped professional physics backend (Cannon‑ES) plus the puppet rig, room, and camera described in `TeatroStageEngine/spec/authoring/teatro-stage-editor.md`. The web implementation is the high‑fidelity reference for puppet motion; the Swift engine in `TeatroPhysics` mirrors the same structures but uses a lighter in‑house solver.

What
- Stage view: Three‑sided Teatro room (floor + walls + door) with a Fadenpuppe marionette rendered via Three.js on a canvas. Orbit and zoom follow the camera spec from TeatroStageEngine.
- Engine: a TypeScript wrapper around Cannon‑ES (`World`, `Body`, constraints) plus a Teatro‑specific puppet rig on top. The same room/rig geometry and invariants are defined in `TeatroPhysics/spec/**`, but on the web the integrator and contacts come from Cannon‑ES instead of a home‑grown solver.
- Authoring UX: simple time bar with record/scrub/snapshot, small inspector for labels and camera/time readout. Dragging the bar or stage actors during record writes engine state over time; scrubbing replays it.

Why
- Provide a portable, spec‑aligned reference implementation of the Teatro Stage Engine that runs without a macOS app, and that can be kept in sync with the Swift engine via the shared specs and snapshots.
- Act as the human‑facing playground for the stage: quick sketching of puppet motion and constellations, with snapshots that can be exported to other tools (e.g. FountainKit).

How
- Dev server: `npm install` then `npm run dev` inside `Public/teatro-stage-web`, with Vite serving `index.html`.
- Build (later): `npm run build` to emit a static bundle under `dist/`.
- Engine parity: TS engine types and constants must mirror the Swift equivalents in `TeatroStageEngine` (world scale, gravity, constraint stiffness, rig dimensions).

Conventions
- Specs‑first: camera, rig, room, and authoring behaviour follow the documents under `TeatroStageEngine/spec/**`. When behaviour changes, update specs first, then align both the Swift solver and this Cannon‑based wrapper. Cannon provides the low‑level contact/joint behaviour; we still treat the spec as authoritative for geometry and invariants.
- No secrets: the app should not embed credentials or call private APIs; it runs purely client‑side or against public/demo endpoints.
- No generated clients: if the app later talks to a TeatroStageEngine HTTP surface, use lightweight hand‑rolled fetches or a small TS client, but do not commit generated code without a clear need.

For how this web app fits into the broader “Teatro Stage as instruments” story (Stage World, Puppet, Camera, Style, Recording), see `Design/TeatroStage-Instruments-Map.md`. That document explains how engine specs, FountainKit instruments, and hosts like this one line up.
