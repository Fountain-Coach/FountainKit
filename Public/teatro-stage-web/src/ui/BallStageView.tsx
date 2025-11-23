import React, { useRef, useState } from "react";
import type { BallStageSnapshot } from "../engine/ballStage";
import {
  type CameraState,
  type Vec3Like,
  computeBallScreenCenter,
  computeFloorScreenY,
  projectWorldToScreen
} from "../engine/camera";

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

  const cameraState: CameraState = {
    azimuth,
    zoom,
    width,
    height
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
  const floorWorld: Vec3Like[] = [
    { x: -15, y: 0, z: 10 },
    { x: 15, y: 0, z: 10 },
    { x: 15, y: 0, z: -10 },
    { x: -15, y: 0, z: -10 }
  ];

  const backWallWorld: Vec3Like[] = [
    { x: -15, y: 0, z: -10 },
    { x: 15, y: 0, z: -10 },
    { x: 15, y: 20, z: -10 },
    { x: -15, y: 20, z: -10 }
  ];

  const leftWallWorld: Vec3Like[] = [
    { x: -15, y: 0, z: 10 },
    { x: -15, y: 0, z: -10 },
    { x: -15, y: 20, z: -10 },
    { x: -15, y: 20, z: 10 }
  ];

  const rightWallWorld: Vec3Like[] = [
    { x: 15, y: 0, z: -10 },
    { x: 15, y: 0, z: 10 },
    { x: 15, y: 20, z: 10 },
    { x: 15, y: 20, z: -10 }
  ];

  const doorWorld: Vec3Like[] = [
    { x: 15, y: 0, z: -4 },
    { x: 15, y: 0, z: -1 },
    { x: 15, y: 8, z: -1 },
    { x: 15, y: 8, z: -4 }
  ];

  const floorScreen = floorWorld.map((p) => projectWorldToScreen(p, cameraState));
  const backWallScreen = backWallWorld.map((p) =>
    projectWorldToScreen(p, cameraState)
  );
  const leftWallScreen = leftWallWorld.map((p) =>
    projectWorldToScreen(p, cameraState)
  );
  const rightWallScreen = rightWallWorld.map((p) =>
    projectWorldToScreen(p, cameraState)
  );
  const doorScreen = doorWorld.map((p) =>
    projectWorldToScreen(p, cameraState)
  );

  const floorPoints = floorScreen.map((p) => `${p.x},${p.y}`).join(" ");
  const backWallPoints = backWallScreen.map((p) => `${p.x},${p.y}`).join(" ");
  const leftWallPoints = leftWallScreen.map((p) => `${p.x},${p.y}`).join(" ");
  const rightWallPoints = rightWallScreen.map((p) => `${p.x},${p.y}`).join(" ");
  const doorPoints = doorScreen.map((p) => `${p.x},${p.y}`).join(" ");

  const ballRadius = 8;
  const ballCenter = computeBallScreenCenter(
    {
      x: ball.position.x,
      y: ball.position.y,
      z: ball.position.z
    },
    cameraState,
    1,
    ballRadius
  );

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
