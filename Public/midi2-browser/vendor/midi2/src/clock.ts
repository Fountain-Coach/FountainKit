export type TimerHandle = number | ReturnType<typeof setTimeout>;

/**
 * Minimal clock interface used by the scheduler.
 * Timebase is milliseconds in the host's high-resolution clock domain.
 */
export interface MidiClock {
  now(): number;
  setTimer(at: number, cb: () => void): TimerHandle;
  cancelTimer(id: TimerHandle): void;
}

/**
 * Default clock using performance.now() when available.
 */
export function createBrowserClock(): MidiClock {
  const perf = typeof performance !== "undefined" ? performance : { now: () => Date.now() };
  return {
    now: () => perf.now(),
    setTimer: (at, cb) => {
      const delay = Math.max(0, at - perf.now());
      return setTimeout(cb, delay);
    },
    cancelTimer: id => clearTimeout(id as number),
  };
}

/**
 * AudioContext-backed clock that tracks the audio timeline.
 * Useful when you want scheduling to align with Web Audio time.
 */
export function createAudioContextClock(ctx: Pick<BaseAudioContext, "currentTime">): MidiClock {
  return {
    now: () => ctx.currentTime * 1000,
    setTimer: (at, cb) => {
      const delayMs = Math.max(0, at - ctx.currentTime * 1000);
      return setTimeout(cb, delayMs);
    },
    cancelTimer: id => clearTimeout(id as number),
  };
}

/**
 * Worker-backed clock to keep timer callbacks off the main thread.
 * Falls back to an error if Worker APIs are unavailable.
 */
export function createWorkerClock(): MidiClock {
  if (typeof Worker === "undefined" || typeof URL === "undefined" || typeof Blob === "undefined") {
    throw new Error("Worker clock is unavailable in this environment.");
  }

  const workerSource = `
    const timers = new Map();
    self.onmessage = evt => {
      const { type, id, delay } = evt.data || {};
      if (type === "set") {
        const handle = setTimeout(() => {
          timers.delete(id);
          self.postMessage({ type: "fire", id });
        }, Math.max(0, delay));
        timers.set(id, handle);
      } else if (type === "cancel") {
        const handle = timers.get(id);
        if (handle !== undefined) {
          clearTimeout(handle);
          timers.delete(id);
        }
      }
    };
  `;
  const blob = new Blob([workerSource], { type: "application/javascript" });
  const worker = new Worker(URL.createObjectURL(blob), { name: "midi2-clock" });

  const perf = typeof performance !== "undefined" ? performance : { now: () => Date.now() };
  const callbacks = new Map<number, () => void>();
  let nextId = 1;

  worker.onmessage = evt => {
    if (!evt.data || evt.data.type !== "fire") {
      return;
    }
    const cb = callbacks.get(evt.data.id);
    if (cb) {
      callbacks.delete(evt.data.id);
      cb();
    }
  };

  return {
    now: () => perf.now(),
    setTimer: (at, cb) => {
      const id = nextId++;
      callbacks.set(id, cb);
      const delay = Math.max(0, at - perf.now());
      worker.postMessage({ type: "set", id, delay });
      return id;
    },
    cancelTimer: id => {
      callbacks.delete(id as number);
      worker.postMessage({ type: "cancel", id });
    },
  };
}
