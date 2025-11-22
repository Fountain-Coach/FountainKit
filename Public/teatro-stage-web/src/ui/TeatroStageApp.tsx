import React from "react";

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
          {/* Stage view placeholder; Three.js canvas will live here */}
          <div
            style={{
              width: "100%",
              height: "100%",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              color: "rgba(0,0,0,0.45)",
              fontFamily:
                "system-ui, -apple-system, BlinkMacSystemFont, sans-serif",
              fontSize: 13
            }}
          >
            Stage view (room + puppet) — Three.js integration pending
          </div>
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

