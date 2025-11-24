World model:
- Right‑handed coordinates: `x` right, `y` up, `z` forward (toward the viewer when camera azimuth is 0).
- Units are abstract but follow the Three.js demo’s scale (floor ≈ 30 units wide, walls 20 units high, puppet around 10 units tall).
- Time is measured in seconds.

Integration:
- The engine uses a semi‑implicit Euler integrator:
  1. For each body with `mass > 0`, compute acceleration from gravity: `a = gravity * invMass`.
  2. Update velocity: `v = (v + a * dt) * (1 − linearDamping)`.
  3. Update position: `p = p + v * dt`.
- After integration, each constraint’s `solve(dt:)` method is invoked once per step to correct positions.

Timestep:
- Reference timestep is `dt = 1/60` (matching the JS `world.step(1/60, dt, 3)` pattern).
- Hosts may pass variable `dt` as long as it remains in a reasonable band (e.g. `[1/120, 1/30]`); for stability, clamping `dt` in the host is recommended.
- The engine itself does not clamp or substep; if tighter stability is required, a host may call `step(dt:)` multiple times with smaller `dt` intervals.

Gravity and damping:
- Default gravity is `(0, -9.82, 0)` — Earth‑like.
- `linearDamping` is a scalar in `[0, 1)` applied each step to velocities; it approximates air drag and internal friction.

Determinism:
- For a given sequence of `step(dt:)` calls on a given world, results are deterministic.
- There is no built‑in randomness; any stochastic behaviour must be introduced explicitly at a higher level.

