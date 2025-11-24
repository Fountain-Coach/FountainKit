Constraint model:
- All constraints conform to `TPConstraint` and implement `solve(dt:)`.
- Constraints operate in world space and may directly adjust body positions to reduce error; velocity is indirectly affected because the next integration step will react to position changes.
- The world update order is:
  1. Integrate gravity and damping into velocities and positions.
  2. Apply all constraints once in sequence.
  Implementations MUST preserve this ordering so that constraint behaviour matches the tests.

`TPDistanceConstraint`:
- Fields:
  - `bodyA`, `bodyB`: the two bodies being constrained.
  - `restLength`: desired distance between their positions.
  - `stiffness`: scalar in `(0, 1]` controlling how aggressively the constraint corrects error.
- Behaviour:
  - Let `delta = bodyB.position − bodyA.position`, `dist = |delta|`.
  - If `dist` is near zero, do nothing.
  - Compute `diff = (dist − restLength) / dist`.
  - Compute correction vector `impulse = delta * (0.5 * stiffness * diff)`.
  - Move bodies:
    - if `bodyA.invMass > 0`, `bodyA.position += impulse`,
    - if `bodyB.invMass > 0`, `bodyB.position -= impulse`.
- This keeps the distance between bodies close to `restLength` without being perfectly rigid; the exact tolerance depends on `stiffness`, `dt`, and damping. Tests define acceptable bands for specific rigs (see `spec/rig-puppet/mechanics.md`).

`TPGroundConstraint`:
- Fields:
  - `body`: the body that should not pass below the floor.
  - `floorY`: vertical position of the stage floor (default `0`).
- Behaviour (normative):
  - Constraints of this type MUST be applied after velocity/position integration and after any other constraints that might move the body downward during the step.
  - When the body has a box collider (`halfExtents.y > 0`), define the bottom face height as `bottomY = body.position.y − halfExtents.y`. Otherwise, treat the body as a point with `bottomY = body.position.y`.
  - If `bottomY` is less than `floorY`, compute the penetration depth `pen = floorY − bottomY` and lift the body by that amount: `body.position.y += pen`.
  - If the clamp was applied and `body.velocity.y` is negative, set `body.velocity.y = 0` so the body does not immediately sink again on the next step under gravity alone.
- This models a simple non‑penetration contact between axis‑aligned boxes (or points) and a horizontal floor with a perfectly inelastic vertical response; it does not model friction or tangential impulses. In the puppet rig, at minimum both feet MUST be attached to ground constraints so their bottom faces never pass below the stage floor.

Future constraints:
- Hinges, point‑to‑point joints with anchors, and more advanced contacts can be added, but each MUST be specified here before implementation.
- New constraints should remain small and focused, and MUST be motivated by a concrete Teatro rig requirement (e.g. door hinges, backline props).
