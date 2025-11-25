import { PuppetRig, type PuppetSnapshot } from "./puppetRig";

export interface StageSnapshot {
  time: number;
  puppet: PuppetSnapshot;
}

// Small in‑process wrapper that drives the puppet rig and exposes a snapshot
// matching the TeatroStageEngine interchange shape (time + body positions).
export class StageEngine {
  private readonly rig: PuppetRig;
  private timeSeconds = 0;
  windStrength = 1;
  private barMotion = {
    swayAmp: 2.0,
    swayRate: 0.7,
    upDownAmp: 0.5,
    upDownRate: 0.9
  };

  constructor() {
    this.rig = new PuppetRig();
  }

  step(dtSeconds: number): void {
    if (dtSeconds <= 0) return;
    const dtClamped = Math.min(dtSeconds, 1 / 30);
    this.timeSeconds += dtClamped;
    this.rig.setBarMotion(this.barMotion);
    this.rig.step(dtClamped, this.timeSeconds);
  }

  snapshot(): StageSnapshot {
    return {
      time: this.timeSeconds,
      puppet: this.rig.snapshot()
    };
  }

  setWindStrength(strength: number): void {
    this.windStrength = Math.max(0, strength);
    this.rig.setWindStrength(this.windStrength);
  }

  setBarMotion(params: {
    swayAmp?: number;
    swayRate?: number;
    upDownAmp?: number;
    upDownRate?: number;
  }): void {
    this.barMotion = {
      ...this.barMotion,
      ...params
    };
  }
}
