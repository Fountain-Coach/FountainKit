import { MidiClock, TimerHandle } from "./clock";
import { Midi2Event, MidiEventHandler } from "./types";
import { JitterReductionSynchronizer } from "./jitter";

type QueueItem = {
  id: number;
  time: number;
  event: Midi2Event;
};

export interface SchedulerOptions {
  /**
   * Additional window (in ms) to coalesce near-due events into a single dispatch tick.
   */
  jitterToleranceMs?: number;
  /**
   * Optional Jitter Reduction synchronizer to project JR clock/timestamp messages into host time.
   */
  jitterReduction?: JitterReductionSynchronizer;
}

export class Midi2Scheduler {
  private readonly clock: MidiClock;
  private readonly jitterToleranceMs: number;
  private readonly jitterReduction?: JitterReductionSynchronizer;
  private readonly handlers = new Set<MidiEventHandler>();
  private queue: QueueItem[] = [];
  private timer: TimerHandle | null = null;
  private nextId = 1;

  constructor(clock: MidiClock, options?: SchedulerOptions) {
    this.clock = clock;
    this.jitterToleranceMs = options?.jitterToleranceMs ?? 0.5;
    this.jitterReduction = options?.jitterReduction;
  }

  onEvent(handler: MidiEventHandler): () => void {
    this.handlers.add(handler);
    return () => this.handlers.delete(handler);
  }

  schedule(event: Midi2Event, at: number): number {
    const id = this.nextId++;
    let timestamp = event.timestamp ?? at;
    if (this.jitterReduction) {
      if (event.kind === "utility" && (event.status === "jrClock" || event.status === "jrTimestamp")) {
        const abs = this.jitterReduction.handle(event as any, at);
        if (abs !== null) timestamp = abs;
      } else {
        const projected = this.jitterReduction.toAbsoluteTime((event as any).group ?? 0);
        if (projected !== null) timestamp = projected;
      }
    }
    const payload: Midi2Event = { ...event, timestamp };
    const item: QueueItem = { id, time: at, event: payload };
    this.insert(item);
    this.armNext();
    return id;
  }

  cancel(id: number): boolean {
    const idx = this.queue.findIndex(item => item.id === id);
    if (idx === -1) {
      return false;
    }
    const removedHead = idx === 0;
    this.queue.splice(idx, 1);
    if (removedHead) {
      this.armNext();
    }
    return true;
  }

  clear(): void {
    this.queue = [];
    if (this.timer !== null) {
      this.clock.cancelTimer(this.timer);
      this.timer = null;
    }
  }

  private dispatchDue(): void {
    const now = this.clock.now();
    const cutoff = now + this.jitterToleranceMs;
    while (this.queue.length && this.queue[0].time <= cutoff) {
      const { event } = this.queue.shift()!;
      this.emit(event);
    }
    this.armNext();
  }

  private emit(event: Midi2Event): void {
    for (const handler of this.handlers) {
      try {
        handler(event);
      } catch (err) {
        // Keep other subscribers running if one fails.
        console.error("midi2: handler threw", err);
      }
    }
  }

  private insert(item: QueueItem): void {
    if (!this.queue.length || item.time >= this.queue[this.queue.length - 1].time) {
      this.queue.push(item);
      return;
    }
    const idx = this.queue.findIndex(q => item.time < q.time);
    if (idx === -1) {
      this.queue.push(item);
    } else {
      this.queue.splice(idx, 0, item);
    }
  }

  private armNext(): void {
    if (this.timer !== null) {
      this.clock.cancelTimer(this.timer);
      this.timer = null;
    }
    if (!this.queue.length) {
      return;
    }
    const next = this.queue[0];
    const now = this.clock.now();
    if (next.time <= now + this.jitterToleranceMs) {
      // Event is already due; dispatch synchronously to avoid timer drift.
      this.dispatchDue();
      return;
    }
    this.timer = this.clock.setTimer(next.time, () => {
      this.timer = null;
      this.dispatchDue();
    });
  }
}
