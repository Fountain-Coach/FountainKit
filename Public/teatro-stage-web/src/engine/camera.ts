export interface Vec3Like {
  x: number;
  y: number;
  z: number;
}

export interface CameraState {
  azimuth: number;
  zoom: number;
  width: number;
  height: number;
}

export const FRUSTUM_SIZE = 40;
export const CAMERA_DISTANCE = 60;
export const CAMERA_ELEVATION = Math.atan(1 / Math.sqrt(2));
export const LOOK_AT: Vec3Like = { x: 0, y: 5, z: 0 };

export function projectWorldToScreen(
  point: Vec3Like,
  state: CameraState
): { x: number; y: number } {
  const { azimuth, zoom, width, height } = state;
  const aspect = width / height;

  const cameraPos: Vec3Like = {
    x: CAMERA_DISTANCE * Math.cos(azimuth),
    y: CAMERA_DISTANCE * Math.sin(CAMERA_ELEVATION),
    z: CAMERA_DISTANCE * Math.sin(azimuth)
  };

  const forwardLen = Math.hypot(
    LOOK_AT.x - cameraPos.x,
    LOOK_AT.y - cameraPos.y,
    LOOK_AT.z - cameraPos.z
  );
  const forward: Vec3Like = {
    x: (LOOK_AT.x - cameraPos.x) / forwardLen,
    y: (LOOK_AT.y - cameraPos.y) / forwardLen,
    z: (LOOK_AT.z - cameraPos.z) / forwardLen
  };

  const worldUp: Vec3Like = { x: 0, y: 1, z: 0 };
  const rightCross: Vec3Like = {
    x: forward.y * worldUp.z - forward.z * worldUp.y,
    y: forward.z * worldUp.x - forward.x * worldUp.z,
    z: forward.x * worldUp.y - forward.y * worldUp.x
  };
  const rightLen = Math.hypot(rightCross.x, rightCross.y, rightCross.z) || 1;
  const right: Vec3Like = {
    x: rightCross.x / rightLen,
    y: rightCross.y / rightLen,
    z: rightCross.z / rightLen
  };

  const upCross: Vec3Like = {
    x: right.y * forward.z - right.z * forward.y,
    y: right.z * forward.x - right.x * forward.z,
    z: right.x * forward.y - right.y * forward.x
  };
  const upLen = Math.hypot(upCross.x, upCross.y, upCross.z) || 1;
  const up: Vec3Like = {
    x: upCross.x / upLen,
    y: upCross.y / upLen,
    z: upCross.z / upLen
  };

  const px = point.x - cameraPos.x;
  const py = point.y - cameraPos.y;
  const pz = point.z - cameraPos.z;

  const xCam = px * right.x + py * right.y + pz * right.z;
  const yCam = px * up.x + py * up.y + pz * up.z;

  const halfH = (FRUSTUM_SIZE / 2) / zoom;
  const halfW = ((FRUSTUM_SIZE * aspect) / 2) / zoom;

  const sx = xCam / halfW;
  const sy = yCam / halfH;

  const screenX = (sx * 0.5 + 0.5) * width;
  const screenY = (1 - (sy * 0.5 + 0.5)) * height;

  return { x: screenX, y: screenY };
}

export function computeBallScreenCenter(
  center: Vec3Like,
  state: CameraState,
  worldRadius: number,
  pixelRadius: number
): { x: number; y: number } {
  const bottomWorld: Vec3Like = {
    x: center.x,
    y: Math.max(0, center.y - worldRadius),
    z: center.z
  };
  const bottomScreen = projectWorldToScreen(bottomWorld, state);
  return {
    x: bottomScreen.x,
    y: bottomScreen.y - pixelRadius
  };
}

export function computeFloorScreenY(state: CameraState): number {
  const floor = projectWorldToScreen({ x: 0, y: 0, z: 0 }, state);
  return floor.y;
}

