Teatro Stage Editor — Authoring UX Sketch
========================================

This document describes a minimal but focused authoring surface for the Teatro Stage Engine. It assumes the engine described in the other specs (physics, rig, room, camera) and adds only what is needed for humans to _shape_ a scene: see the stage, move the puppet (or actors), and mark important instants in time.

The editor is deliberately not a full 3D package or DAW. It has three main parts:
- the **stage view**,
- the **time bar**,
- and a small **inspector**.

1. Stage view
-------------

The stage view shows:
- the three‑sided room (floor + walls + door),
- the Fadenpuppe rig (drawn from `TPPuppetSnapshot`),
- optional stage actors or props on the floor.

Camera:
- Orthographic, orbiting around Y with a fixed elevation and zoom, as per `spec/camera`.
- Orbit by dragging on empty space; zoom via wheel/pinch.

Direct manipulations:
- Puppet mode:
  - The only direct handle is the **bar**. Dragging it in the stage view adjusts its position in the engine; limbs respond via physics.
  - Limbs (head/hands/feet) are not individually draggable in the default mode.
- Constellation/actor mode:
  - Floor tokens representing actors can be dragged along the floor plane.
  - Other bodies in the rig remain under physics control.

The stage view should feel like a clean, isometric drawing: no gizmo clutter, no extra grids beyond what the room already implies.

2. Time bar
-----------

Along the bottom of the window runs a simple time bar:
- indicates current time as a vertical marker,
- can be scrubbed by dragging the marker or clicking elsewhere,
- shows small tick marks at regular intervals (e.g. every second),
- shows snapshot markers (see below).

Modes:
- **Record**:
  - When record is enabled, the engine advances time in real‑time and records the motion resulting from bar or rep drags.
  - Stopping record freezes the timeline; the user can scrub and inspect.
- **Scrub**:
  - Scrubbing moves the engine to a prior or future time by replaying or interpolating from recorded data.

Snapshots:
- A snapshot is a named frame of interest.
- Creating a snapshot at the current time writes:
  - time `t`,
  - engine state (bodies and camera),
  - an optional human label (subtext, beat name).
- Snapshots appear as small markers on the time bar; clicking one jumps to that time.

The time bar does not expose generic curve editors or multitrack timelines. It is a simple strip of time with a playhead and a few important markers.

3. Inspector
------------

The inspector is a small panel attached to the stage editor (right side or as a popover). It has three responsibilities:

1. Snapshot label
   - At a snapshot, show and allow editing of a short text label (e.g. “confrontation”, “collapse”, “decision to leave”).
   - At non‑snapshot frames, show either the nearest snapshot label or an empty field.

2. Camera and time readout
   - Display current azimuth and zoom for debugging (`cameraAzimuth`, `cameraZoom`).
   - Show current time `t` in seconds or beats.

3. Puppet/stage state summary
   - A compact readout of key state: e.g. “feet wide/narrow”, “head ahead/behind torso”, or just raw body positions for debugging.
   - This is primarily for authors who want to see numeric confirmation while tuning, not for everyday use.

The inspector is intentionally small: one or two short text fields and a handful of numeric fields. The script or full Teatro prompt lives elsewhere (e.g. FountainKit’s editor), not inside this panel.

4. Typical authoring flow
-------------------------

1. The author opens the Teatro Stage Editor and orbits/zooms once to get a comfortable view of the stage.
2. They press **Record** and drag the bar to sketch a rough motion, or drag actors in constellation mode, while the engine runs at 60 Hz.
3. They stop; the time bar now contains motion across a span of time.
4. They scrub through time, dropping snapshots at interesting poses. At each snapshot, they may tweak the bar position slightly to refine the pose.
5. In the inspector, they label each snapshot with a short phrase capturing its dramatic role.
6. They export a sequence of snapshots (for storyboard frames) or leave the stage running alongside a script editor as a live reference.

The editor should make this loop fast and low‑friction. Anything that feels like “building a full animation project” is out of scope.

5. Integration expectations
---------------------------

Hosts like FountainKit that embed the Teatro Stage Engine and want authoring should:
- treat this document as the UX baseline,
- keep camera and time behaviour aligned with `spec/camera` and `spec/physics`,
- store snapshots as structured data (time + engine snapshot + label) so they can be reloaded and compared,
- avoid introducing instrument‑specific controls that would fragment the stage experience.

The long‑term goal is that whether you open the stage in a Metal app or a web demo, the basic authoring experience feels the same: orbit, drag, record, scrub, snapshot, label.
