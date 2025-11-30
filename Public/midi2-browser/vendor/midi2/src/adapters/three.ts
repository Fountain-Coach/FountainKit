import { Midi2ControlChangeEvent, Midi2Event, Midi2NoteOffEvent, Midi2NoteOnEvent, Midi2PitchBendEvent } from "../types";

type SceneLike = { add: (obj: any) => void; remove: (obj: any) => void };

export interface ThreeAdapterOptions {
  decayMs?: number;
  createObject?: (evt: Midi2NoteOnEvent) => any;
  onControlChange?: (evt: Midi2ControlChangeEvent) => void;
  onPitchBend?: (evt: Midi2PitchBendEvent) => void;
}

function defaultMeshFactory(evt: Midi2NoteOnEvent): any | null {
  const maybeThree = (globalThis as any).THREE;
  if (!maybeThree) return null;
  const size = 0.3 + (evt.velocity / 65535) * 0.7;
  const geometry = new maybeThree.SphereGeometry(size, 16, 16);
  const material = new maybeThree.MeshStandardMaterial({
    color: new maybeThree.Color(`hsl(${(evt.note % 24) * 15}, 70%, 55%)`),
    emissiveIntensity: 0.6,
  });
  const mesh = new maybeThree.Mesh(geometry, material);
  mesh.position.set((evt.note - 60) * 0.15, 0, 0);
  mesh.userData.midi2Key = `${evt.group}:${evt.channel}:${evt.note}`;
  return mesh;
}

/**
 * Returns a MidiEventHandler that maps note on/off into transient Three.js meshes.
 * Requires a scene-like object with add/remove; uses global THREE if available.
 */
export function createThreeAdapter(scene: SceneLike, opts?: ThreeAdapterOptions) {
  const decayMs = opts?.decayMs ?? 250;
  const factory = opts?.createObject ?? defaultMeshFactory;
  const active = new Map<string, any>();

  return (evt: Midi2Event) => {
    switch (evt.kind) {
      case "noteOn": {
        const key = `${evt.group}:${evt.channel}:${evt.note}`;
        const obj = factory(evt);
        if (!obj) return;
        active.set(key, obj);
        scene.add(obj);
        break;
      }
      case "noteOff": {
        const key = `${evt.group}:${evt.channel}:${evt.note}`;
        const obj = active.get(key);
        if (!obj) return;
        setTimeout(() => {
          scene.remove(obj);
          active.delete(key);
        }, decayMs);
        break;
      }
      case "controlChange":
        opts?.onControlChange?.(evt as Midi2ControlChangeEvent);
        break;
      case "pitchBend":
        opts?.onPitchBend?.(evt as Midi2PitchBendEvent);
        break;
      default:
        break;
    }
  };
}
