The canonical Teatro room for the puppet stage is a simple three‑sided box:

- Floor: rectangle 30 × 20 units in the XZ plane, centered at the origin.
  - X ranges from −15 to +15.
  - Z ranges from −10 (back) to +10 (front).
  - The floor lies at `y = 0`.

- Back wall: rectangle 30 × 20 at Z = −10.
  - X ranges from −15 to +15.
  - Y ranges from 0 to 20.

- Left wall: rectangle 20 × 20 at X = −15.
  - Z ranges from −10 to +10.
  - Y ranges from 0 to 20.

- Right wall: rectangle 20 × 20 at X = +15.
  - Z ranges from −10 to +10.
  - Y ranges from 0 to 20.

Door (on right wall, Three.js reference):
- A smaller rectangle cut into the right wall, roughly 8 units high, positioned toward the back:
  - X fixed at +15.
  - Z from −4 to −1.
  - Y from 0 to 8.

The puppet rig origin is near the center of the floor at `(0, 0, 0)`. Renderers MUST draw edges for floor and walls using these coordinates to match the engine’s world, and SHOULD render the door cut‑out on the right wall using the dimensions above so the stage reads as a Teatro room rather than a generic crate.

Rest‑pose alignment (normative):
- The puppet rest pose from `spec/rig-puppet/mechanics.md` places the feet at `y = 5` and the head at `y = 10`, with the rig bar at `y = 15` and the controller at `y = 19`.
- Renderers MUST draw the floor exactly at world `y = 0` and use the same room coordinates, so that:
  - when the feet contact the floor under gravity, their centres lie visually on the drawn floor line, and
  - the head remains clearly below the rig bar and below the top of the room walls.
