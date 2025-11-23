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
  selectedId?: string;
  onTogglePlay(): void;
  onAddSnapshot(): void;
  onSelectSnapshot(id: string): void;
  onChangeLabel(id: string, label: string): void;
}

export const TimeBar: React.FC<TimeBarProps> = ({
  time,
  isPlaying,
  snapshots,
  onTogglePlay,
  onAddSnapshot,
  onSelectSnapshot,
  selectedId,
  onChangeLabel
}) => {
  const duration = Math.max(10, Math.ceil(time) + 2);
  const normalized = Math.min(1, Math.max(0, time / duration));

  const selected = snapshots.find((s) => s.id === selectedId);

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
          const isSelected = s.id === selectedId;
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
                backgroundColor: isSelected
                  ? "rgba(0,0,0,0.9)"
                  : "rgba(0,0,0,0.55)",
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
      <div
        style={{
          minWidth: 220,
          display: "flex",
          flexDirection: "column",
          alignItems: "flex-end",
          gap: 4
        }}
      >
        <div>t = {time.toFixed(2)}s</div>
        <div>
          <span style={{ marginRight: 4 }}>Label:</span>
          <input
            type="text"
            value={selected?.label ?? ""}
            onChange={(e) =>
              selected &&
              onChangeLabel(selected.id, e.currentTarget.value)
            }
            placeholder={selected ? "Snapshot label" : "Select a snapshot…"}
            disabled={!selected}
            style={{
              fontSize: 11,
              padding: "2px 4px",
              borderRadius: 4,
              border: "1px solid rgba(0,0,0,0.25)",
              width: 140,
              backgroundColor: selected ? "#fffdf7" : "#f1e3cc"
            }}
          />
        </div>
      </div>
    </div>
  );
};
