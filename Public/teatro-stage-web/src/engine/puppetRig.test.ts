import { describe, it, expect } from "vitest";
import { PuppetRig } from "./puppetRig";

describe("PuppetRig", () => {
  it("produces a non-degenerate snapshot at t=0", () => {
    const rig = new PuppetRig();
    const snap = rig.snapshot();
    // controller above torso
    expect(snap.controller.y).toBeGreaterThan(snap.torso.y);
    // head above torso
    expect(snap.head.y).toBeGreaterThan(snap.torso.y);
  });

  it("moves when stepped forward in time", () => {
    const rig = new PuppetRig();
    const snap0 = rig.snapshot();
    const dt = 1 / 60;
    let t = 0;
    for (let i = 0; i < 60; i++) {
      t += dt;
      rig.step(dt, t);
    }
    const snap1 = rig.snapshot();
    expect(snap1.controller.x).not.toBe(snap0.controller.x);
  });
});

