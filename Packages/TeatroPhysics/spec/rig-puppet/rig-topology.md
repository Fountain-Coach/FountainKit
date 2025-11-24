The Teatro puppet rig is a small tree of rigid bodies connected by distance constraints. Bodies:

- `controller` — the controller cross the puppeteer holds, running inside the overhead rig.
- `bar` — the crossbar immediately above the head.
- `torso` — main body segment.
- `head` — head block above torso.
- `handL`, `handR` — left and right hands/forearms.
- `footL`, `footR` — left and right feet/legs.

Skeleton constraints:
- `torso ↔ head` — keeps head above torso.
- `torso ↔ handL`, `torso ↔ handR` — keep hands attached near shoulders.
- `torso ↔ footL`, `torso ↔ footR` — keep feet attached near hips.

String constraints:
- `controller ↔ bar` — central string from controller cross to bar.
- `controller ↔ handL`, `controller ↔ handR` — strings from cross ends to hands.
- (optionally) `bar ↔ head` — a reinforcing string from bar to head to keep posture upright.

All constraints are distance constraints with rest lengths derived from initial positions. Visual “strings” in renderers should be drawn between the corresponding body centers or anchor points, using the current positions from the physics snapshot.
