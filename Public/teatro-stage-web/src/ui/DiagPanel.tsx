import React from "react";
import type { StageSnapshot } from "../engine/stage";

interface DiagPanelProps {
  snapshot: StageSnapshot | null;
}

export const DiagPanel: React.FC<DiagPanelProps> = ({ snapshot }) => {
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
        background: "rgba(0,0,0,0.6)",
        color: "white",
        padding: 8,
        borderRadius: 8,
        fontFamily: "monospace",
        fontSize: 12
      }}
    >
      {lines.map((l, i) => (
        <div key={i}>{l}</div>
      ))}
    </div>
  );
};
