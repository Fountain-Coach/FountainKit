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

  constructor() {
    this.rig = new PuppetRig();
  }

  step(dtSeconds: number): void {
    if (dtSeconds <= 0) return;
    this.timeSeconds += dtSeconds;
    this.rig.step(dtSeconds, this.timeSeconds);
  }

  snapshot(): StageSnapshot {
    return {
      time: this.timeSeconds,
      puppet: this.rig.snapshot()
    };
  }
}

