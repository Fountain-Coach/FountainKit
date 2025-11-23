import React from "react";
import type { StageSnapshot } from "../engine/stage";

interface StageViewProps {
  snapshot: StageSnapshot;
}

// Simple 2D projection of the Teatro room and puppet using the canonical world
// coordinates from TeatroStageEngine specs. This stays intentionally minimal:
// it draws a front‑on room and uses a linear mapping from world space
// (X ∈ [-15, 15], Y ∈ [0, 20]) into SVG space.
export const StageView: React.FC<StageViewProps> = ({ snapshot }) => {
  const { puppet } = snapshot;

  const width = 480;
  const height = 320;

  // Room coordinates in SVG space.
  const floorTop = 220;
  const floorHeight = 40;
  const wallHeight = 120;
  const roomLeft = 60;
  const roomRight = width - 60;

  const roomWidthPx = roomRight - roomLeft;

  const worldToScreenX = (x: number): number =>
    roomLeft + ((x + 15) / 30) * roomWidthPx;

  const worldToScreenY = (y: number): number =>
    floorTop - (y / 20) * wallHeight;

  const torsoWidth = 24;
  const torsoHeight = 40;
  const headRadius = 10;

  const torsoCenterX = worldToScreenX(puppet.torso.x);
  const torsoCenterY = worldToScreenY(puppet.torso.y);
  const torsoTopY = torsoCenterY - torsoHeight / 2;
  const torsoLeftX = torsoCenterX - torsoWidth / 2;

  const headCenterX = worldToScreenX(puppet.head.x);
  const headCenterY = worldToScreenY(puppet.head.y);

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

      {/* Simple door on the right wall (height ≈ 8 units) */}
      <rect
        x={roomRight - 40}
        y={floorTop - (8 / 20) * wallHeight}
        width={24}
        height={(8 / 20) * wallHeight}
        fill="#f4ead6"
        stroke="#111111"
        strokeWidth={1}
      />

      {/* Puppet torso */}
      <rect
        x={torsoLeftX}
        y={torsoTopY}
        width={torsoWidth}
        height={torsoHeight}
        fill="#f4ead6"
        stroke="#111111"
        strokeWidth={1}
      />

      {/* Puppet head */}
      <circle
        cx={headCenterX}
        cy={headCenterY}
        r={headRadius}
        fill="#f4ead6"
        stroke="#111111"
        strokeWidth={1}
      />

      {/* Simple floor spotlight */}
      <ellipse
        cx={torsoCenterX}
        cy={floorTop + floorHeight - 6}
        rx={40}
        ry={10}
        fill="#f1e1c9"
      />
    </svg>
  );
}
