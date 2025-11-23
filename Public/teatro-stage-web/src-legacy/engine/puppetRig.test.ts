import { describe, it, expect } from "vitest";
import { PuppetRig } from "./puppetRig";
import { Vec3 } from "./physics";

const EPS_POS = 0.05;
const EPS_SYM = 0.05;

function length(a: Vec3, b: Vec3): number {
  return Vec3.subtract(b, a).length();
}

describe("PuppetRig", () => {
  it("matches the spec rest pose at t=0", () => {
    const rig = new PuppetRig();
    const s = rig.snapshot();

    // Positions as specified in spec/rig-puppet/mechanics.md
    expect(s.controller.x).toBeCloseTo(0, EPS_POS);
    expect(s.controller.y).toBeCloseTo(19, EPS_POS);
    expect(s.controller.z).toBeCloseTo(0, EPS_POS);

    expect(s.bar.x).toBeCloseTo(0, EPS_POS);
    expect(s.bar.y).toBeCloseTo(15, EPS_POS);
    expect(s.bar.z).toBeCloseTo(0, EPS_POS);

    expect(s.torso.x).toBeCloseTo(0, EPS_POS);
    expect(s.torso.y).toBeCloseTo(8, EPS_POS);
    expect(s.torso.z).toBeCloseTo(0, EPS_POS);

    expect(s.head.x).toBeCloseTo(0, EPS_POS);
    expect(s.head.y).toBeCloseTo(10, EPS_POS);
    expect(s.head.z).toBeCloseTo(0, EPS_POS);

    expect(s.handL.x).toBeCloseTo(-1.8, EPS_POS);
    expect(s.handL.y).toBeCloseTo(8, EPS_POS);
    expect(s.handL.z).toBeCloseTo(0, EPS_POS);

    expect(s.handR.x).toBeCloseTo(1.8, EPS_POS);
    expect(s.handR.y).toBeCloseTo(8, EPS_POS);
    expect(s.handR.z).toBeCloseTo(0, EPS_POS);

    expect(s.footL.x).toBeCloseTo(-0.6, EPS_POS);
    expect(s.footL.y).toBeCloseTo(5, EPS_POS);
    expect(s.footL.z).toBeCloseTo(0, EPS_POS);

    expect(s.footR.x).toBeCloseTo(0.6, EPS_POS);
    expect(s.footR.y).toBeCloseTo(5, EPS_POS);
    expect(s.footR.z).toBeCloseTo(0, EPS_POS);

    // Symmetry
    expect(s.handL.x).toBeCloseTo(-s.handR.x, EPS_SYM);
    expect(s.footL.x).toBeCloseTo(-s.footR.x, EPS_SYM);
    expect(s.head.x).toBeCloseTo(s.torso.x, EPS_SYM);

    // Basic vertical ordering
    expect(s.controller.y).toBeGreaterThan(s.bar.y);
    expect(s.bar.y).toBeGreaterThan(s.head.y);
    expect(s.head.y).toBeGreaterThan(s.torso.y);
    expect(s.footL.y).toBeGreaterThanOrEqual(0);
    expect(s.footR.y).toBeGreaterThanOrEqual(0);
  });

  it("keeps structure and controller bounds over 1 second of motion", () => {
    const rig = new PuppetRig();
    const dt = 1 / 60;
    let t = 0;
    for (let i = 0; i < 60; i++) {
      t += dt;
      rig.step(dt, t);
    }
    const s = rig.snapshot();

    // Controller bounds
    expect(Math.abs(s.controller.x)).toBeLessThanOrEqual(2.0 + 1e-3);
    expect(s.controller.y).toBeGreaterThanOrEqual(15.0 - 1e-3);
    expect(s.controller.y).toBeLessThanOrEqual(19.5 + 1e-3);

    // Vertical ordering
    expect(s.controller.y).toBeGreaterThan(s.bar.y);
    expect(s.bar.y).toBeGreaterThan(s.head.y);
    expect(s.head.y).toBeGreaterThan(s.torso.y);
    expect(s.footL.y).toBeGreaterThanOrEqual(0);
    expect(s.footR.y).toBeGreaterThanOrEqual(0);

    // Feet corridor
    expect(Math.abs(s.footL.x)).toBeLessThanOrEqual(2.0 + 1e-3);
    expect(Math.abs(s.footR.x)).toBeLessThanOrEqual(2.0 + 1e-3);

    // Torso support in X
    const minFootX = Math.min(s.footL.x, s.footR.x) - 0.5;
    const maxFootX = Math.max(s.footL.x, s.footR.x) + 0.5;
    expect(s.torso.x).toBeGreaterThanOrEqual(minFootX - 1e-3);
    expect(s.torso.x).toBeLessThanOrEqual(maxFootX + 1e-3);

    // Head under controller
    expect(Math.abs(s.head.x - s.controller.x)).toBeLessThanOrEqual(3.0 + 1e-3);
  });

  // Cannon's constraints handle stretch and slack; we assert rig‑level invariants
  // (rest pose, structural ordering, controller bounds) in the other tests and
  // do not additionally constrain exact stretch bands here.
});
