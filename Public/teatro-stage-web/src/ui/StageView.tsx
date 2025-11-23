import React, { useRef, useState } from "react";
import type { StageSnapshot } from "../engine/stage";

interface StageViewProps {
  snapshot: StageSnapshot;
}

interface Vec3 {
  x: number;
  y: number;
  z: number;
}

const FRUSTUM_SIZE = 40;
const CAMERA_DISTANCE = 60;
const CAMERA_ELEVATION = Math.atan(1 / Math.sqrt(2));
const LOOK_AT: Vec3 = { x: 0, y: 5, z: 0 };

// Simple orthographic isometric projection of the Teatro room and puppet using
// the camera model from TeatroStageEngine: fixed elevation, orbiting azimuth,
// and a zoom factor in [0.5, 3.0]. We render to a 2D SVG by projecting world
// coordinates through the camera basis.
export const StageView: React.FC<StageViewProps> = ({ snapshot }) => {
  const { puppet } = snapshot;

  const [azimuth, setAzimuth] = useState(Math.PI / 4);
  const [zoom, setZoom] = useState(1);
  const draggingRef = useRef(false);
  const lastXRef = useRef(0);

  const width = 480;
  const height = 320;
  const aspect = width / height;

  const cameraPos: Vec3 = {
    x: CAMERA_DISTANCE * Math.cos(azimuth),
    y: CAMERA_DISTANCE * Math.sin(CAMERA_ELEVATION),
    z: CAMERA_DISTANCE * Math.sin(azimuth)
  };

  const forwardLen = Math.hypot(
    LOOK_AT.x - cameraPos.x,
    LOOK_AT.y - cameraPos.y,
    LOOK_AT.z - cameraPos.z
  );
  const forward: Vec3 = {
    x: (LOOK_AT.x - cameraPos.x) / forwardLen,
    y: (LOOK_AT.y - cameraPos.y) / forwardLen,
    z: (LOOK_AT.z - cameraPos.z) / forwardLen
  };

  const worldUp: Vec3 = { x: 0, y: 1, z: 0 };
  const rightCross: Vec3 = {
    x: forward.y * worldUp.z - forward.z * worldUp.y,
    y: forward.z * worldUp.x - forward.x * worldUp.z,
    z: forward.x * worldUp.y - forward.y * worldUp.x
  };
  const rightLen = Math.hypot(rightCross.x, rightCross.y, rightCross.z) || 1;
  const right: Vec3 = {
    x: rightCross.x / rightLen,
    y: rightCross.y / rightLen,
    z: rightCross.z / rightLen
  };

  const upCross: Vec3 = {
    x: right.y * forward.z - right.z * forward.y,
    y: right.z * forward.x - right.x * forward.z,
    z: right.x * forward.y - right.y * forward.x
  };
  const upLen = Math.hypot(upCross.x, upCross.y, upCross.z) || 1;
  const up: Vec3 = {
    x: upCross.x / upLen,
    y: upCross.y / upLen,
    z: upCross.z / upLen
  };

  const project = (p: Vec3): { x: number; y: number } => {
    const px = p.x - cameraPos.x;
    const py = p.y - cameraPos.y;
    const pz = p.z - cameraPos.z;

    const xCam = px * right.x + py * right.y + pz * right.z;
    const yCam = px * up.x + py * up.y + pz * up.z;

    const halfH = (FRUSTUM_SIZE / 2) / zoom;
    const halfW = ((FRUSTUM_SIZE * aspect) / 2) / zoom;

    const sx = xCam / halfW;
    const sy = yCam / halfH;

    const screenX = (sx * 0.5 + 0.5) * width;
    const screenY = (1 - (sy * 0.5 + 0.5)) * height;

    return { x: screenX, y: screenY };
  };

  const handlePointerDown = (e: React.PointerEvent<SVGSVGElement>) => {
    draggingRef.current = true;
    lastXRef.current = e.clientX;
    e.currentTarget.setPointerCapture(e.pointerId);
  };

  const handlePointerMove = (e: React.PointerEvent<SVGSVGElement>) => {
    if (!draggingRef.current) return;
    const dx = e.clientX - lastXRef.current;
    lastXRef.current = e.clientX;
    setAzimuth((prev) => prev + dx * 0.003);
  };

  const handlePointerUp = (e: React.PointerEvent<SVGSVGElement>) => {
    draggingRef.current = false;
    try {
      e.currentTarget.releasePointerCapture(e.pointerId);
    } catch {
      // ignore
    }
  };

  const handleWheel = (e: React.WheelEvent<SVGSVGElement>) => {
    e.preventDefault();
    const factor = e.deltaY > 0 ? 0.9 : 1.1;
    setZoom((prev) => {
      const next = prev * factor;
      return Math.max(0.5, Math.min(3.0, next));
    });
  };

  // Room geometry in world coordinates.
  const floorWorld: Vec3[] = [
    { x: -15, y: 0, z: 10 },
    { x: 15, y: 0, z: 10 },
    { x: 15, y: 0, z: -10 },
    { x: -15, y: 0, z: -10 }
  ];

  const backWallWorld: Vec3[] = [
    { x: -15, y: 0, z: -10 },
    { x: 15, y: 0, z: -10 },
    { x: 15, y: 20, z: -10 },
    { x: -15, y: 20, z: -10 }
  ];

  const leftWallWorld: Vec3[] = [
    { x: -15, y: 0, z: 10 },
    { x: -15, y: 0, z: -10 },
    { x: -15, y: 20, z: -10 },
    { x: -15, y: 20, z: 10 }
  ];

  const rightWallWorld: Vec3[] = [
    { x: 15, y: 0, z: -10 },
    { x: 15, y: 0, z: 10 },
    { x: 15, y: 20, z: 10 },
    { x: 15, y: 20, z: -10 }
  ];

  const doorWorld: Vec3[] = [
    { x: 15, y: 0, z: -4 },
    { x: 15, y: 0, z: -1 },
    { x: 15, y: 8, z: -1 },
    { x: 15, y: 8, z: -4 }
  ];

  const floorScreen = floorWorld.map(project);
  const backWallScreen = backWallWorld.map(project);
  const leftWallScreen = leftWallWorld.map(project);
  const rightWallScreen = rightWallWorld.map(project);
  const doorScreen = doorWorld.map(project);

  const floorPoints = floorScreen.map((p) => `${p.x},${p.y}`).join(" ");
  const backWallPoints = backWallScreen.map((p) => `${p.x},${p.y}`).join(" ");
  const leftWallPoints = leftWallScreen.map((p) => `${p.x},${p.y}`).join(" ");
  const rightWallPoints = rightWallScreen.map((p) => `${p.x},${p.y}`).join(" ");
  const doorPoints = doorScreen.map((p) => `${p.x},${p.y}`).join(" ");

  // Puppet bodies at z = 0.
  const torsoCenter = project({
    x: puppet.torso.x,
    y: puppet.torso.y,
    z: puppet.torso.z ?? 0
  });
  const headCenter = project({
    x: puppet.head.x,
    y: puppet.head.y,
    z: puppet.head.z ?? 0
  });
  const handL = project({
    x: puppet.handL.x,
    y: puppet.handL.y,
    z: puppet.handL.z ?? 0
  });
  const handR = project({
    x: puppet.handR.x,
    y: puppet.handR.y,
    z: puppet.handR.z ?? 0
  });
  const footL = project({
    x: puppet.footL.x,
    y: puppet.footL.y,
    z: puppet.footL.z ?? 0
  });
  const footR = project({
    x: puppet.footR.x,
    y: puppet.footR.y,
    z: puppet.footR.z ?? 0
  });

  const torsoWidth = 24;
  const torsoHeight = 40;
  const headRadius = 10;

  const torsoTopY = torsoCenter.y - torsoHeight / 2;
  const torsoLeftX = torsoCenter.x - torsoWidth / 2;

  return (
    <svg
      viewBox={`0 0 ${width} ${height}`}
      width="100%"
      height="100%"
      style={{ display: "block", cursor: "grab" }}
      onPointerDown={handlePointerDown}
      onPointerMove={handlePointerMove}
      onPointerUp={handlePointerUp}
      onPointerLeave={handlePointerUp}
      onWheel={handleWheel}
    >
      {/* Paper background */}
      <rect x={0} y={0} width={width} height={height} fill="#f4ead6" />

      {/* Floor */}
      <polygon
        points={floorPoints}
        fill="#f2e3cc"
        stroke="#111111"
        strokeWidth={1}
      />

      {/* Side walls */}
      <polygon
        points={leftWallPoints}
        fill="#f7efdd"
        stroke="#111111"
        strokeWidth={1}
      />
      <polygon
        points={rightWallPoints}
        fill="#f7efdd"
        stroke="#111111"
        strokeWidth={1}
      />

      {/* Back wall */}
      <polygon
        points={backWallPoints}
        fill="#f7efdd"
        stroke="#111111"
        strokeWidth={1}
      />

      {/* Simple door on the right wall (height ≈ 8 units) */}
      <polygon
        points={doorPoints}
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
        cx={headCenter.x}
        cy={headCenter.y}
        r={headRadius}
        fill="#f4ead6"
        stroke="#111111"
        strokeWidth={1}
      />

      {/* Hands */}
      <circle
        cx={handL.x}
        cy={handL.y}
        r={4}
        fill="#f4ead6"
        stroke="#111111"
        strokeWidth={1}
      />
      <circle
        cx={handR.x}
        cy={handR.y}
        r={4}
        fill="#f4ead6"
        stroke="#111111"
        strokeWidth={1}
      />

      {/* Feet */}
      <rect
        x={footL.x - 6}
        y={footL.y - 3}
        width={12}
        height={6}
        fill="#f4ead6"
        stroke="#111111"
        strokeWidth={1}
      />
      <rect
        x={footR.x - 6}
        y={footR.y - 3}
        width={12}
        height={6}
        fill="#f4ead6"
        stroke="#111111"
        strokeWidth={1}
      />

      {/* Simple floor spotlight */}
      <ellipse
        cx={torsoCenter.x}
        cy={footL.y + 10}
        rx={40}
        ry={10}
        fill="#f1e1c9"
      />
    </svg>
  );
}
