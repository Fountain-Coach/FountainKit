import React from "react";
import type { StageSnapshot } from "../engine/stage";

interface DiagPanelProps {
  snapshot: StageSnapshot | null;
  onHide: () => void;
}

export const DiagPanel: React.FC<DiagPanelProps> = ({ snapshot, onHide }) => {
  const lines: string[] = [];
  if (snapshot) {
    lines.push(`t=${snapshot.time.toFixed(3)}`);
    const b = snapshot.puppet.bar.position;
    lines.push(`bar=(${b.x.toFixed(2)},${b.y.toFixed(2)},${b.z?.toFixed(2) ?? "0"})`);
  } else {
    lines.push("no snapshot");
  }

  return (
    <div
      style={{
        position: "absolute",
        right: 12,
        top: 12,
        background: "rgba(0,0,0,0.7)",
        color: "white",
        padding: 12,
        borderRadius: 10,
        fontFamily: "monospace",
        fontSize: 12,
        animation: "fadein 0.2s ease-out",
        pointerEvents: "auto"
      }}
      onMouseLeave={() => setTimeout(onHide, 800)}
    >
      {lines.map((l, i) => (
        <div key={i}>{l}</div>
      ))}
      <style>
        {`@keyframes fadein { from { opacity: 0; transform: translateY(-6px); } to { opacity: 1; transform: translateY(0); } }`}
      </style>
    </div>
  );
};
