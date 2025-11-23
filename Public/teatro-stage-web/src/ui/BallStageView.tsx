import React, { useRef, useState } from "react";
import type { BallStageSnapshot } from "../engine/ballStage";

interface BallStageViewProps {
  snapshot: BallStageSnapshot;
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

// Isometric projection of the Teatro room and a single ball using the same
// camera model as the puppet view. This view intentionally draws only the
// three‑sided room and the ball; no puppet or other props are present.
export const BallStageView: React.FC<BallStageViewProps> = ({ snapshot }) => {
  const { ball } = snapshot;

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

  // World-space ball radius matches the baseline (r = 1). We derive the
  // screen-space placement from the projected bottom point so that, when the
  // ball rests on the floor (bottom at y = 0), the circle visually sits on the
  // drawn floor polygon instead of appearing to fall through it.
  const ballRadiusWorld = 1;
  const ballBottomWorld: Vec3 = {
    x: ball.position.x,
    y: Math.max(0, ball.position.y - ballRadiusWorld),
    z: ball.position.z
  };
  const ballBottomScreen = project(ballBottomWorld);
  const ballRadius = 8;
  const ballCenter = {
    x: ballBottomScreen.x,
    y: ballBottomScreen.y - ballRadius
  };

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

      {/* Door on the right wall */}
      <polygon
        points={doorPoints}
        fill="#f4ead6"
        stroke="#111111"
        strokeWidth={1}
      />

      {/* Ball */}
      <circle
        cx={ballCenter.x}
        cy={ballCenter.y}
        r={ballRadius}
        fill="#f4ead6"
        stroke="#111111"
        strokeWidth={1}
      />
    </svg>
  );
};
