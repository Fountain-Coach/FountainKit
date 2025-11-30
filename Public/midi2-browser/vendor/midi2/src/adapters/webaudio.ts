import {
  Midi2ChannelPressureEvent,
  Midi2ControlChangeEvent,
  Midi2Event,
  Midi2NoteOffEvent,
  Midi2NoteOnEvent,
  Midi2PitchBendEvent,
  Midi2PolyPressureEvent,
} from "../types";

function midiNoteToHz(note: number): number {
  return 440 * Math.pow(2, (note - 69) / 12);
}

function clamp01(value: number): number {
  return Math.min(1, Math.max(0, value));
}

type VoiceKey = string;
type Voice = {
  osc: OscillatorNode;
  gain: GainNode;
};

export interface WebAudioAdapterOptions {
  destination?: AudioNode;
  releaseMs?: number;
  pitchBendRange?: number;
  velocityCurve?: (velocity: number) => number;
}

class SimplePolySynth {
  private readonly ctx: AudioContext;
  private readonly master: GainNode;
  private readonly voices = new Map<VoiceKey, Voice>();
  private readonly releaseMs: number;
  private readonly pitchBendRange: number;
  private readonly velocityCurve: (velocity: number) => number;

  constructor(ctx: AudioContext, opts?: WebAudioAdapterOptions) {
    this.ctx = ctx;
    this.releaseMs = opts?.releaseMs ?? 40;
    this.pitchBendRange = opts?.pitchBendRange ?? 2;
    this.velocityCurve = opts?.velocityCurve ?? (v => Math.pow(v / 65535, 0.35));
    this.master = ctx.createGain();
    this.master.gain.value = 0.6;
    this.master.connect(opts?.destination ?? ctx.destination);
  }

  noteOn(evt: Midi2NoteOnEvent): void {
    const key = this.voiceKey(evt);
    this.stopVoice(key);
    const gain = this.ctx.createGain();
    const osc = this.ctx.createOscillator();
    osc.type = "sawtooth";
    osc.frequency.value = midiNoteToHz(evt.note);
    const level = clamp01(this.velocityCurve(evt.velocity));
    const now = this.ctx.currentTime;
    gain.gain.setValueAtTime(0, now);
    gain.gain.linearRampToValueAtTime(level, now + 0.005);
    osc.connect(gain).connect(this.master);
    osc.start(now);
    this.voices.set(key, { osc, gain });
  }

  noteOff(evt: Midi2NoteOffEvent): void {
    const key = this.voiceKey(evt);
    const voice = this.voices.get(key);
    if (!voice) return;
    const now = this.ctx.currentTime;
    const releaseSeconds = this.releaseMs / 1000;
    voice.gain.gain.cancelScheduledValues(now);
    voice.gain.gain.setTargetAtTime(0, now, releaseSeconds / 4);
    voice.osc.stop(now + releaseSeconds * 2);
    setTimeout(() => this.stopVoice(key), this.releaseMs * 2);
  }

  polyPressure(evt: Midi2PolyPressureEvent): void {
    const voice = this.voices.get(this.voiceKey(evt));
    if (!voice) return;
    const pressure = clamp01(evt.pressure / 0xffffffff);
    voice.gain.gain.setTargetAtTime(0.2 + pressure * 0.8, this.ctx.currentTime, 0.01);
  }

  controlChange(evt: Midi2ControlChangeEvent): void {
    const norm = evt.value / 0xffffffff;
    if (evt.controller === 7) {
      this.master.gain.setTargetAtTime(clamp01(norm), this.ctx.currentTime, 0.01);
    }
  }

  channelPressure(evt: Midi2ChannelPressureEvent): void {
    const pressure = clamp01(evt.pressure / 0xffffffff);
    this.master.gain.setTargetAtTime(0.2 + pressure * 0.8, this.ctx.currentTime, 0.01);
  }

  pitchBend(evt: Midi2PitchBendEvent): void {
    const bendNorm = (evt.value - 0x80000000) / 0x7fffffff;
    const bendCents = bendNorm * this.pitchBendRange * 100;
    const now = this.ctx.currentTime;
    for (const [key, voice] of this.voices) {
      if (!key.startsWith(`${evt.group}:${evt.channel}:`)) continue;
      voice.osc.detune.setTargetAtTime(bendCents, now, 0.01);
    }
  }

  private stopVoice(key: VoiceKey): void {
    const voice = this.voices.get(key);
    if (!voice) return;
    try {
      voice.osc.stop();
    } catch {
      // oscillator already stopped
    }
    voice.osc.disconnect();
    voice.gain.disconnect();
    this.voices.delete(key);
  }

  private voiceKey(evt: { group: number; channel: number; note: number }): VoiceKey {
    return `${evt.group}:${evt.channel}:${evt.note}`;
  }
}

/**
 * Returns a MidiEventHandler that maps MIDI 2.0 channel voice messages to a simple Web Audio synth.
 */
export function createWebAudioAdapter(ctx: AudioContext, opts?: WebAudioAdapterOptions) {
  const synth = new SimplePolySynth(ctx, opts);
  return (evt: Midi2Event) => {
    switch (evt.kind) {
      case "noteOn":
        synth.noteOn(evt);
        break;
      case "noteOff":
        synth.noteOff(evt);
        break;
      case "polyPressure":
        synth.polyPressure(evt);
        break;
      case "controlChange":
        synth.controlChange(evt);
        break;
      case "channelPressure":
        synth.channelPressure(evt);
        break;
      case "pitchBend":
        synth.pitchBend(evt);
        break;
      default:
        break;
    }
  };
}
