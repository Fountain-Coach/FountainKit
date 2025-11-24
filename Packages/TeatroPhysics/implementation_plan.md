TeatroPhysics brings the Fadenpuppe and related Teatro rigs into a small, testable Swift physics core. The plan is to mirror the behaviour of `Design/teatro-engine-spec/demo1.html` (Three.js + Cannon) closely enough that MetalViewKit and other renderers can treat this engine as the single source of truth.

Phase 1 — Core types and integrator
- Define `TPVec3` (minimal 3D vector), `TPBody` (position, velocity, mass), and `TPWorld` (collection of bodies + global parameters such as gravity and damping).
- Implement a simple semi‑implicit Euler integrator: accumulate forces, integrate velocity, then integrate position with a fixed timestep (e.g. 1/60 s).
- Add tests to verify that free‑fall under gravity behaves as expected and that damping stabilises motion.

Phase 2 — Constraints (distance and point‑to‑point)
- Introduce a `TPConstraint` protocol with a `solve(dt:)` method that can apply impulses or position corrections to attached bodies.
- Implement `TPDistanceConstraint` (fixed or soft rope length) and `TPPointConstraint` (two anchor points that want to coincide).
- Add tests to confirm that constraints keep two bodies within a tolerance of the target distance over many steps.

Phase 3 — Puppet rig model
- Define a `TPPuppetRig` that wires up bodies for bar, torso, head, hands, and feet, plus ground plane and strings.
- Reproduce the dimensions and attachment points from `demo1.html` so that the Metal and JS demos share coordinates.
- Implement a simple “drive bar” helper to move the crossbar over time (sway + up/down) as in the Three.js demo.

Phase 4 — Integration hooks and snapshots
- Add snapshot helpers to expose rig state as a list of body transforms per frame for renderers.
- Provide a deterministic `step(dt:)` API so callers (MetalViewKit, tests, tools) control the clock explicitly.
- Avoid any rendering or platform assumptions; this package stays pure Swift, no AppKit/Metal imports.

Phase 5 — Extraction and GitHub packaging
- Once the puppet rig behaves correctly in FountainKit, extract this package into a standalone GitHub repo under the Fountain Coach org with the same public API.
- Switch in‑repo references to use `.package(url:)` while keeping this directory as a mirror or subtree as long as needed.

