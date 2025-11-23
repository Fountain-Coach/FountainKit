# Teatro Stage as Instruments — Conceptual Map

This note explains how the Teatro Stage Engine (TeatroPhysics + specs) maps into FountainKit’s instrument model. The goal is to treat the Teatro stage as a small, well‑defined set of instruments instead of a one‑off demo, so hosts (MetalViewKit, web, MIDI, LLM tools) can all talk to the same conceptual surface.

The document stays at the “conceptual wiring” level: detailed physics, camera, and authoring rules remain in `Packages/TeatroPhysics/spec/**`, and HTTP/PE details live with their OpenAPI specs under `Packages/FountainSpecCuration/openapi/**`.

## 1. Layers and Ownership

Teatro Stage is shared between three layers that each own different rules:

- **Physical layer — Teatro Stage Engine**  
  Implemented in this repo as `Packages/TeatroPhysics` and mirrored in the standalone `TeatroStageEngine` package. It owns the world state, puppet rig, constraints, gravity, damping, and snapshots, following the prose specs under `Packages/TeatroPhysics/spec/**`. It is renderer‑agnostic and does not know about HTTP, MIDI, or instruments.

- **Instrument layer — FountainKit instruments**  
  Owned by FountainKit’s OpenAPI + facts + Teatro‑prompt pipeline. It decides which parts of the stage are controllable or observable, how they are named, and how they are exposed as tools (HTTP surfaces, PE properties, LLM tools). Specs for these instruments will live under `Packages/FountainSpecCuration/openapi/v1/teatro-stage-*.yml` (exact files to be added).

- **Host layer — apps and frontends**  
  Implemented today by:
  - `Packages/FountainApps/Sources/teatro-stage-app` (MetalViewKit host),
  - `Public/teatro-stage-web` (Cannon‑ES + Three.js reference),
  - future MIDI/LLM hosts that consume instrument facts via Gateway/Tools Factory.  
  Hosts draw, handle input, and call into the instrument surfaces; they do not re‑implement physics.

## 2. Stage Domain (Engine Concepts)

The engine’s domain model is the single source of truth for “what exists” on the Teatro stage:

- **World**  
  A right‑handed 3D world with gravity, damping, and a small set of constraints, implemented by `TPWorld`, `TPBody`, and `TPConstraint` in `Packages/TeatroPhysics/Sources/TeatroPhysics`. The reference timestep and integrator rules are defined in `Packages/TeatroPhysics/spec/physics/**`.

- **Puppet rig**  
  The Fadenpuppe rig — bar, torso, head, hands, feet — with bones and strings as distance constraints. The topology and layout are specified under `Packages/TeatroPhysics/spec/rig-puppet/**` and implemented by `TPPuppetRig`. The rig exposes a `step(dt:time:)` + `snapshot()` contract for hosts.

- **Stage room**  
  A three‑sided room (floor + walls + door) with fixed dimensions and layout, described in `Packages/TeatroPhysics/spec/stage-room/**`. Hosts render the room consistently across MetalViewKit, web, and any future surfaces.

- **Camera and style**  
  A canonical orthographic camera model (fixed elevation, orbit azimuth, clamped zoom) and a “paper stage” visual style (warm paper, black line art, soft lights), defined in `Packages/TeatroPhysics/spec/camera/**` and `Packages/TeatroPhysics/spec/style/**`. Implementations in MetalViewKit and web follow these documents instead of inventing their own numbers.

- **Snapshots and interchange**  
  A snapshot schema that captures time, camera state, and body positions/velocities, defined in `Packages/TeatroPhysics/spec/interchange/**`. Hosts use this schema for logs, replay, and potential remote control surfaces.

All changes to this domain start in the specs: update `spec/**` first, then align Swift (`TeatroPhysics`), web (`Public/teatro-stage-web`), and any other backends.

## 3. Instrument Set for the Teatro Stage

FountainKit instruments carve the physical stage into a small set of controllable/observable surfaces. The exact OpenAPI documents and facts will be defined separately, but the conceptual instrument set is:

### 3.1 Stage World instrument

**What**  
Controls global simulation knobs and reports high‑level health. Typical fields: gravity vector, damping, reset/seed controls, and a “run/pause” flag for stepping.

**Why**  
Gives tools a safe way to configure the stage’s physical envelope (e.g., “slightly lighter gravity”) without reaching into per‑body state or constraints.

