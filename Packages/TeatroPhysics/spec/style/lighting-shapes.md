The Teatro puppet stage uses simple, abstract light shapes to suggest focus. These shapes are part of the visual contract: renderers SHOULD implement them, and when they do, they MUST follow the geometry below closely enough that scenes look recognisably “Teatro”.

- Floor spot:
  - Circular or slightly elliptical patch centred beneath the puppet.
  - Radius ≈ 4 units.
  - At least 2 concentric rings or layers fading outward (e.g. inner disc + outer ring), to avoid a hard edge.
  - Colour near `#f9f0e0` with low contrast against paper.

- Back‑wall wash:
  - Rectangle on the back wall centred behind the puppet, roughly 12 units wide and 8 units tall.
  - Positioned so its centre is near `(0, 8, -10)` in world coordinates.
  - Colour near `#f7efe0`, slightly lighter than the floor spot, with soft opacity.

- Head backlight (outline):
  - A subtle outline around the head block, drawn in a lighter line colour (e.g. `#faf2e4`).
  - Geometry closely tracks the head box extents (slightly larger to read as a halo).

Lights are not physically simulated; they are compositional cues. Renderers MUST treat them as flat shapes aligned to the room surfaces or puppet geometry, not as volumetric cones or dynamic light sources.
