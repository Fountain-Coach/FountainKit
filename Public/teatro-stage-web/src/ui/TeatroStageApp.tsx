import React, { useEffect, useRef, useState } from "react";
import { StageView } from "./StageView";
import { StageEngine, type StageSnapshot } from "../engine/stage";

export const TeatroStageApp: React.FC = () => {
  const engineRef = useRef<StageEngine | null>(null);
  const lastTimeRef = useRef<number | null>(null);
  const rafRef = useRef<number | null>(null);
  const [snapshot, setSnapshot] = useState<StageSnapshot | null>(null);

  useEffect(() => {
    engineRef.current = new StageEngine();

    const loop = () => {
      const now = performance.now();
      const last = lastTimeRef.current ?? now;
      const dtSeconds = (now - last) / 1000;
      lastTimeRef.current = now;

      const engine = engineRef.current;
      if (engine) {
        engine.step(dtSeconds);
        setSnapshot(engine.snapshot());
      }

      rafRef.current = requestAnimationFrame(loop);
    };

    rafRef.current = requestAnimationFrame(loop);

    return () => {
      if (rafRef.current != null) {
        cancelAnimationFrame(rafRef.current);
      }
    };
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
      <header
        style={{
          padding: "8px 12px",
          fontFamily:
            "system-ui, -apple-system, BlinkMacSystemFont, sans-serif",
          fontSize: 14,
          fontWeight: 500,
          borderBottom: "1px solid rgba(0,0,0,0.08)"
        }}
      >
        Teatro Stage Engine — Web (rebuild in progress)
      </header>
      <main style={{ flex: 1, display: "flex", flexDirection: "column" }}>
        <div style={{ flex: 1 }}>
          {snapshot && <StageView snapshot={snapshot} />}
        </div>
      </main>
    </div>
  );
};
