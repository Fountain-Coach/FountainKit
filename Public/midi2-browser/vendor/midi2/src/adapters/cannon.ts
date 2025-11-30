import { Midi2ControlChangeEvent, Midi2Event, Midi2NoteOffEvent, Midi2NoteOnEvent, Midi2PitchBendEvent } from "../types";

type CannonWorldLike = {
  addBody: (body: any) => void;
  removeBody: (body: any) => void;
};

export interface CannonAdapterOptions {
  createBody?: (evt: Midi2NoteOnEvent) => any;
  impulseScale?: number;
  onControlChange?: (evt: Midi2ControlChangeEvent) => void;
  onPitchBend?: (evt: Midi2PitchBendEvent) => void;
}

function defaultBodyFactory(evt: Midi2NoteOnEvent): any | null {
  const CANNON = (globalThis as any).CANNON;
  if (!CANNON) return null;
  const radius = 0.2 + (evt.velocity / 65535) * 0.4;
  const shape = new CANNON.Sphere(radius);
  const body = new CANNON.Body({
    mass: 1,
    shape,
    position: new CANNON.Vec3((evt.note - 60) * 0.3, 1 + (evt.velocity / 65535) * 1.5, 0),
  });
  body.userData = { midi2Key: `${evt.group}:${evt.channel}:${evt.note}` };
  return body;
}

/**
 * Returns a MidiEventHandler that maps note on/off to Cannon.js rigid bodies and impulses.
 * Requires a world-like object with addBody/removeBody; uses global CANNON if available.
 */
export function createCannonAdapter(world: CannonWorldLike, opts?: CannonAdapterOptions) {
  const bodies = new Map<string, any>();
  const impulseScale = opts?.impulseScale ?? 10;
  const factory = opts?.createBody ?? defaultBodyFactory;

  return (evt: Midi2Event) => {
    switch (evt.kind) {
      case "noteOn": {
        const key = `${evt.group}:${evt.channel}:${evt.note}`;
        const body = factory(evt);
        if (!body) return;
        bodies.set(key, body);
        world.addBody(body);
        const impulseStrength = (evt.velocity / 65535) * impulseScale;
        if (typeof body.applyImpulse === "function") {
          body.applyImpulse({ x: 0, y: impulseStrength, z: 0 }, body.position);
        }
        break;
      }
      case "noteOff": {
        const key = `${evt.group}:${evt.channel}:${evt.note}`;
        const body = bodies.get(key);
        if (!body) return;
        world.removeBody(body);
        bodies.delete(key);
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
