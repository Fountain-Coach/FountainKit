# Teatro Style Spec (`teatro-v1`)

## 1. Projection and Camera

- Projection: **orthographic** (no perspective foreshortening).
- Primary view: **isometric** orientation:
  - Camera looks toward the origin along a direction equivalent to `(1, 1, 1)` in world space.
  - Canonical angles:
    - Azimuth around Y: `π/4` (45°)
    - Elevation above horizontal: `atan(1 / √2)` ≈ 35.264°.
- Default camera behavior:
  - Rotation: orbit around **Y-axis only**, elevation fixed.
  - Zoom: via orthographic zoom or equivalent world scaling.
  - Target: look-at point near stage center, e.g. `(0, 5, 0)`.

## 2. Color Palette

- Background (paper): `#f4ead6`
- Primary line/fill: `#111111`
- Highlight outline (for black solids): `#f4ead6`
- Secondary greys (optional): `#dddddd`, `#eeeeee`
- Accent (rare, strong): e.g. `#cc3333`.

## 3. Geometry & Line Work

- Dominant primitives: rectilinear boxes, almost no curves.
- Lines:
  - Outer frame & room edges: 2–4 px (depending on resolution).
  - Internal edges & props: 1–3 px.
- Shading:
  - Flat fills, no gradients.
  - Prefer black solids with paper-colored outlines.
  - Hatching/stippling used sparingly.

## 4. Typography

- Font: serif, print-like (`Georgia`, `Times New Roman`, or equivalent).
- Titles: uppercase, centered, generous letter spacing.
- Labels: uppercase or small caps; small, unobtrusive; positioned above or near objects.

## 5. Framing & Layout

- Outer frame rectangle with margin to viewport.
- Optional lower title band with centered title text.
- Stage: a single box room (floor + 2–3 visible walls), optional door(s).

## 6. Lighting

- Light is a dramaturgical object, not a photorealistic effect. It is drawn in the same black‑on‑paper language as everything else.
- Primary light types:
  - **Spot**: a focused cone or oval of attention, typically anchored above the stage and aimed at a floor region or actor.
  - **Wash**: a broad area of slightly lifted paper tone on floor and lower walls.
  - **Backlight**: an outline emphasis around figures or props, without visible beams.
- Rendering:
  - Spots and washes are drawn as simple polygons or ovals in a slightly lighter paper tone, with hard or gently feathered edges (no gradients).
  - Backlight is expressed via slightly thicker or lighter outlines around selected silhouettes.
  - Light shapes never introduce new colours; they modulate paper and black within the existing palette.
- Semantics:
  - Light indicates **focus** and **availability**, not physical lux. A figure in spot is “seen”; a figure in wash is “present but backgrounded”.
  - Multiple lights can overlap; where they do, outlines remain crisp and the strongest focus wins visually.

## 7. Interaction Vocabulary

- Stage rotation: drag on empty space → orbit around Y.
- Zoom: pinch (touch) or wheel (desktop) → adjust orthographic zoom.
- Actor movement: drag actor on floor plane; constrain to XZ plane.
- Puppet rig: bar motion drives puppet physically via strings and joints.
- Light editing (engine‑level):
  - Spot/wash placement: click or tap on floor/wall to create a light; drag handles to adjust footprint and direction.
  - Intensity over time is authored as a simple curve (0–1) in the engine’s timeline; GUI surfaces may expose this as part of a score view.
