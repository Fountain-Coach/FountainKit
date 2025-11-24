TeatroStageEngine
==================

TeatroStageEngine is the canonical game engine for the Teatro puppet stage: a small, pure‑Swift package that defines the physics core, puppet rig, stage geometry, and written specs for camera, visual style, and interchange. It is renderer‑agnostic by design — no Metal, SDL, or UIKit — and is meant to be embedded into hosts like FountainKit, MetalViewKit demos, or web frontends via a thin bridge.

From the engine’s point of view, there is only:
- a world with gravity,
- a rig (the Fadenpuppe marionette),
- a three‑sided room,
- a camera that orbits and zooms around that scene,
- and a deterministic way to advance state and take snapshots.

Everything else — drawing, MIDI control, network APIs — lives on top.

## 0. What lives here

This repository carries two things in lockstep:

1. **Specs** under `spec/`  
   These documents describe the engine in human terms:
   - `spec/camera` — orthographic camera model and input mapping.
   - `spec/physics` — world/timestep and constraint behaviour.
   - `spec/rig-puppet` — Fadenpuppe topology and geometry.
   - `spec/stage-room` — floor, walls, and door geometry.
   - `spec/style` — paper palette, line weights, light shapes.
   - `spec/interchange` — snapshot schema and integration notes.

   If you change behaviour, update the relevant spec first and then the code.

2. **Engine code** under `Sources/TeatroPhysics`  
   This is the minimal Swift core that implements the specs:
   - `TPVec3` — small value type for 3D vectors.
   - `TPBody` — rigid body with position, velocity, mass.
   - `TPWorld` — collection of bodies and constraints with gravity and damping.
   - `TPConstraint` and `TPDistanceConstraint` — a soft rope/rod between two bodies.
   - `TPPuppetRig` — assembles a world matching the Fadenpuppe rig spec and exposes
     `step(dt:time:)` and `snapshot()` for hosts.

The engine does not know about cameras or rooms explicitly; those are described in `spec/` and implemented in whichever renderer you plug in (MetalViewKit, Three.js, SVG, etc.).

## 1. World + physics core

The physics layer is intentionally small and deterministic:

- Coordinates: right‑handed, `y` up. Units are abstract but match the Three.js demo scale (floor ≈ 30 units wide, walls 20 units high, puppet ≈ 10 units tall).
- World: `TPWorld` owns bodies and constraints plus a gravity vector and linear damping.
- Integrator: semi‑implicit Euler (`velocity` from gravity + damping, then `position` from velocity).
- Constraints: objects conforming to `TPConstraint.solve(dt:)` that nudge body positions to reduce error; the first and primary one is `TPDistanceConstraint`.

The reference timestep is `dt = 1/60`. Hosts own the clock and call `world.step(dt:)` at whatever cadence they need, clamping `dt` if required. For details, see `spec/physics/world-and-timestep.md` and `spec/physics/constraints.md`.

## 2. Puppet rig (Fadenpuppe)

The puppet rig is implemented by `TPPuppetRig` and specified in `spec/rig-puppet`:

- Bodies:
  - `bar` — crossbar above the stage.
  - `torso` — central block.
  - `head` — head block.
  - `handL`, `handR` — left and right hands.
  - `footL`, `footR` — left and right feet.
- Skeleton constraints keep head, hands, and feet attached to the torso.
- String constraints connect bar to head and hands.

At construction time, the rig:
- creates a `TPWorld`,
- positions bodies according to the geometry spec,
- adds distance constraints for bones and strings using initial distances as rest lengths.

During simulation:
- `step(dt:time:)` drives the bar using a simple sway/up‑down motion (mirroring the JS demo) and advances the world.
- `snapshot()` returns a `TPPuppetSnapshot` with body positions; renderers map those into their own vector types and draw box outlines, silhouettes, strings, etc.

## 3. Stage geometry, camera, and style

TeatroStageEngine does not ship a renderer, but it does lock down the numbers and behaviour that renderers should follow:

- **Stage room** (`spec/stage-room`):
  - Floor: 30 × 20 rectangle in the XZ plane, centered at the origin, at `y = 0`.
  - Walls: back, left, and right walls 20 units high around the floor.
  - Door: smaller rectangle cut into the right wall toward the back.

- **Camera** (`spec/camera`):
  - Orthographic camera with frustum derived from `frustumSize = 40` and viewport aspect.
  - Fixed elevation `atan(1 / sqrt(2))` (~35°).
  - Orbiting via azimuth around the Y axis.
  - Zoom as an orthographic scale factor, clamped in `[0.5, 3.0]`.
  - Input mapping for pointer drag, wheel, and pinch is documented so orbit/zoom feel consistent across implementations.

- **Style** (`spec/style`):
  - Paper background `#f4ead6`.
  - Line colour `#111111`.
  - Hairline edges for room and puppet, slightly lighter shapes for floor spot and back‑wall wash.

These specs give MetalViewKit, Three.js, or SVG renderers enough structure to produce the same stage picture from engine state.

## 4. Interchange and integration

`spec/interchange/snapshot-schema.md` outlines how to represent the engine state for logs or remote use:

- `time` in seconds,
- `camera` (azimuth, zoom, and optionally derived fields),
- `bodies` as a map from body name to position and velocity.

Hosts like FountainKit can:
- record sequences of snapshots as NDJSON for replay,
- wrap the engine behind a small OpenAPI service,
- map camera/rig parameters into MIDI CI Property Exchange facts.

The Swift package itself remains unaware of HTTP or MIDI; it exposes only Swift types and stepping APIs.

## 5. Using the engine from another package

Add TeatroStageEngine as a dependency in your `Package.swift`:

```swift
.package(url: "https://github.com/Fountain-Coach/TeatroStageEngine.git", from: "0.2.0"),
```

Then, in your target dependencies:

```swift
.product(name: "TeatroPhysics", package: "TeatroStageEngine")
```

In code:

```swift
import TeatroPhysics

let rig = TPPuppetRig()
var time = 0.0
let dt = 1.0 / 60.0

for _ in 0..<600 {
    rig.step(dt: dt, time: time)
    let snapshot = rig.snapshot()
    // map snapshot.body positions into your renderer here
    time += dt
}
```

For a custom scene, work directly with `TPWorld`, `TPBody`, and `TPDistanceConstraint`.

## 6. Status and evolution

Current status:
- Physics core and puppet rig are implemented in Swift.
- Specs for camera, physics, rig, room, style, and interchange are scaffolded under `spec/`.
- FountainKit integrates this engine via the `teatro-stage-app` demo using MetalViewKit.

Short‑term work:
- Tighten numerical parity with the original Three.js + Cannon.js demo by aligning camera and rig parameters.
- Add rig‑level tests that assert stability and rough motion envelopes over long runs.
- Provide a minimal demo inside this repo (e.g. SVG or SwiftUI+Metal) that consumes `TPPuppetRig` and `spec/` without depending on FountainKit.

The guiding principle is to keep this package small, deterministic, and well‑specified. New features (more constraints, contacts, additional Teatro rigs) should start as updates to `spec/` and only then appear in `Sources/`.

