This directory owns the physics and solver semantics: world coordinates, gravity, timestep, and constraint behaviour. The Swift implementation (`TPWorld`, `TPBody`, `TPConstraint`) must follow the rules described here; demos and hosts should treat this as the authoritative description of the Teatro Stage Engine’s physics.

Files in this folder cover:
- the world and timestep model (`world-and-timestep.md`),
- the definition and expected behaviour of each constraint type (`constraints.md`).

When you change integrator details, gravity, or constraint behaviour, update this spec alongside the code and tests.

