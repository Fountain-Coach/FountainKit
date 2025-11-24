Bullet‑Class Physics in Swift — Bullet Research & Plan
======================================================

Context
-------

The Teatro Stage Engine currently uses a small, in‑house solver in Swift (`TeatroPhysics`) and a Cannon‑ES–backed implementation in the web demo. This keeps the Swift side lightweight and spec‑driven, but it also means the macOS/Metal implementation diverges from the behaviour of mature engines like Cannon or Bullet, especially around contact, joints, and stability.

You asked explicitly to stop “guessing” and to consider a professional engine instead of evolving our own solver indefinitely. The research you provided summarises how Bullet can be consumed from Swift, either through existing bindings or a custom wrapper. This report digests that research, critiques the options, and sketches a plan that fits FountainKit’s constraints.

Naming note: we treat Bullet as a reference for “Bullet‑class” physics but avoid exposing the brand in user‑visible surfaces to keep the language non‑violent. UI copy and prompts should use neutral terms like “physics backend” or “high‑fidelity physics” even if the underlying backend is Bullet.

Summary of integration options
------------------------------

The research breaks the Swift/Bullet landscape into three broad approaches:

1. **Reuse an existing Swift wrapper.**  
   There are several projects that already talk to Bullet from Swift (PhyKit/PhysicsKit, SwiftBullet, BulletSwift, Swift‑CBullet). They all follow the same basic pattern: hide Bullet behind a C or Obj‑C API, then expose a Swifty façade.

2. **Roll a custom C shim + Swift façade.**  
   This is the classic and robust interoperability path:
   - build Bullet as a static/shared library;
   - write a small C API (opaque pointers for world and bodies, flat functions for create/step/destroy);
   - expose that API as a SwiftPM module (system library or vendored modulemap);
   - write a Swift wrapper that owns the lifecycle and presents value‑centric types.

3. **Use Swift’s experimental C++ interop.**  
   Swift 5.9+ can call some C++ APIs directly. In theory, we could import Bullet headers straight into Swift and wrap `btWorld`, `btRigidBody`, etc., without a C shim. In practice, Bullet is a large, older C++ codebase and may exercise corners of C++ that Swift’s interop does not yet cover cleanly.

Critique — fit with Teatro and FountainKit
------------------------------------------

The key question is not “can Swift call Bullet?” (it clearly can), but “how does Bullet fit into our architecture and guarantees?”

**Existing wrappers.**  
Pros: very fast path to a working prototype; someone else has already fought the build and header wars. Cons: APIs tend to be shaped for SceneKit/SpriteKit or generic game engines rather than for Teatro’s stage‑centric semantics. Pulling one of these in wholesale would give us a lot of surface area we do not want to expose to Codex or to the rest of FountainKit. We would also inherit their update cadence and build assumptions.

**Custom C shim + Swift façade.**  
This is the most controlled option and aligns best with the “spec‑first, narrow seams” philosophy in `AGENTS.md`:
- the C shim can define a very small, Teatro‑shaped API (world, floor, box/plane shapes, a handful of constraint types);
- the Swift façade can hide Bullet completely behind Teatro types (`TPWorld`, `TPRigidBody`, `TPJoint`) rather than leaking Bullet classes into the rest of the repo;
- we can version and test the shim separately, and later swap Bullet out if we ever need to without rewriting host code.

The cost is engineering effort: we must own the shim, the build configuration, and the packaging for all target platforms we care about.

**Direct C++ interop.**  
Tempting for small libraries, but risky for a mature, macro‑heavy codebase like Bullet. It would also entangle the Swift code more tightly with Bullet’s exact headers and types, making it harder to keep our own API surface small and stable. Given how much we value explicit, documented seams, the C shim is a safer and more maintainable choice.

**Cross‑language parity.**  
One of Teatro’s design goals is that Swift and web should agree on scene semantics. After the recent change, the web uses Cannon‑ES while Swift uses a small deterministic solver. Introducing Bullet on Swift would give us *three* behaviours (Cannon, Bullet, in‑house). To avoid chaos, we should either:
- treat Bullet and Cannon as “professional backends” and align our high‑level spec around the behaviours they share (contact, joints, gravity), or
- treat Bullet as an internal reference and keep the Swift solver as the canonical, spec‑matching engine for now, only using Bullet for exploratory or high‑fidelity tools.

