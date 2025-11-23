import { BallWorld, type BallSnapshot } from "./ball";
import { Vec3 } from "./physics";

export interface BallStageSnapshot {
  time: number;
  ball: BallSnapshot;
}

// Small in‑process wrapper that drives the BallWorld and exposes a snapshot
// matching the TeatroStageEngine ball baseline (time + position + velocity).
export class BallStageEngine {
  private readonly world: BallWorld;
  private timeSeconds = 0;

  constructor(initialMode: "drop" | "throw" = "drop") {
    if (initialMode === "drop") {
      this.world = new BallWorld();
    } else {
      this.world = new BallWorld(new Vec3(0, 1, 0), 1.0, 1.0);
      this.world.setHorizontalSpeed(4.0);
    }
  }

  step(dtSeconds: number): void {
    if (dtSeconds <= 0) return;
    this.timeSeconds += dtSeconds;
    this.world.step(dtSeconds);
  }

  snapshot(): BallStageSnapshot {
    return {
      time: this.timeSeconds,
      ball: this.world.snapshot()
    };
  }
}
