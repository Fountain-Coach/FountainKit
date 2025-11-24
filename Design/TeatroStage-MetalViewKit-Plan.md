# TeatroStage MetalViewKit Integration Plan

This document sketches how to bring the Teatro stage (room, puppet, reps, lights, timeline)
into the FountainKit engine as a first-class MetalViewKit surface and instrument.

The goal is to stop treating the Teatro stage as a one-off SDL line sketch and instead
fold it into the existing Canvas2D/MetalViewKit/Instrument architecture, so that:

- the stage is rendered by MetalViewKit, not ad-hoc 2D calls,
- the same engine model drives the stage, the constellation field, and puppet rigs,
- the surface is addressable via OpenAPI + PE facts like any other instrument.

The Three.js demos (`demo1.html`, `demo2.html`) remain visual references; the Swift
engine and MetalViewKit view become the authoritative implementation.

---

## 1. Engine Model — `TeatroStageScene`

Introduce a small, pure Swift model that represents a Teatro scene independent of
any renderer or host:

- `TeatroStageScene`
  - `camera`:
    - `azimuth` (rotation around Y; elevation fixed to isometric angle),
    - `zoom` (orthographic scale),
  - `room`:
    - width / depth / height,
    - doors (wall, offset, size),
  - `reps`: representatives on the floor plane
    - `id: String`,
    - `position: Vec3` (y=0 plane, systemic constellation style),
    - optional `roleLabel` (CLIENT, MOTHER, etc.),
  - `lights`:
    - `type: LightType` (SPOT, WASH, BACKLIGHT),
    - `origin: Vec3`, `target: Vec3`,
    - `radius`, `intensity`, optional `label`,
  - `rigs`:
    - zero or more puppet rigs (for Fadenpuppe, etc.),
  - `timeline`:
    - optional history of snapshots (time, camera, reps, lights) for replay/scrubbing.

This is the in-process mirror of the Teatro engine OpenAPI (`Design/teatro-engine-spec/openapi/teatro-engine.yaml`)
and of the constellation-stage spec, but lives entirely in Swift, under a new module
or a MetalViewKit-adjacent file.

No SDL or Metal types appear here; it is purely geometry and state.

---

## 2. Metal Node — `TeatroStageMetalNode`

Add a MetalCanvasNode implementation that knows how to draw the Teatro stage using
MetalViewKit’s existing transforms:

- File: `Packages/FountainApps/Sources/MetalViewKit/TeatroStageMetalNode.swift`.
- Conform to `MetalCanvasNode` so it can be hosted by `MetalCanvasView`.
- Properties:
  - `id: String`,
  - `scene: TeatroStageScene` (or a read-only view into it),
  - optional styling parameters (line weights, colours, accent flags).
- `encode(into:device:encoder:transform:)`:
  - compute a world→doc transform for the isometric projection:
    - room/world space expressed in doc coordinates (`Canvas2D`-friendly),
    - isometric camera applied via a small helper (like the current 2D math in the SDL demo),
  - draw:
    - room: floor and walls as line segments, matching Teatro black-on-paper style,
    - puppet silhouette: triangles + lines for torso, head, limbs (animated via scene rig state),
    - reps: circles or small filled shapes on the floor plane,
    - lights:
      - SPOT: projected ovals on floor, drawn as filled or outlined shapes in lighter paper tone,
      - WASH: rectangles or polygons on back wall,
      - BACKLIGHT: slightly brighter outlines around selected silhouettes.

`MetalCanvasTransform` already maps doc space into NDC; we use that as the final step
after applying the engine’s isometric projection.

The node does **not** own input; it just draws based on the current `TeatroStageScene`.

---

## 3. Hosting in `MetalCanvasView`

Expose the Teatro node through the existing MetalCanvasView machinery:

