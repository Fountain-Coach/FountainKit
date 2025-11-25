import { describe, it, expect } from "vitest";
import { StageEngine } from "./stage";

describe("StageEngine", () => {
  it("steps without NaN and produces puppet snapshot", () => {
    const eng = new StageEngine();
    eng.step(1 / 60);
    const snap = eng.snapshot();
    expect(snap.time).toBeGreaterThan(0);
    const parts = [
      snap.puppet.bar,
      snap.puppet.torso,
      snap.puppet.head,
      snap.puppet.handL,
      snap.puppet.handR,
      snap.puppet.footL,
      snap.puppet.footR
    ];
    for (const p of parts) {
      expect(Number.isFinite(p.position.x)).toBe(true);
      expect(Number.isFinite(p.position.y)).toBe(true);
      expect(Number.isFinite(p.position.z)).toBe(true);
    }
  });
});
