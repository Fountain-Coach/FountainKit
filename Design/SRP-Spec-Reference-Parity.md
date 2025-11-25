**Spec + Reference Parity (SRP) — Working Method**

Goal: keep Three.js + Cannon.js work deterministic and trustworthy by coding only against the spec and a known reference demo, and proving parity before every commit.

Principles
- Spec + reference first: restate acceptance before coding (rig/camera/visual/physics parity with the canonical Three.js + Cannon demo and TeatroStageEngine specs).
- Extract, don’t guess: lift all numbers (masses, lengths, frustum, colors) directly from spec/demo into shared constants; no ad-hoc tweaks.
- Parity tests first: maintain two checks and run them before committing:
  - State parity: run N frames, dump body positions, compare to a known-good snapshot from the reference.
  - Visual parity: render a baseline PNG and diff (camera/frustum/lines/colors).
- Single loop discipline: one loop per frame — step Cannon at fixed dt (with accumulator), sync meshes, render. No per-frame object rebuilds.
- Pre-commit rule: no commits unless parity checks pass locally. If they fail, fix first. No partial pushes.
- Small, checked commits: keep changes minimal and self-contained, validated by the parity checks.

How to apply (Teatro Stage Web)
- Acceptance: matches `threejs-fadenpuppe/demo1.html` and TeatroStageEngine specs (rig geometry/motion, camera/frustum, stage layout, visuals).
- Constants: extract from demo/specs into engine constants; use them everywhere (rig builder, camera, visuals).
- Checks: add `npm run parity` that runs state snapshot diff + baseline render diff; block commits until green.
- Loop: Cannon step at fixed dt (1/60) with accumulator → update Three meshes → render.