Either way, the Bullet API we expose to Swift must be narrow and shaped like `TeatroPhysics`, not like a generic game engine.

Implementation plan — Bullet as an optional backend
---------------------------------------------------

The recommendation is to introduce Bullet as an **optional backend** for the stage on macOS, not as a hard dependency for all of FountainKit, and to keep the current Swift solver as the minimal reference implementation. The stages are:

1. **Define the backend boundary in spec.**  
   Extend `spec/physics/world-and-timestep.md` with a short section that distinguishes:
   - the *logical* world model (bodies, shapes, constraints, floor, timestep); and
   - the *solver backend* (in‑house, Bullet, or Cannon).  
   Make it explicit that the host (“Teatro Stage Engine”) talks to an abstract physics backend, not to Bullet/Cannon directly.

2. **Create a Bullet shim module (separate repo).**  
   Under the Fountain Coach org, add a small repo (for example `TeatroBulletShim`) that:
   - builds Bullet as a static library for macOS (and iOS if needed) using CMake;
   - provides a C header like `BulletShim.h` with opaque types `btWorldRef`, `btRigidBodyRef`, and functions such as:
     - `BulletCreateWorld`, `BulletStepWorld`, `BulletDestroyWorld`;
     - `BulletCreateRigidBodyBox`, `BulletCreateFloorPlane`;
     - `BulletAddDistanceConstraint`, `BulletAddHinge`, etc.;
   - implements these in C++ using Bullet’s APIs;
   - exposes them as a SwiftPM system library (`CBulletShim`) via a modulemap.

3. **Add a Swift façade package.**  
   In `Packages/TeatroPhysics` or a sibling package, add a target (for example `TeatroPhysicsBulletBackend`) that:
   - depends on `CBulletShim`;
   - wraps the C API in Swifty types (`BulletWorld`, `BulletBody`, `BulletJoint`);
   - offers a protocol such as `TPPhysicsBackend` that mirrors the existing `TPWorld` methods (add body, add constraint, step, snapshot).

4. **Make `TeatroPhysics` pluggable.**  
   Refactor the current in‑house `TPWorld` so that:
   - it can delegate to a backend that conforms to `TPPhysicsBackend`;
   - the existing pure‑Swift implementation remains the default backend;
   - for macOS stage demos, we can opt into the Bullet backend at construction time (e.g. `TPWorld(backend: .bullet)`).

5. **Align tests and expectations.**  
   Extend the test suite so that:
   - core invariants (rest pose, floor non‑penetration, basic joints) are expressed against the `TPPhysicsBackend` interface;
   - we can run the same invariants against both the pure‑Swift backend and the Bullet backend, acknowledging that numeric trajectories will differ but contact and ordering constraints must still hold.

6. **Evaluate parity with Cannon.**  
   For the puppet stage, run a small battery of comparison scripts:
   - drive the same controller profile in Cannon (web) and Bullet (Swift);
   - log key frame snapshots (positions of bar/head/hands/feet, contact events);
   - compare for qualitative parity (no obvious tunnelling, similar swing and settling).  
   Use these observations to refine the spec where needed (for example, how much stretch or bounce we consider acceptable in strings under realistic motion).

7. **Document usage and limits.**  
   Once the Bullet backend is usable, add a short “Backend options” section to `Packages/TeatroPhysics/AGENTS.md` explaining:
   - when to use the pure‑Swift backend (tests, portability, deterministic snapshots);
   - when to enable Bullet (high‑fidelity stage demos, rich joint constraints);
   - and the fact that the web still uses Cannon, so Bullet and Cannon are treated as *reference backends* under a common Teatro spec, not as exact bitwise mirrors.

This path accepts your requirement to “wrap a professional engine” without handing Bullet’s entire API surface to the rest of the repo. We keep our spec and public Swift API narrow and Teatro‑specific, but we let Bullet do the heavy lifting for contact and joints where it matters most: the live stage on macOS.
