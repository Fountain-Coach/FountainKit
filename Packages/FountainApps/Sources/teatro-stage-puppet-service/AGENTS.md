Teatro Stage Puppet Service
===========================

This executable exposes the Teatro Stage puppet rig over HTTP as an instrument‑oriented
service. It provides a thin wrapper around `TeatroPhysics.TPPuppetRig` that implements
the `teatro-stage-puppet.yml` spec under `Packages/FountainSpecCuration/openapi/v1`.

What
- Service name: `teatro-stage-puppet-service`.
- Spec: `Packages/FountainSpecCuration/openapi/v1/teatro-stage-puppet.yml`.
- Agent id: `fountain.coach/agent/teatro-stage-puppet/service` (see `Tools/openapi-facts-mapping.json`).
- Backend: `TPPuppetRig` and its snapshot API in `TeatroPhysics` (from `TeatroStageEngine`).

Why
- Gives tools and FountainAi a concrete HTTP surface for the Teatro puppet:
  pose, gestures, and coarse health invariants.
- Keeps behaviour source‑of‑truth in `TeatroPhysics` + its tests; this service
  only reads that state and serialises it into the OpenAPI schema.

How
- Run: `swift run --package-path Packages/FountainApps teatro-stage-puppet-service`.
- Port: `TEATRO_STAGE_PUPPET_PORT` or `PORT` (default `8093`).
- Routes:
  - `GET /openapi.yaml` – serves `teatro-stage-puppet.yml`.
  - `GET /puppet/pose` – returns `PuppetPose` built from `TPPuppetRig.snapshot()`.
  - `POST /puppet/reset` – reinitialises the rig to its rest pose.
  - `GET /puppet/gestures` – returns a small static gesture catalogue.
  - `POST /puppet/gestures/play` – accepts a gesture id and returns an `ActiveGestureState`.
  - `GET /puppet/health` – computes `PuppetHealth` from the current rig state.

Implementation notes
- The service owns a single long‑lived `TPPuppetRig` instance and a simulation time
  counter inside an actor (`PuppetEngine`) to keep updates serialised.
- `GET /puppet/pose` currently advances the rig by a small fixed timestep before
  sampling pose, to give a simple animation when polled repeatedly.
- Health flags (`feetOnStage`, `withinStageBounds`, `stringsStable`) mirror the
  invariants exercised in `PuppetRigMechanicsTests` inside `TeatroStageEngine`.

