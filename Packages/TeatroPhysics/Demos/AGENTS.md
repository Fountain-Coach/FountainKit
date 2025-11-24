The `Demos/` tree holds reference implementations of the Teatro Stage Engine. They are not the spec and not the authoritative source of truth — that role belongs to the documents under `spec/` and the Swift engine — but they show how the same stage behaves in other stacks.

- `threejs-fadenpuppe/` contains the original JavaScript / Three.js + Cannon.js demos (`demo1.html`, `demo2.html`) that inspired this engine. Keep them visually in sync with the Swift engine and specs, but treat the Swift side as the primary authority when behaviour changes.

When making changes to rig, camera, or room behaviour, update `spec/` and the Swift implementation first, then adjust the demos so they continue to match.

For how these demos relate to FountainKit’s instrument model (Stage World, Puppet, Camera, etc.) and hosts like `teatro-stage-app` and `teatro-stage-web`, see `Design/TeatroStage-Instruments-Map.md` in the FountainKit repo.
