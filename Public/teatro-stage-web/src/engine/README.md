This folder will host the TypeScript port of the TeatroStageEngine core:

- `Vec3`, `Body`, `World`, `Constraint` — matching the Swift `TPVec3`, `TPBody`, `TPWorld`, `TPConstraint`.
- `PuppetRig` — matching `TPPuppetRig`, built from the same dimensions and masses described under `TeatroStageEngine/spec/rig-puppet`.

The goal is to keep these types structurally aligned with the Swift engine so that snapshots and behaviour stay in sync across implementations.

