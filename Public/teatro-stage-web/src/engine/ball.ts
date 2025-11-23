import { Body, GroundConstraint, Vec3, World } from "./physics";

export interface BallSnapshot {
  time: number;
  position: Vec3;
  velocity: Vec3;
}

/**
 * Minimal Cannon‑ES scene mirroring the TPBallScene baseline in
 * TeatroStageEngine. It owns a single dynamic body representing the ball and a
 * ground plane at y = 0, and exposes a small step/snapshot API for tests and
 * hosts.
 */
export class BallWorld {
  readonly world: World;
  readonly ballBody: Body;
  readonly radius: number;

  private timeSeconds = 0;

  constructor(
    initialPosition: Vec3 = new Vec3(0, 12, 0),
    radius = 1.0,
    mass = 1.0
  ) {
    this.radius = radius;
    this.world = new World();
    this.world.gravity = new Vec3(0, -9.82, 0);
    this.world.linearDamping = 0.02;

    const halfExtents = new Vec3(radius, radius, radius);
    this.ballBody = new Body(initialPosition.clone(), mass, halfExtents);
    this.world.addBody(this.ballBody);

    // Floor at y = 0 with a bit of restitution so the ball bounces before
    // settling under damping.
    this.world.addConstraint(new GroundConstraint(0, 0.4));
  }

  step(dtSeconds: number): void {
    if (dtSeconds <= 0) return;
    this.timeSeconds += dtSeconds;
    this.world.step(dtSeconds);
  }

  snapshot(): BallSnapshot {
    return {
      time: this.timeSeconds,
      position: this.ballBody.position.clone(),
      velocity: this.ballBody.velocity.clone() as Vec3
    };
  }

  /**
   * Convenience for the thrown-ball scenario: set a horizontal speed in the
   * +X direction, resetting vertical/forward velocity.
   */
  setHorizontalSpeed(speed: number): void {
    this.ballBody.velocity.set(speed, 0, 0);
  }
}
