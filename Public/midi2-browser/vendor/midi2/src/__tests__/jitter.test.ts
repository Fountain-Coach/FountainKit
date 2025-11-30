import { describe, expect, it } from "vitest";
import { applyJitterReduction, JitterReductionSynchronizer } from "../jitter";
import { Midi2Event } from "../types";

function createMockClock(
  start = 0,
): {
  clock: { now: () => number; setTimer: (at: number, cb: () => void) => number; cancelTimer: (id: number) => void };
  advance: (ms: number) => void;
} {
  let now = start;
  return {
    clock: {
      now: () => now,
      setTimer: (at, cb) => {
        const delay = Math.max(0, at - now);
        const id = setTimeout(() => {
          now = at;
          cb();
        }, delay) as unknown as number;
        return id;
      },
      cancelTimer: id => clearTimeout(id),
    },
    advance: (ms: number) => {
      now += ms;
    },
  };
}

describe("JitterReductionSynchronizer", () => {
  it("anchors jrClock and projects jrTimestamp to host time", () => {
    const mock = createMockClock(1000);
    const jr = new JitterReductionSynchronizer(mock.clock, 1); // 1 unit = 1ms for test simplicity
    jr.handle({ kind: "utility", status: "jrClock", value: 900, timestampGroup: 0 }, mock.clock.now());
    const abs = jr.handle({ kind: "utility", status: "jrTimestamp", value: 950, timestampGroup: 0 }, mock.clock.now());
    expect(abs).toBe(1050);
    expect(jr.toAbsoluteTime(0, 960)).toBe(1060);
  });

  it("applies latest JR timestamp to subsequent events", () => {
    const mock = createMockClock(500);
    const jr = new JitterReductionSynchronizer(mock.clock, 1);
    const events: Midi2Event[] = [
      { kind: "utility", status: "jrClock", value: 100, timestampGroup: 0 },
      { kind: "utility", status: "jrTimestamp", value: 150, timestampGroup: 0 },
      { kind: "noteOn", group: 0, channel: 0, note: 60, velocity: 0x7fff },
    ];
    const withTs = applyJitterReduction(events, jr, mock.clock.now());
    const note = withTs.find(e => e.kind === "noteOn");
    expect(note?.timestamp).toBe(550); // base 500 - (100) + 150
  });

  it("returns null if no jrClock has been observed for group", () => {
    const mock = createMockClock();
    const jr = new JitterReductionSynchronizer(mock.clock, 1);
    expect(jr.handle({ kind: "utility", status: "jrTimestamp", value: 10, timestampGroup: 1 }, mock.clock.now())).toBeNull();
    expect(jr.toAbsoluteTime(1, 10)).toBeNull();
  });
});
