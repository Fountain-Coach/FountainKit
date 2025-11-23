import { describe, it, expect } from "vitest";
import {
  type CameraState,
  computeBallScreenCenter,
  computeFloorScreenY
} from "./camera";

const WIDTH = 480;
const HEIGHT = 320;

describe("camera projection", () => {
  it("draws ball bottom on the projected floor when at rest", () => {
    const state: CameraState = {
      azimuth: Math.PI / 4,
      zoom: 1,
      width: WIDTH,
      height: HEIGHT
    };

    const floorY = computeFloorScreenY(state);

    // Ball at rest on the floor in world coordinates: centre at y = 1, radius
    // 1. The BallStageView logic uses a worldRadius of 1 and a fixed
    // pixelRadius; the circle's bottom should line up with the projected floor.
    const ballCenter = computeBallScreenCenter(
      { x: 0, y: 1, z: 0 },
      state,
      1,
      8
    );
    const ballBottomY = ballCenter.y + 8;

    expect(Math.abs(ballBottomY - floorY)).toBeLessThanOrEqual(1);
  });
});

