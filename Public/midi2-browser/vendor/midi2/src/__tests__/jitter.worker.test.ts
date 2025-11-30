import { describe, expect, it } from "vitest";
import { JitterReductionSynchronizer } from "../jitter";

const workerSupported = typeof Worker !== "undefined";

describe.skipIf(!workerSupported)("JitterReductionSynchronizer in worker-like clocks", () => {
  it("projects timestamps with a worker clock shim", async () => {
    // Simulate an isolated clock that only advances via a hook.
    let now = 1000;
    const clock = {
      now: () => now,
      setTimer: (at: number, cb: () => void) => {
        const delay = Math.max(0, at - now);
        setTimeout(() => {
          now = at;
          cb();
        }, delay);
        return 1;
      },
      cancelTimer: () => {},
    };
    const jr = new JitterReductionSynchronizer(clock);
    jr.handle({ kind: "utility", status: "jrClock", value: 900, group: 0 }, clock.now());
    const abs = jr.handle({ kind: "utility", status: "jrTimestamp", value: 950, group: 0 }, clock.now());
    expect(abs).toBe(1050);
  });
});
