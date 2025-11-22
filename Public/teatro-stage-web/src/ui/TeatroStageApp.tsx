import React from "react";
import { StageView } from "./StageView";

export const TeatroStageApp: React.FC = () => {
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
          fontFamily: "system-ui, -apple-system, BlinkMacSystemFont, sans-serif",
          fontSize: 14,
          fontWeight: 500,
          borderBottom: "1px solid rgba(0,0,0,0.08)"
        }}
      >
        Teatro Stage Engine — Web (WIP)
      </header>
      <main style={{ flex: 1, display: "flex", flexDirection: "column" }}>
        <div
          style={{
            flex: 1,
            borderBottom: "1px solid rgba(0,0,0,0.08)"
          }}
        >
          <StageView />
        </div>
        <div
          style={{
            height: 80,
            borderTop: "1px solid rgba(0,0,0,0.08)",
            display: "flex",
            alignItems: "center",
            padding: "0 12px",
            fontFamily:
              "system-ui, -apple-system, BlinkMacSystemFont, sans-serif",
            fontSize: 12,
            color: "rgba(0,0,0,0.6)"
          }}
        >
          Time bar + inspector (record / scrub / snapshot) — to be wired to the TS engine.
        </div>
      </main>
    </div>
  );
};
