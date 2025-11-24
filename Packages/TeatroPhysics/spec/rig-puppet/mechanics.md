Teatro Puppet Mechanics — Rest Pose and Invariants
==================================================

This file is normative for the Fadenpuppe rig. Implementations (Swift, TypeScript, JS demos) MUST satisfy the invariants below within explicit numeric tolerances; tests are required to enforce them.

The rig is modelled as a set of point‑mass bodies (controller, bar, torso, head, hands, feet). Boxes, silhouettes, and other shapes drawn by renderers are visual only and MUST NOT introduce additional degrees of freedom (no separate rotational state in the engine).

1. Rest pose (t = 0)
--------------------

At time `t = 0` with the controller at its neutral position, the rig MUST be in the following pose (all coordinates in world units, tolerances inclusive):

- Controller cross centre:
  - Position: `(0, 19, 0)` ± `ε_pos`.
- Bar harness centre:
  - Position: `(0, 15, 0)` ± `ε_pos`.
- Body centres:
  - Torso centre: `(0, 8, 0)` ± `ε_pos`.
  - Head centre: `(0, 10, 0)` ± `ε_pos`.
  - Left hand centre: `(-1.8, 8, 0)` ± `ε_pos`.
  - Right hand centre: `(1.8, 8, 0)` ± `ε_pos`.
  - Left foot centre: `(-0.6, 5, 0)` ± `ε_pos`.
  - Right foot centre: `(0.6, 5, 0)` ± `ε_pos`.

Where `ε_pos = 0.05` in tests (5 cm in a 1 m = 1 unit interpretation).

The floor plane is at `y = 0`. Both feet start above the floor (`y = 5`) and are each connected to it by a ground constraint; under gravity they may contact the floor but MUST NEVER penetrate it.

2. String rest lengths and stretch band
---------------------------------------

At rest, the following string rest lengths are implied by the positions above:

- `controller ↔ bar` rest length ≈ 4.
- `controller ↔ handL` rest length ≈ 11.
- `controller ↔ handR` rest length ≈ 11.
- `bar ↔ head` rest length ≈ 5.

The engine MUST initialise distance constraints for these pairs with rest lengths computed from the rest pose, not hard‑coded magic numbers, so that changing the pose in spec/geometry automatically updates the strings.

Under the canonical drive profile (section 4), with world parameters from `spec/physics/world-and-timestep.md` and a fixed timestep `dt ≈ 1/60`, the following MUST hold for all simulation steps up to at least `t = 10` seconds:

- For each string, let `L0` be its rest length at `t = 0` and `L(t)` its length at time `t`.
- Stretch constraint:
  - `0.8 · L0 ≤ L(t) ≤ 1.2 · L0` for all `t` in the test horizon.
- No slack:
  - Strings MUST NOT invert or collapse: `L(t)` MUST remain strictly positive and MUST NOT fall below `0.5 · L0`.

Tests in Swift and TypeScript MUST sample representative timesteps and assert these bounds. If future rig changes require a different band, this file and the tests MUST be updated together.

3. Geometric and structural invariants
--------------------------------------

For all times `t`, the following inequalities MUST hold (within a small epsilon determined by tests):

- Vertical ordering:
  - `controller.y > bar.y > head.y > torso.y > footL.y ≥ 0` and `footR.y ≥ 0`.
- Symmetry at rest:
  - In neutral pose (`t = 0` and controller at `(0, 19, 0)` within `ε_pos`), the x‑positions of symmetric limbs satisfy:
    - `handL.x ≈ −handR.x` within `ε_sym = 0.05`,
    - `footL.x ≈ −footR.x` within `ε_sym = 0.05`,
    - `head.x ≈ torso.x ≈ 0` within `ε_sym`.
- Foot corridor:
  - During motion driven solely by the canonical controller function, feet stay within a horizontal corridor:
    - `|footL.x| ≤ 2` and `|footR.x| ≤ 2.0`.
- Torso support:
  - Projecting positions onto the X‑axis (the rig is centred at `z = 0`), the torso centre MUST remain over the feet within a margin:
    - `min(footL.x, footR.x) − 0.5 ≤ torso.x ≤ max(footL.x, footR.x) + 0.5`.
- Head under controller:
  - The head MUST remain under the controller’s vertical projection with limited lateral drift:
    - `|head.x − controller.x| ≤ 3.0`.

Tests MUST explicitly assert these relationships for both the rest pose and for motion over at least one second of simulated time.

4. Floor contact invariants
---------------------------

Ground constraints MUST ensure:

- For all steps, `footL.y ≥ 0` and `footR.y ≥ 0` within a numeric tolerance of `1e‑6`.
- When a foot is at the floor (`y = 0`) and only gravity acts between steps, the next integration step MUST NOT move it below the floor; after applying the ground constraint, the vertical velocity component of that foot MUST be non‑negative (no continued sinking).
- The rig MUST attach `TPGroundConstraint` (or its equivalent) at least to both feet. Other bodies MAY use the same constraint type, but feet are the canonical point of contact with the floor.

5. Controller drive profile vs. host input
------------------------------------------

The engine distinguishes between:

- A canonical drive profile used for tests and demos.
- Host‑controlled input, where the controller trajectory may come from user interaction or another system.

The canonical drive function is:

```text
controller.x(t) = 2.0 * sin(0.7 * t)
controller.y(t) = 19 + 0.5 * sin(0.9 * t)
controller.z(t) = 0
```

For the canonical profile:

- `|controller.x(t)| ≤ 2.0` for all `t`.
- `18.5 ≤ controller.y(t) ≤ 19.5` for all `t`.
- `controller.z(t) = 0` for all `t`.

The Swift and TypeScript reference engines MUST expose this profile as their default when no external controller input is provided, so that tests can compare positions numerically. Hosts that wish to drive the controller explicitly MAY override the controller position each frame instead of using this function, but MUST then still respect the structural invariants above.

6. Test expectations
--------------------

The Swift and TypeScript test suites MUST, at a minimum:

- Rest pose:
  - Construct a rig, sample `snapshot()` at `t = 0` without stepping, and assert that all body positions match the rest pose coordinates with tolerance `ε_pos` and `ε_sym`.
- Motion under canonical drive:
  - Advance by one second of simulated time with the drive function and assert:
    - `controller.x(t)` is no longer zero but still within `[-2, 2]`.
    - Vertical ordering still holds.
    - Foot corridor, torso support, and head‑under‑controller constraints remain satisfied.
- String band:
  - Sample string lengths at several timesteps up to at least `t = 1` second and assert that the stretch and slack bounds from section 2 hold.
- Floor contact:
  - When starting with feet below the floor and stepping once, their y‑positions are clamped to `≥ 0` and do not go negative on subsequent steps under gravity.

Any change to the rig, constraints, masses, or controller semantics that violates these expectations MUST be preceded by an update to this document and accompanied by matching changes in the Swift and TypeScript test suites.
