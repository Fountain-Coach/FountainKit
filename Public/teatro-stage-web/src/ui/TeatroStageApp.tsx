import React, { useEffect, useRef, useState } from "react";
import { StageView } from "./StageView";

interface StageState {
  time: number;
}

export const TeatroStageApp: React.FC = () => {
  const [state, setState] = useState<StageState>({ time: 0 });
  const rafRef = useRef<number | null>(null);

  useEffect(() => {
    const start = performance.now();

    const loop = () => {
      const now = performance.now();
      const t = (now - start) / 1000;
      setState({ time: t });
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
          <StageView time={state.time} />
        </div>
      </main>
    </div>
  );
};

