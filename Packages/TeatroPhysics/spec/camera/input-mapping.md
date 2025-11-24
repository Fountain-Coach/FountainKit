The reference JS implementation defines a simple interaction model:

- Pointer drag (mouse or single‑finger touch) orbits the camera around the Y‑axis.
  - On pointer down, we enter `dragMode = 'orbit'` and record `lastX`.
  - On pointer move while dragging, we compute `dx = currentX − lastX` and update:
    - `cameraAzimuth += dx * 0.003`
  - Pointer up ends the drag.

- Mouse wheel controls zoom:
  - `deltaY > 0` → zoom out by factor `0.9`,
  - `deltaY < 0` → zoom in by factor `1.1`,
  - result is clamped to `[0.5, 3.0]`.

- Two‑finger pinch on touch devices controls zoom:
  - On pinch start, record starting distance and starting zoom,
  - On pinch move, set zoom to `startZoom * (currentDistance / startDistance)`,
  - clamp to `[0.5, 3.0]`.

The engine itself does not process events, but it assumes hosts:
- treat azimuth as unbounded (wrapping at 2π is fine),
- apply a similar sensitivity constant (0.003 radians per pixel) for orbiting,
- use a bounded, multiplicative zoom model.

When integrating with FountainKit or MetalViewKit, use this mapping as the baseline so that orbit/zoom “feel” matches the web demo.

