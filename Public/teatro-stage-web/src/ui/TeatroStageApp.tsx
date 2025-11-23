import React, { useEffect, useRef, useState } from "react";
import { BallStageView } from "./BallStageView";
import {
  BallStageEngine,
  type BallStageSnapshot
} from "../engine/ballStage";

export const TeatroStageApp: React.FC = () => {
  const engineRef = useRef<BallStageEngine | null>(null);
  const lastTimeRef = useRef<number | null>(null);
  const rafRef = useRef<number | null>(null);
  const [snapshot, setSnapshot] = useState<BallStageSnapshot | null>(null);
  const [isPlaying, setIsPlaying] = useState(true);

  useEffect(() => {
    engineRef.current = new BallStageEngine("drop");

    const loop = () => {
      const now = performance.now();
      const last = lastTimeRef.current ?? now;
      const dtSeconds = (now - last) / 1000;
      lastTimeRef.current = now;

      const engine = engineRef.current;
      if (engine && isPlaying) {
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
  }, [isPlaying]);

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
        <span>Teatro Stage Engine — Web (rebuild in progress)</span>
        <span style={{ marginLeft: 16, opacity: 0.7 }}>
          t = {timeSeconds.toFixed(2)}s · {isPlaying ? "playing" : "paused"}
        </span>
      </header>
      <main style={{ flex: 1, display: "flex", flexDirection: "column" }}>
        <div style={{ flex: 1, position: "relative" }}>
          {snapshot && <BallStageView snapshot={snapshot} />}
          <div
            style={{
              position: "absolute",
              left: 12,
              bottom: 12,
              display: "inline-flex",
              alignItems: "center",
              gap: 8,
              padding: "4px 8px",
              borderRadius: 999,
              backgroundColor: "rgba(244, 234, 214, 0.85)",
              border: "1px solid rgba(0,0,0,0.12)",
              fontSize: 12,
              fontFamily:
                "system-ui, -apple-system, BlinkMacSystemFont, sans-serif"
            }}
          >
            <button
              type="button"
              onClick={handleTogglePlay}
              style={{
                border: "none",
                background: "transparent",
                padding: "2px 6px",
                cursor: "pointer",
                fontSize: 12
              }}
            >
              {isPlaying ? "Pause" : "Play"}
            </button>
            <span style={{ opacity: 0.7 }}>
              t = {timeSeconds.toFixed(2)}s
            </span>
          </div>
        </div>
      </main>
    </div>
  );
};
