import React from "react";

export interface MidiEventInfo {
  ts: number;
  status: number;
  data1: number;
  data2: number;
  type: "noteon" | "noteoff" | "cc" | "other";
}

interface MidiDebugOverlayProps {
  events: MidiEventInfo[];
  visible: boolean;
  onClear: () => void;
}

export const MidiDebugOverlay: React.FC<MidiDebugOverlayProps> = ({
  events,
  visible,
  onClear
}) => {
  if (!visible) return null;
  return (
    <div
      style={{
        position: "absolute",
        right: 12,
        bottom: 12,
        width: 260,
        maxHeight: 240,
        overflowY: "auto",
        background: "rgba(0,0,0,0.6)",
        color: "white",
        padding: 8,
        borderRadius: 8,
        fontFamily: "monospace",
        fontSize: 12
      }}
    >
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 4 }}>
        <span>MIDI log (latest first)</span>
        <button
          type="button"
          onClick={onClear}
          style={{
            border: "1px solid rgba(255,255,255,0.4)",
            background: "transparent",
            color: "white",
            borderRadius: 6,
            padding: "2px 6px",
            cursor: "pointer",
            fontSize: 11
          }}
        >
          clear
        </button>
      </div>
      {events.slice(0, 20).map((e, idx) => (
        <div key={idx} style={{ opacity: idx === 0 ? 1 : 0.8 }}>
          {e.type.padEnd(6, " ")} | st=0x{e.status.toString(16).padStart(2, "0")} d1={e.data1
            .toString()
            .padStart(3, " ")} d2={e.data2.toString().padStart(3, " ")} t={e.ts.toFixed(3)}
        </div>
      ))}
      {events.length === 0 && <div style={{ opacity: 0.7 }}>no events</div>}
    </div>
  );
};
