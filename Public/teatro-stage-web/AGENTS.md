## Teatro Stage Web — Agent Guide

This app is the browser implementation of the Teatro Stage Engine: a small Vite + TypeScript frontend that embeds a JavaScript port of the engine (physics + puppet rig + room + camera) and exposes the authoring UX described in `TeatroStageEngine/spec/authoring/teatro-stage-editor.md`.

What
- Stage view: Three‑sided Teatro room (floor + walls + door) with a Fadenpuppe marionette rendered via Three.js on a canvas. Orbit and zoom follow the camera spec from TeatroStageEngine.
- Engine: a TypeScript port of the TeatroStageEngine core (`Vec3`, `Body`, `World`, `DistanceConstraint`, `PuppetRig`) that runs entirely in the browser; the app does not depend on a new Swift service.
- Authoring UX: simple time bar with record/scrub/snapshot, small inspector for labels and camera/time readout. Dragging the bar or stage actors during record writes engine state over time; scrubbing replays it.

Why
- Provide a portable, spec‑aligned reference implementation of the Teatro Stage Engine that runs without a macOS app, and that can be kept in sync with the Swift engine via the shared specs and snapshots.
- Act as the human‑facing playground for the stage: quick sketching of puppet motion and constellations, with snapshots that can be exported to other tools (e.g. FountainKit).

How
- Dev server (once wired): `npm install` then `npm run dev` inside `Public/teatro-stage-web`, with Vite serving `index.html`.
- Build (later): `npm run build` to emit a static bundle under `dist/`.
- Engine parity: TS engine types and constants must mirror the Swift equivalents in `TeatroStageEngine` (world scale, gravity, constraint stiffness, rig dimensions).

Conventions
- Specs‑first: camera, rig, room, and authoring behaviour follow the documents under `TeatroStageEngine/spec/**`. When behaviour changes, update specs + Swift first, then this app.
- No secrets: the app should not embed credentials or call private APIs; it runs purely client‑side or against public/demo endpoints.
- No generated clients: if the app later talks to a TeatroStageEngine HTTP surface, use lightweight hand‑rolled fetches or a small TS client, but do not commit generated code without a clear need.

