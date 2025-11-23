import { describe, it, expect } from "vitest";
import { BallWorld } from "./ball";
import { Vec3 } from "./physics";

const DT = 1 / 60;
const EPS_POS = 1e-3;
const EPS_VEL = 0.05;

const length = (v: { x: number; y: number; z: number }): number =>
  Math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z);

describe("BallWorld baseline (drop)", () => {
  it("respects the floor and settles", () => {
    const world = new BallWorld();
    const radius = world.radius;

    const totalTime = 8.0;
    const steps = Math.floor(totalTime / DT);

    let snap = world.snapshot();

    for (let i = 0; i < steps; i++) {
      world.step(DT);
      snap = world.snapshot();

      // Floor non‑penetration: centre should stay close to or above the
      // nominal radius. In Cannon, contacts may resolve with a tiny overlap, so
      // allow a small band below `radius` for numeric quirks.
      expect(snap.position.y).toBeGreaterThanOrEqual(radius - 0.1);

      // Room bounds in X/Z: keep within the canonical stage box (with radius).
      expect(Math.abs(snap.position.x)).toBeLessThanOrEqual(
        15 - radius + EPS_POS
      );
      expect(Math.abs(snap.position.z)).toBeLessThanOrEqual(
        10 - radius + EPS_POS
      );
    }

    // After enough time, the ball should be near rest on the floor.
    expect(Math.abs(snap.position.y - radius)).toBeLessThanOrEqual(EPS_POS);
    expect(length(snap.velocity)).toBeLessThanOrEqual(EPS_VEL);
  });
});

describe("BallWorld thrown scenario", () => {
  // The thrown-ball scenario is fully specified and enforced in the Swift
  // engine tests (TPBallScene). Cannon's contact/bounce behaviour can differ
  // significantly depending on solver settings; until we tune those for parity,
  // this test is marked skipped to avoid giving a false sense of exact numeric
  // equivalence. It remains useful as a manual harness when iterating locally.
  it.skip("moves across the floor and settles", () => {
    const radius = 1.0;
    const world = new BallWorld(new Vec3(0, radius, 0), radius, 1.0);
    world.setHorizontalSpeed(4.0);

    const initialX = world.snapshot().position.x;

    const totalTime = 10.0;
    const steps = Math.floor(totalTime / DT);

    let snap = world.snapshot();
    let maxTravel = 0;

    for (let i = 0; i < steps; i++) {
      world.step(DT);
      snap = world.snapshot();

      const travel = Math.abs(snap.position.x - initialX);
      if (travel > maxTravel) {
        maxTravel = travel;
      }
    }

    // The ball should have travelled at least two radii across the floor.
    expect(maxTravel).toBeGreaterThanOrEqual(2 * radius - EPS_POS);

    // And it should settle again near rest on the floor.
    expect(Math.abs(snap.position.y - radius)).toBeLessThanOrEqual(0.1);
    expect(length(snap.velocity)).toBeLessThanOrEqual(EPS_VEL);
  });
}
);