**Where**  
Backed by the `TPWorld` state in `Packages/TeatroPhysics` and a future spec such as `Packages/FountainSpecCuration/openapi/v1/teatro-stage-world.yml`. Facts for this surface will live in FountainStore’s `agents` corpus via `openapi-to-facts` / Tools Factory.

### 3.2 Puppet instrument

**What**  
Controls rig‑level inputs (bar motion profile, scripted gestures and poses) and exposes rig pose and stability. It can answer “where is the head/torso/hands/feet?” and “is the puppet still on stage and in frame?”.

**Why**  
Separates “how the puppet moves” from “how the room or camera behaves”, so tools can script puppet motion without breaking room invariants.

**Where**  
Backed by `TPPuppetRig` and its snapshot API in `Packages/TeatroPhysics`, plus rig specs under `spec/rig-puppet/**`. The eventual OpenAPI spec would live under `Packages/FountainSpecCuration/openapi/v1/teatro-stage-puppet.yml`, with PE facts seeded into FountainStore.

### 3.3 Camera instrument

**What**  
Controls and exposes camera azimuth, zoom, and framing presets (for example “full stage” or “waist shot”), within the bounds defined by the camera spec.

**Why**  
Centralises view control and keeps camera behaviour consistent across MetalViewKit, web, and MIDI/LLM hosts. Invariants like “default framing keeps the puppet’s head visible” live here.

**Where**  
Backed by the camera model in `Packages/TeatroPhysics/spec/camera/**` and host‑specific camera abstractions in `Packages/FountainApps/Sources/teatro-stage-app` and `Public/teatro-stage-web`. A future spec such as `openapi/v1/teatro-stage-camera.yml` would define the HTTP surface.

### 3.4 Style / lighting instrument (optional)

**What**  
Exposes a constrained set of palette and lighting presets (for example “rehearsal”, “performance”, “backlight emphasis”) and small numeric tweaks (intensity, radius) that stay within the paper‑stage style.

**Why**  
Lets tools and operators adjust mood and focus without breaking the Teatro look or the geometry of the stage.

**Where**  
Backed by style and lighting parameters in the renderer hosts:
- Metal: `Packages/FountainApps/Sources/teatro-stage-app` + `Packages/FountainApps/Sources/MetalViewKit/*`,
- Web: `Public/teatro-stage-web/src/**`,  
with their bounds and defaults anchored in `Packages/TeatroPhysics/spec/style/**`.

### 3.5 Recording / playback instrument (optional)

**What**  
Manages snapshot streams and playback cursors: start/stop recording, list takes, play and scrub a take, and expose current playback time.

**Why**  
Gives tools a way to capture and replay stage motion deterministically — useful for debugging, authoring, and robot scenarios.

**Where**  
Backed by snapshot interchange rules in `Packages/TeatroPhysics/spec/interchange/**` and any host‑level recording mechanisms in `teatro-stage-app` and `teatro-stage-web`. The HTTP surface would publish “takes” in a format compatible with the snapshot schema.

## 4. Mapping Rules: Physics → Instruments

To keep the system coherent, instruments follow a small set of mapping rules when they talk to the engine:

- **Specs and engine are authoritative**  
  All geometry, physics parameters, camera maths, and style bounds come from `Packages/TeatroPhysics/spec/**` and the `TeatroPhysics` Swift module. Instruments never re‑define these numbers; they only read or adjust parameters that the engine already understands.

- **Instruments are spec‑first surfaces**  
  Each instrument gets a focused OpenAPI document under `Packages/FountainSpecCuration/openapi/v1/teatro-stage-*.yml`. The OpenAPI schema is the single source of truth for field names, types, and bounds; PE facts and tools are generated from it, not hand‑written.

- **Determinism and tests**  
  Given the same engine configuration, timestep schedule, and instrument commands, the stage evolves deterministically. Tests and robots can drive instruments (for example via Tools Factory or Gateway), record snapshots, and assert invariants over time (such as “no body leaves the room” or “camera never loses the puppet head in default mode”).

- **Snapshots as the bridge**  
  Instruments influence engine parameters and stepping; renderers, tools, and robots consume snapshots defined in `spec/interchange/**` to understand what happened. No host invents its own snapshot shape.

- **Teatro prompts live in FountainStore**  
  The human description of the “Teatro Stage” surface — which instruments exist and how they relate — is a Teatro prompt stored in FountainStore (for example under a `teatro-stage` corpus). This conceptual map informs that prompt, but the prompt text itself is generated via the Teatro Prompt Factory and seeded by a `*-seed` executable, not hand‑written in docs.

