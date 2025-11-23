import { describe, it, expect } from "vitest";
import { Body, Vec3, World, DistanceConstraint, GroundConstraint } from "./physics";

describe("Vec3", () => {
  it("adds and scales correctly", () => {
    const v = new Vec3(1, 2, 3);
    v.add(new Vec3(1, -1, 0)).scale(2);
    expect(v).toEqual({ x: 4, y: 2, z: 6 });
  });
});

describe("World", () => {
  it("applies gravity so bodies fall down", () => {
    const world = new World();
    const b = new Body(new Vec3(0, 0, 0), 1);
    world.addBody(b);
    world.gravity = new Vec3(0, -10, 0);
    world.linearDamping = 0;

    world.step(0.1);
    expect(b.position.y).toBeLessThan(0);
  });

  it("keeps distance constraints near rest length", () => {
    const world = new World();
    const a = new Body(new Vec3(0, 0, 0), 1);
    const b = new Body(new Vec3(2, 0, 0), 1);
    world.addBody(a);
    world.addBody(b);
    const rest = 1;
    world.addConstraint(new DistanceConstraint(a, b, rest, 1));

    for (let i = 0; i < 20; i++) {
      world.step(0.016);
    }
    const dist = Vec3.subtract(b.position, a.position).length();
    expect(Math.abs(dist - rest)).toBeLessThan(0.2);
  });

  it("keeps body above floor with GroundConstraint", () => {
    const world = new World();
    const body = new Body(new Vec3(0, -1, 0), 1, new Vec3(0.5, 0.5, 0.5));
    world.addBody(body);
    world.addConstraint(new GroundConstraint(body, 0));
    for (let i = 0; i < 10; i++) {
      world.step(0.016);
    }
    expect(body.position.y).toBeGreaterThanOrEqual(-1e-3);
  });

  // We rely on Cannon's contact response for velocity changes at the floor; no additional
  // guarantees beyond non‑penetration are asserted here.
});
