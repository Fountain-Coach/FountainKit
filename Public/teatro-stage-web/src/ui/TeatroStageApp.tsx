import React, { useEffect, useRef, useState } from "react";
import { StageEngine, type StageSnapshot } from "../engine/stage";
import { ThreeStageView } from "./ThreeStageView";
import { DiagPanel } from "./DiagPanel";

export const TeatroStageApp: React.FC = () => {
  const engineRef = useRef<StageEngine | null>(null);
  const lastTimeRef = useRef<number | null>(null);
  const rafRef = useRef<number | null>(null);
  const [snapshot, setSnapshot] = useState<StageSnapshot | null>(null);
  const [isPlaying, setIsPlaying] = useState(true);
  const [windStrength] = useState(0.6);
  const [showDiag, setShowDiag] = useState(false);
  const barMotionRef = useRef({
    swayAmp: 2.0,
    swayRate: 0.7,
    upDownAmp: 0.5,
    upDownRate: 0.9
  });
  const prevBarRef = useRef<{ x: number; t: number }>({ x: 0, t: 0 });

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

        prevBarRef.current = { x: snap.puppet.bar.position.x, t: snap.time };
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
          {snapshot && <ThreeStageView snapshot={snapshot} />}
          <button
            type="button"
            aria-label="Info"
            onClick={() => setShowDiag(true)}
            style={{
              position: "absolute",
              right: 12,
              top: 12,
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
          {showDiag && <DiagPanel snapshot={snapshot} onHide={() => setShowDiag(false)} />}
        </div>
      </main>
    </div>
  );
};
