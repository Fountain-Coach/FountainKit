The puppet’s proportions mirror the Three.js demo, which uses box bodies of various sizes. In the Swift engine we represent bodies as points, but the same dimensions are used by renderers to draw box outlines.

Approximate body extents (Three.js reference):
- Controller cross: visual width ~10, depth ~6, centred around `(0, 19, 0)` inside the overhead rig. In physics, this is a point body at `(0, 19, 0)`; renderers draw the cross around that point.
- Bar: width 10, height 0.2, depth 0.2, centred at `(0, 15, 0)`.
- Torso: width 1.6, height 3, depth 0.8, centred at `(0, 8, 0)`.
- Head: width 1.1, height 1.1, depth 0.8, centred at `(0, 10, 0)`.
- Hands: width 0.4, height 2.0, depth 0.4, centred near `(-1.8, 8, 0)` and `(1.8, 8, 0)`.
- Feet: width 0.5, height 2.2, depth 0.5, centred near `(-0.6, 5, 0)` and `(0.6, 5, 0)`. In the physics engine, the foot bodies use these dimensions as box colliders: when colliding with the stage floor at `y = 0`, the engine clamps the bottom face of each box (centre.y − halfHeight) to stay at or above the floor.

Masses:
- Controller cross: light mass (~0.1); driven directly by the engine or user input, strings transmit its motion to bar and hands.
- Bar: light mass (~0.1) so it responds smoothly to the controller but influences the rig.
- Torso: heavier (~1.0), the main inertia of the puppet.
- Head: medium (~0.5).
- Hands: light (~0.3).
- Feet: medium (~0.4).

Exact numbers used in `TPPuppetRig` should be kept in sync with this file. Adjustments for feel (e.g. slightly heavier feet) are allowed but must be recorded here.
