import React, { useEffect, useRef, useState } from "react";
import { StageEngine, type StageSnapshot } from "../engine/stage";
import { ThreeStageView } from "./ThreeStageView";
import { DiagPanel } from "./DiagPanel";

function clamp(v: number, min: number, max: number) {
  return Math.max(min, Math.min(max, v));
}

function sendCC(outputs: WebMidi.MIDIOutput[], cc: number, value01: number, channel = 0) {
  const v = clamp(value01, 0, 1);
  const data2 = Math.round(v * 127);
  const status = 0xb0 | (channel & 0x0f);
  for (const out of outputs) {
    out.send([status, cc & 0x7f, data2]);
  }
}

function emitMidiForSnapshot(
  snap: StageSnapshot,
  prev: StageSnapshot | null,
  outputs: WebMidi.MIDIOutput[]
) {
  if (!prev || outputs.length === 0) return;
  const dt = Math.max(1e-3, snap.time - prev.time);
  const velBarX = (snap.puppet.bar.position.x - prev.puppet.bar.position.x) / dt;
  const velBarY = (snap.puppet.bar.position.y - prev.puppet.bar.position.y) / dt;
  const velMag = Math.sqrt(velBarX * velBarX + velBarY * velBarY);
  const vel01 = clamp(velMag / 5, 0, 1);
  sendCC(outputs, 1, vel01); // mod depth
  const height01 = clamp((snap.puppet.bar.position.y - 5) / 20, 0, 1);
  sendCC(outputs, 74, height01); // brightness
  // simple energy: sum of hand/foot speeds
  const limbs = ["handL", "handR", "footL", "footR"] as const;
  let energy = 0;
  for (const limb of limbs) {
    const dx =
      (snap.puppet[limb].position.x - (prev.puppet as any)[limb].position.x) / dt;
    const dy =
      (snap.puppet[limb].position.y - (prev.puppet as any)[limb].position.y) / dt;
    energy += Math.sqrt(dx * dx + dy * dy);
  }
  const energy01 = clamp(energy / 10, 0, 1);
  sendCC(outputs, 7, energy01); // volume proxy
}

export const TeatroStageApp: React.FC = () => {
  const engineRef = useRef<StageEngine | null>(null);
  const lastTimeRef = useRef<number | null>(null);
  const rafRef = useRef<number | null>(null);
  const [snapshot, setSnapshot] = useState<StageSnapshot | null>(null);
  const [isPlaying, setIsPlaying] = useState(true);
  const [windStrength] = useState(0.6);
  const [showDiag, setShowDiag] = useState(false);
  const [showRestOverlay, setShowRestOverlay] = useState(false);
  const midiOutputsRef = useRef<WebMidi.MIDIOutput[]>([]);
  const barMotionRef = useRef({
    swayAmp: 2.0,
    swayRate: 0.7,
    upDownAmp: 0.5,
    upDownRate: 0.9
  });
  const prevSnapshotRef = useRef<StageSnapshot | null>(null);

  useEffect(() => {
    engineRef.current = new StageEngine();
    engineRef.current.setWindStrength(windStrength);
    engineRef.current.setBarMotion(barMotionRef.current);

    const loop = () => {
      const now = performance.now();
      const last = lastTimeRef.current ?? now;
      const dtSeconds = (now - last) / 1000;
      lastTimeRef.current = now;

      const engine = engineRef.current;
      if (engine && isPlaying) {
        engine.step(dtSeconds);
        const snap = engine.snapshot();
        setSnapshot(snap);

        emitMidiForSnapshot(snap, prevSnapshotRef.current, midiOutputsRef.current);
        prevSnapshotRef.current = snap;
      }

      rafRef.current = requestAnimationFrame(loop);
    };

    rafRef.current = requestAnimationFrame(loop);

    return () => {
      if (rafRef.current != null) {
        cancelAnimationFrame(rafRef.current);
      }
    };
  }, [isPlaying, windStrength]);

  const handleTogglePlay = () => {
    setIsPlaying((prev) => !prev);
  };

  const timeSeconds = snapshot?.time ?? 0;

  // Web MIDI setup (outputs only).
  useEffect(() => {
    if (!("requestMIDIAccess" in navigator)) return;
    (navigator as any)
      .requestMIDIAccess()
      .then((access: WebMidi.MIDIAccess) => {
        midiOutputsRef.current = Array.from(access.outputs.values());
        access.onstatechange = () => {
          midiOutputsRef.current = Array.from(access.outputs.values());
        };
      })
      .catch(() => {
        midiOutputsRef.current = [];
      });
  }, []);

  return (
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        height: "100vh",
        backgroundColor: "#f4ead6"
      }}
    >
      <main style={{ flex: 1, display: "flex", flexDirection: "column" }}>
        <div style={{ flex: 1, position: "relative" }}>
          {snapshot && <ThreeStageView snapshot={snapshot} showRestOverlay={showRestOverlay} />}
          <div
            style={{
              position: "absolute",
              right: 12,
              top: 12,
              display: "flex",
              gap: 8
            }}
          >
            <button
              type="button"
              aria-label="Toggle rest pose overlay"
              aria-pressed={showRestOverlay}
              onClick={() => setShowRestOverlay((prev) => !prev)}
              style={{
                width: 28,
                height: 28,
                borderRadius: "50%",
                border: "1px solid rgba(0,0,0,0.3)",
                background: showRestOverlay ? "rgba(30, 136, 229, 0.15)" : "rgba(0,0,0,0.05)",
                cursor: "pointer",
                fontSize: 14,
                fontWeight: 600,
                color: "#0d47a1"
              }}
              title="Rest pose overlay"
            >
              ⧉
            </button>
            <button
              type="button"
              aria-label="Info"
              onClick={() => setShowDiag(true)}
              style={{
                width: 28,
                height: 28,
                borderRadius: "50%",
                border: "1px solid rgba(0,0,0,0.3)",
                background: "rgba(0,0,0,0.05)",
                cursor: "pointer",
                fontSize: 14,
                fontWeight: 600
              }}
            >
              i
            </button>
          </div>
          {showDiag && <DiagPanel snapshot={snapshot} onHide={() => setShowDiag(false)} />}
        </div>
      </main>
    </div>
  );
};
