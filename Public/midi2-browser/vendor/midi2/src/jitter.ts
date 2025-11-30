import { MidiClock } from "./clock";
import { Midi2Event, UtilityEvent } from "./types";

type GroupState = {
  baseMs: number;
  clockValue: number;
  lastTimestamp?: number;
};

/**
 * Tracks Jitter Reduction (JR) clock/timestamp messages and projects them into the host clock domain.
 * Assumes JR units are expressed in milliseconds unless overridden via `unitMs`.
 * This is a minimal helper; callers must wire incoming utility events (jrClock/jrTimestamp) into `handle`.
 */
export class JitterReductionSynchronizer {
  private readonly clock: MidiClock;
  private readonly unitMs: number;
  private readonly groups = new Map<number, GroupState>();

  constructor(clock: MidiClock, unitMs = 1) {
    this.clock = clock;
    this.unitMs = unitMs;
  }

  /**
    * Handle a utility event (jrClock or jrTimestamp) and update internal state.
    * Returns an absolute host time (ms) when a jrTimestamp is processed and a base clock is known; otherwise null.
    */
  handle(event: UtilityEvent, receivedAtMs = this.clock.now()): number | null {
    if (event.kind !== "utility") return null;
    const group = (event.group ?? event.timestampGroup) ?? 0;
    if (event.status === "jrClock") {
      const state: GroupState = {
        baseMs: receivedAtMs - (event.value ?? 0) * this.unitMs,
        clockValue: event.value ?? 0,
        lastTimestamp: undefined,
      };
      this.groups.set(group, state);
      return null;
    }
    if (event.status === "jrTimestamp") {
      const state = this.groups.get(group);
      if (!state) return null;
      state.lastTimestamp = event.value ?? 0;
      return state.baseMs + (event.value ?? 0) * this.unitMs;
    }
    return null;
  }

  /**
   * Convert a JR timestamp value into an absolute host time (ms) for the given group.
   * Returns null if no JR clock has been observed for the group.
   */
  toAbsoluteTime(group: number, jrTimestampValue?: number): number | null {
    const state = this.groups.get(group);
    if (!state) return null;
    const value = jrTimestampValue ?? state.lastTimestamp;
    if (value === undefined) return null;
    return state.baseMs + value * this.unitMs;
  }
}

/**
 * Applies jitter reduction timestamps to a sequence of events.
 * JR clock/timestamp utility messages are fed to the synchronizer; other events get a `timestamp`
 * derived from the latest JR state for their group when available.
 */
export function applyJitterReduction(events: Midi2Event[], jr: JitterReductionSynchronizer, receivedAtMs?: number): Midi2Event[] {
  const out: Midi2Event[] = [];
  const now = receivedAtMs ?? jr["clock"]?.now?.() ?? 0;
  for (const evt of events) {
    if (evt.kind === "utility" && (evt.status === "jrClock" || evt.status === "jrTimestamp")) {
      const ts = jr.handle(evt, now);
      out.push(ts !== null ? { ...evt, timestamp: ts } : evt);
      continue;
    }
    const abs = evt.timestamp ?? jr.toAbsoluteTime((evt as any).group ?? 0);
    out.push(abs !== null ? { ...evt, timestamp: abs } : evt);
  }
  return out;
}