- Add a nodes provider that returns a single `TeatroStageMetalNode` (plus any other nodes if needed).
- Use `Canvas2D`/`MetalCanvasTransform` as the doc→view transform, but treat Teatro’s isometric
  projection as an internal world→doc step:
  - world (Teatro engine coordinates) → doc (`Canvas2D`),
  - doc → NDC (MetalCanvasTransform),
  - NDC → screen (Metal).

For the initial integration, we can:

- create a small SwiftUI wrapper (like the existing canvas views) that hosts
  `MetalCanvasView` with a single Teatro node,
- add an `AppKit` entry point under `FountainApps` that opens this view in a window
  (parallel to the existing Metal canvas demos).

Optionally, we can later embed this inside an SDLKit window, but the first target is
to get a clean MetalViewKit-based Teatro window running on macOS.

---

## 4. Instrument Descriptor — Teatro Stage Instrument

Define an instrument descriptor that maps Teatro engine properties to MIDI 2 PE /
OpenAPI fields, following the existing MetalInstrument patterns:

- New descriptor type: `TeatroStageInstrumentDescriptor` (or similar).
- Backed by:
  - the `TeatroStageScene` model,
  - the Constellation Stage spec (`constellation-stage.yml`),
  - the Teatro engine spec (for more advanced rigs/lights).
- Exposed properties (initial set):
  - `field.zoom`, `field.translation.x`, `field.translation.y` (camera),
  - `field.replay.t`, `field.replay.playing` (timeline),
  - minimal light controls (`light[0].intensity`, etc.) if we want PE to drive light.

Wire this descriptor into a `MetalInstrument` whose sink talks to `TeatroStageMetalNode`,
so setting a PE property immediately updates the scene model and redraws via Metal.

This gives us:

- a Constellation Stage instrument (no rigs, reps + lights only),
- a Puppet Rig instrument (rig properties exposed, room/rep/lighting as context),
both sharing the same underlying Teatro engine and renderer.

---

## 5. Input & Interaction

Keep interactions consistent with the style spec and existing Infinity/Canvas patterns:

- Camera:
  - orbit: drag on empty stage → adjust `camera.azimuth`,
  - zoom: pinch/wheel or a dedicated handle → adjust `camera.zoom`.
- Representatives:
  - pick on floor plane and drag → update rep positions in world coordinates,
  - selection handled by MetalCanvasView selection machinery where possible.
- Timeline:
  - long-term: integrate a proper replay control (similar to the SDLKit demo’s
    timeline) either inside the Teatro stage view or as a separate control surface,
  - engine records snapshots; MetalViewKit view simply renders a chosen frame.

Initial implementation can defer input to a thin controller that owns the
`TeatroStageScene` and forwards updates into the Metal node.

---

## 6. OpenAPI & Facts Alignment

Ensure that the MetalViewKit implementation matches and reuses the engine specs:

- Constellation Stage spec (`Packages/FountainSpecCuration/openapi/v1/constellation-stage.yml`)
  remains the primary PE/OpenAPI surface for the constellation instrument.
- Teatro Engine spec (`Design/teatro-engine-spec/openapi/teatro-engine.yaml`) describes
  the more general scene/rig/light space; the engine model is aligned with this.
- Facts:
  - use `openapi-to-facts` to generate agent facts for the Teatro stage instrument(s),
  - ensure properties exposed by `TeatroStageInstrumentDescriptor` match the facts.

---

## 7. Migration of Demos

Use existing demos as references and gradually converge them:

- Keep `Design/teatro-engine-spec/demo1.html` and `demo2.html` as visual references
  for the MetalViewKit renderer (camera, room geometry, puppet behaviour, lights).
- Keep `teatro-engine-demo` (SDLKit) as a **logic and interaction prototype**:
  - once TeatroStageMetalNode exists, we can drop the SDLRenderer sketch and either:
    - host the Metal view in SwiftUI/AppKit, or
    - embed MetalViewKit into an SDLKit window if needed.

The long-term goal is one authoritative Teatro engine model and one MetalViewKit
renderer, with browsers and SDL prototypes as thin clients or references.

