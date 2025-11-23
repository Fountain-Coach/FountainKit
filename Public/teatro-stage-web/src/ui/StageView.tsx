import React from "react";

interface StageViewProps {
  time: number;
}

// Simple 2D stage sketch that mirrors the three‑sided room and a single puppet
// body at a rough “waist height”. This is a placeholder while the new
// Cannon‑backed engine wrapper is rebuilt from the TeatroStageEngine specs.
export const StageView: React.FC<StageViewProps> = ({ time }) => {
  // Gentle sway for the puppet to keep the scene alive without relying on the
  // old physics wrapper. Numbers are intentionally small; the authoritative
  // behaviour still lives in TeatroStageEngine.
  const sway = Math.sin(time * 0.8) * 10;

  const width = 480;
  const height = 320;

  // Room coordinates in SVG space.
  const floorTop = 220;
  const floorHeight = 40;
  const wallHeight = 120;
  const roomLeft = 60;
  const roomRight = width - 60;

  const puppetX = (roomLeft + roomRight) / 2;
  const puppetBaseY = floorTop;
  const puppetTorsoHeight = 40;
  const puppetHeadRadius = 10;

  const torsoTopY = puppetBaseY - puppetTorsoHeight + sway * 0.2;
  const headCenterY = torsoTopY - puppetHeadRadius * 1.4;

  return (
    <svg
      viewBox={`0 0 ${width} ${height}`}
      width="100%"
      height="100%"
      style={{ display: "block" }}
    >
      {/* Paper background */}
      <rect x={0} y={0} width={width} height={height} fill="#f4ead6" />

      {/* Floor */}
      <rect
        x={roomLeft}
        y={floorTop}
        width={roomRight - roomLeft}
        height={floorHeight}
        fill="#f2e3cc"
        stroke="#111111"
        strokeWidth={1}
      />

      {/* Back wall */}
      <rect
        x={roomLeft}
        y={floorTop - wallHeight}
        width={roomRight - roomLeft}
        height={wallHeight}
        fill="#f7efdd"
        stroke="#111111"
        strokeWidth={1}
      />

      {/* Simple door on the right wall */}
      <rect
        x={roomRight - 40}
        y={floorTop - 60}
        width={24}
        height={60}
        fill="#f4ead6"
        stroke="#111111"
        strokeWidth={1}
      />

      {/* Puppet torso */}
      <rect
        x={puppetX - 12}
        y={torsoTopY}
        width={24}
        height={puppetTorsoHeight}
        fill="#f4ead6"
        stroke="#111111"
        strokeWidth={1}
      />

      {/* Puppet head */}
      <circle
        cx={puppetX}
        cy={headCenterY}
        r={puppetHeadRadius}
        fill="#f4ead6"
        stroke="#111111"
        strokeWidth={1}
      />

      {/* Simple floor spotlight */}
      <ellipse
        cx={puppetX}
        cy={floorTop + floorHeight - 6}
        rx={40}
        ry={10}
        fill="#f1e1c9"
      />
    </svg>
  );
}

