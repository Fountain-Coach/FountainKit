import React from "react";
import type { PuppetSnapshot } from "../engine/puppetRig";

export interface SnapshotRecord {
  id: string;
  time: number;
  snapshot: PuppetSnapshot;
  label?: string;
}

interface TimeBarProps {
  time: number;
  isPlaying: boolean;
  snapshots: SnapshotRecord[];
  onTogglePlay(): void;
  onAddSnapshot(): void;
  onSelectSnapshot(id: string): void;
}

export const TimeBar: React.FC<TimeBarProps> = ({
  time,
  isPlaying,
  snapshots,
  onTogglePlay,
  onAddSnapshot,
  onSelectSnapshot
}) => {
  const duration = Math.max(10, Math.ceil(time) + 2);
  const normalized = Math.min(1, Math.max(0, time / duration));

  return (
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
        color: "rgba(0,0,0,0.6)",
        gap: 12
      }}
    >
      <button
        type="button"
        onClick={onTogglePlay}
        style={{
          padding: "4px 8px",
          fontSize: 12,
          borderRadius: 4,
          border: "1px solid rgba(0,0,0,0.2)",
          backgroundColor: isPlaying ? "#f3e0c4" : "#fffaf0",
          cursor: "pointer"
        }}
      >
        {isPlaying ? "Pause" : "Play"}
      </button>
      <button
        type="button"
        onClick={onAddSnapshot}
        style={{
          padding: "4px 8px",
          fontSize: 12,
          borderRadius: 4,
          border: "1px solid rgba(0,0,0,0.2)",
          backgroundColor: "#fffaf0",
          cursor: "pointer"
        }}
      >
        Snapshot @ {time.toFixed(2)}s
      </button>
      <div style={{ flex: 1, position: "relative", height: 32 }}>
        <div
          style={{
            position: "absolute",
            left: 0,
            right: 0,
            top: "50%",
            transform: "translateY(-50%)",
            height: 2,
            backgroundColor: "rgba(0,0,0,0.15)"
          }}
        />
        {snapshots.map((s) => {
          const center = Math.min(1, Math.max(0, s.time / duration));
          return (
            <div
              key={s.id}
              title={s.label || `Snapshot @ ${s.time.toFixed(2)}s`}
              onClick={() => onSelectSnapshot(s.id)}
              style={{
                position: "absolute",
                left: `${center * 100}%`,
                top: "50%",
                transform: "translate(-50%, -50%)",
                width: 8,
                height: 16,
                borderRadius: 3,
                backgroundColor: "rgba(0,0,0,0.55)",
                cursor: "pointer"
              }}
            />
          );
        })}
        <div
          style={{
            position: "absolute",
            left: `${normalized * 100}%`,
            top: "50%",
            transform: "translate(-50%, -50%)",
            width: 2,
            height: 24,
            backgroundColor: "rgba(0,0,0,0.9)"
          }}
        />
      </div>
      <div style={{ minWidth: 80, textAlign: "right" }}>
        t = {time.toFixed(2)}s
      </div>
    </div>
  );
};

