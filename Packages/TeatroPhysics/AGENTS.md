TeatroStageEngine is the canonical engine for the Teatro puppet stage. The Swift module `TeatroPhysics` currently holds a small, in‑house rigid‑body solver and puppet rig; the `spec/` tree describes camera, room, rig, style, authoring UX, and interchange in prose; and the `Demos/` tree shows how the same stage behaves in Three.js. Other repos (FountainKit, web frontends, tools) should treat the *specs* in this package as the source of truth and keep their implementations aligned with those documents.

Important: the Swift solver in `TeatroPhysics` is a **minimal reference backend**, not a full professional physics engine. The web implementation already runs on Cannon‑ES, and the physics spec includes a plan for integrating Bullet as an optional macOS backend (`spec/physics/bullet-integration-report.md`). Future work should move heavy stage demos toward these industrial‑strength backends while keeping the Swift solver small, deterministic, and spec‑driven.

Working rules for agents:
- Spec‑first: when behaviour changes, update the relevant document under `spec/` (camera, physics, rig‑puppet, stage‑room, style, authoring, interchange) and then adjust Swift and JS implementations or backends (Cannon/Bullet) to match. The Three.js demos are historical references only.
- Deterministic physics (Swift backend): keep the pure‑Swift integrator semi‑implicit Euler with explicit gravity and damping (`spec/physics/world-and-timestep.md`). Do not introduce randomness in the Swift core. Backends like Cannon or Bullet may have their own numeric quirks but should still respect the high‑level invariants in the specs.
- Narrow constraint set: constraint types are explicit (`TPDistanceConstraint` today). Add new constraints only when a real Teatro use‑case requires them, and document them under `spec/physics/constraints.md` before coding.
- Tests as guardrails: extend the test suite beyond unit math to cover rig behaviour (energy not exploding, strings staying near rest length, rig remaining within reasonable bounds over long runs). Treat failing tests as blockers for visual tweaks.

Implementation norms:
- Prefer small value types (`TPVec3`) and thin reference types (`TPBody`, `TPPuppetRig`) only where identity is required.
- Keep the Swift package renderer‑agnostic and reusable; visual choices belong in demos and host apps.
- Maintain the mapping between Swift, TS, and specs: field names and units must line up so snapshots can flow between the engine, web demo, and FountainKit without adapters that “fix” mismatches on the fly.

For the higher‑level mapping between this engine and FountainKit’s instrument surfaces (Stage World, Puppet, Camera, etc.), see `Design/TeatroStage-Instruments-Map.md` at the repo root. That document explains how hosts and specs should carve this physics core into OpenAPI/PE instruments without changing the underlying rules.
