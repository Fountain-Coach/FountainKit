import { describe, expect, it } from "vitest";
import { Midi2Scheduler } from "../scheduler";
import { Midi2Event } from "../types";
import { MidiClock } from "../clock";
import { JitterReductionSynchronizer } from "../jitter";

type Scheduled = { at: number; cb: () => void; id: number };

function createMockClock(): { clock: MidiClock; advance: (ms: number) => void; now: () => number } {
  let now = 0;
  let nextId = 1;
  const timers: Scheduled[] = [];

  const runDue = () => {
    timers.sort((a, b) => a.at - b.at);
    while (timers.length && timers[0].at <= now) {
      const { cb, id } = timers.shift()!;
      cb();
      for (let i = timers.length - 1; i >= 0; i--) {
        if (timers[i].id === id) timers.splice(i, 1);
      }
      timers.sort((a, b) => a.at - b.at);
    }
  };

  const clock: MidiClock = {
    now: () => now,
    setTimer: (at, cb) => {
      const id = nextId++;
      timers.push({ at, cb, id });
      timers.sort((a, b) => a.at - b.at);
      return id;
    },
    cancelTimer: id => {
      const idx = timers.findIndex(t => t.id === id);
      if (idx !== -1) timers.splice(idx, 1);
    },
  };

  return {
    clock,
    advance: (ms: number) => {
      now += ms;
      runDue();
    },
    now: () => now,
  };
}

describe("Midi2Scheduler with jitter reduction", () => {
  it("projects JR timestamps onto scheduled events", () => {
    const mock = createMockClock();
    const jr = new JitterReductionSynchronizer(mock.clock, 1); // 1 unit == 1 ms for test
    const scheduler = new Midi2Scheduler(mock.clock, { jitterToleranceMs: 0, jitterReduction: jr });
    const received: Midi2Event[] = [];
    scheduler.onEvent(evt => received.push(evt));

    scheduler.schedule({ kind: "utility", status: "jrClock", value: 100 }, mock.now());
    scheduler.schedule({ kind: "utility", status: "jrTimestamp", value: 150 }, mock.now());
    scheduler.schedule({ kind: "noteOn", group: 0, channel: 0, note: 60, velocity: 0x7fff }, mock.now());

    mock.advance(0);
    expect(received.length).toBe(3);
    const note = received.find(e => e.kind === "noteOn");
    expect(note?.timestamp).toBe(50); // base = now -100 -> -100; timestamp 150 => 50ms absolute
  });
});
