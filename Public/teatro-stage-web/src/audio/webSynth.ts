export interface SynthParams {
  masterGain: number;
  wave: OscillatorType;
  attack: number;
  release: number;
}

type Voice = {
  osc: OscillatorNode;
  gain: GainNode;
  stop: () => void;
};

// Minimal Web Audio poly synth for browser use. Not for production audio,
// just to demo stage + sound controlled via Web MIDI.
export class WebSynth {
  private ctx: AudioContext | null = null;
  private master: GainNode | null = null;
  private voices: Map<string, Voice> = new Map();
  private params: SynthParams = {
    masterGain: 0.1,
    wave: "sine",
    attack: 0.01,
    release: 0.3
  };

  private ensureContext(): void {
    if (!this.ctx) {
      this.ctx = new AudioContext();
      this.master = this.ctx.createGain();
      this.master.gain.value = this.params.masterGain;
      this.master.connect(this.ctx.destination);
    }
  }

  setParams(params: Partial<SynthParams>): void {
    this.params = { ...this.params, ...params };
    if (this.master) {
      this.master.gain.value = this.params.masterGain;
    }
  }

  noteOn(note: number, velocity: number): void {
    this.ensureContext();
    if (!this.ctx || !this.master) return;
    const now = this.ctx.currentTime;
    const freq = 440 * Math.pow(2, (note - 69) / 12);
    const osc = this.ctx.createOscillator();
    osc.type = this.params.wave;
    osc.frequency.value = freq;

    const gain = this.ctx.createGain();
    const vel = Math.max(0, Math.min(1, velocity / 127));
    gain.gain.setValueAtTime(0, now);
    gain.gain.linearRampToValueAtTime(vel, now + this.params.attack);
    osc.connect(gain).connect(this.master);
    osc.start(now);

    const key = `${note}`;
    const stop = () => {
      const end = this.ctx!.currentTime + this.params.release;
      gain.gain.cancelScheduledValues(this.ctx!.currentTime);
      gain.gain.setValueAtTime(gain.gain.value, this.ctx!.currentTime);
      gain.gain.linearRampToValueAtTime(0, end);
      osc.stop(end);
      setTimeout(() => {
        osc.disconnect();
        gain.disconnect();
      }, this.params.release * 1000 + 50);
    };

    this.voices.set(key, { osc, gain, stop });
  }

  noteOff(note: number): void {
    const key = `${note}`;
    const v = this.voices.get(key);
    if (!v) return;
    v.stop();
    this.voices.delete(key);
  }
}