## 5. Integration Hooks in FountainKit

This conceptual map ties together several concrete pieces already present in FountainKit:

- **Engine and specs**  
  - `Packages/TeatroPhysics/*` — Swift engine and tests.  
  - `Packages/TeatroPhysics/spec/**` — canonical specs for physics, rig, room, camera, style, authoring, and interchange.

- **MetalViewKit host**  
  - `Packages/FountainApps/Sources/teatro-stage-app/*` — current MetalViewKit host for the stage.  
  - `Design/TeatroStage-MetalViewKit-Plan.md` — detailed plan for bringing the stage into MetalViewKit and wiring it as a Metal instrument surface.

- **Web host**  
  - `Public/teatro-stage-web/*` — Vite/TypeScript implementation using Cannon‑ES and Three.js, aligned with the same specs.

- **Future instrument surfaces**  
  - `Packages/FountainSpecCuration/openapi/v1/teatro-stage-*.yml` — to define the Stage World, Puppet, Camera, Style, and Recording instruments.  
  - `Tools/openapi-facts-mapping.json` — to map those specs to agent IDs for facts seeding.  
  - `Packages/FountainApps/Sources/tools-factory-server` and `Packages/FountainServiceKit-ToolsFactory` — to generate and serve instrument facts for hosts.

When adding or changing Teatro Stage instruments, update this conceptual map as you adjust specs and hosts, so readers can see the end‑to‑end picture from physics core to instruments and tools.

## 6. Authoring Playbook — Stage Engine → Instruments

This section is the short, practical checklist for “tomorrow’s self” when changing the Teatro stage or its instruments. It does not introduce new rules; it just links the existing ones into a path.

### 6.1 Change the stage behaviour (physics, rig, room, camera, style)

When you want to change how “The Teatro” actually behaves:

1. **Start in the engine specs**  
   - Edit the relevant document under `Packages/TeatroPhysics/spec/**` (physics, rig‑puppet, stage‑room, camera, style, authoring, interchange).  
   - Keep changes small and explicit; this is the single source of truth.

2. **Update the Swift engine**  
   - Adjust `Packages/TeatroPhysics/Sources/TeatroPhysics/*` to match the spec changes.  
   - Extend or fix tests under `Packages/TeatroPhysics/Tests/**` so they cover the new behaviour.

3. **Align the hosts**  
   - Metal: update `Packages/FountainApps/Sources/teatro-stage-app/*` (and related MetalViewKit nodes) so the on‑screen stage matches the new behaviour.  
   - Web: update `Public/teatro-stage-web/src/**` so the Cannon‑based demo stays visually consistent with the specs.

4. **Re‑evaluate instruments (if needed)**  
   - If the change introduces new tunable parameters or observables that instruments should expose (e.g., a new camera preset, a new rig mode), decide which instrument they belong to (Stage World, Puppet, Camera, Style, Recording) and note that in this map.

5. **Only then touch OpenAPI / facts / prompts**  
   - Once the engine and hosts are updated, adapt the relevant OpenAPI specs under `Packages/FountainSpecCuration/openapi/v1/teatro-stage-*.yml` and regenerate facts as needed.  
   - Update the Teatro prompt in FountainStore via its `*-seed` executable; do not write prompts into docs or code.

### 6.2 Add or change an instrument surface

When you want to add a new instrument or extend an existing one:

1. **Confirm the engine already supports it**  
   - The capability must already exist in `Packages/TeatroPhysics` and its specs; if it does not, follow 6.1 first.

2. **Design the surface in OpenAPI**  
   - Add or edit the appropriate spec under `Packages/FountainSpecCuration/openapi/v1/teatro-stage-*.yml`.  
   - Keep routes and schemas as thin veneers over engine state and snapshot structures.

3. **Generate and seed facts**  
   - Use `openapi-to-facts` or Tools Factory to generate PE facts for the new/changed spec and seed them into FountainStore (`Tools/openapi-facts-mapping.json` should list the mapping).

4. **Wire up hosts**  
   - Update `Packages/FountainApps/Sources/teatro-stage-app/*`, `Public/teatro-stage-web/*`, or other hosts to call the new instrument surface where appropriate.

5. **Update the Teatro prompt**  
   - Adjust the Teatro prompt for the Teatro stage (via its seeder) so it describes the new instrument surface and invariants in human language, consistent with this map.

6. **Refresh this map as needed**  
   - If you introduce a new kind of instrument or significantly change the boundaries of an existing one, add a short note to this document so future authors see the updated shape at a glance.
