import React, { useEffect, useRef, useState } from "react";
import { StageView } from "./StageView";
import { PuppetRig, type PuppetSnapshot } from "../engine/puppetRig";
import { TimeBar, type SnapshotRecord } from "./TimeBar";

export const TeatroStageApp: React.FC = () => {
  const rigRef = useRef<PuppetRig | null>(null);
  const timeRef = useRef(0);
  const [time, setTime] = useState(0);
  const [snapshot, setSnapshot] = useState<PuppetSnapshot | null>(null);
  const [isPlaying, setIsPlaying] = useState(true);
  const playingRef = useRef(true);
  const [snapshots, setSnapshots] = useState<SnapshotRecord[]>([]);

  useEffect(() => {
    rigRef.current = new PuppetRig();
    const rig = rigRef.current;
    const initial = rig.snapshot();
    setSnapshot(initial);
    timeRef.current = 0;
    setTime(0);

    let last = performance.now();
    let frameId: number;
    const loop = () => {
      frameId = requestAnimationFrame(loop);
      const now = performance.now();
      const dt = (now - last) / 1000;
      last = now;
      if (!playingRef.current || !rigRef.current) return;
      const nextTime = timeRef.current + dt;
      rigRef.current.step(dt, nextTime);
      timeRef.current = nextTime;
      setTime(nextTime);
      setSnapshot(rigRef.current.snapshot());
    };
    loop();

    return () => {
      cancelAnimationFrame(frameId);
    };
  }, []);

  const handleTogglePlay = () => {
    const next = !isPlaying;
    setIsPlaying(next);
    playingRef.current = next;
  };

  const handleAddSnapshot = () => {
    if (!snapshot) return;
    const id =
      typeof crypto !== "undefined" && "randomUUID" in crypto
        ? (crypto.randomUUID() as string)
        : `snap-${Date.now()}-${Math.random().toString(16).slice(2)}`;
    setSnapshots((prev) => [
      ...prev,
      { id, time, snapshot, label: undefined }
    ]);
  };

  const handleSelectSnapshot = (id: string) => {
    const rec = snapshots.find((s) => s.id === id);
    if (!rec || !rigRef.current) return;
    playingRef.current = false;
    setIsPlaying(false);
    rigRef.current.applySnapshot(rec.snapshot);
    timeRef.current = rec.time;
    setTime(rec.time);
    setSnapshot(rec.snapshot);
  };

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
          {snapshot && <StageView snapshot={snapshot} />}
        </div>
        <TimeBar
          time={time}
          isPlaying={isPlaying}
          snapshots={snapshots}
          onTogglePlay={handleTogglePlay}
          onAddSnapshot={handleAddSnapshot}
          onSelectSnapshot={handleSelectSnapshot}
        />
      </main>
    </div>
  );
};
