import { Body, DistanceConstraint, GroundConstraint, Vec3, World } from "./physics";

export interface PuppetSnapshot {
  controller: Vec3;
  bar: Vec3;
  torso: Vec3;
  head: Vec3;
  handL: Vec3;
  handR: Vec3;
  footL: Vec3;
  footR: Vec3;
}

// Puppet rig parameters are aligned with TeatroStageEngine/spec/rig-puppet mechanics
// and geometry: controller at (0,19,0), bar at (0,15,0), torso/head/hands/feet as
// documented there. Rest lengths for strings are derived from these positions.
export class PuppetRig {
  readonly world: World;
  readonly controllerBody: Body;
  readonly barBody: Body;
  readonly torsoBody: Body;
  readonly headBody: Body;
  readonly handLBody: Body;
  readonly handRBody: Body;
  readonly footLBody: Body;
  readonly footRBody: Body;

  constructor() {
    this.world = new World();
    this.world.gravity = new Vec3(0, -9.82, 0);
    this.world.linearDamping = 0.02;

    this.controllerBody = new Body(new Vec3(0, 19, 0), 0.1);
    this.barBody = new Body(new Vec3(0, 15, 0), 0.1);
    this.torsoBody = new Body(new Vec3(0, 8, 0), 1.0);
    this.headBody = new Body(new Vec3(0, 10, 0), 0.5);
    this.handLBody = new Body(new Vec3(-1.8, 8, 0), 0.3);
    this.handRBody = new Body(new Vec3(1.8, 8, 0), 0.3);
    this.footLBody = new Body(new Vec3(-0.6, 5, 0), 0.4);
    this.footRBody = new Body(new Vec3(0.6, 5, 0), 0.4);

    const bodies = [
      this.controllerBody,
      this.barBody,
      this.torsoBody,
      this.headBody,
      this.handLBody,
      this.handRBody,
      this.footLBody,
      this.footRBody
    ];
    for (const b of bodies) {
      this.world.addBody(b);
    }

    const addDistance = (a: Body, b: Body, stiffness = 0.9) => {
      const delta = Vec3.subtract(b.position, a.position);
      const rest = delta.length();
      this.world.addConstraint(new DistanceConstraint(a, b, rest, stiffness));
    };

    // Skeleton constraints (torso ↔ head/hands/feet)
    addDistance(this.torsoBody, this.headBody, 0.8);
    addDistance(this.torsoBody, this.handLBody, 0.8);
    addDistance(this.torsoBody, this.handRBody, 0.8);
    addDistance(this.torsoBody, this.footLBody, 0.8);
    addDistance(this.torsoBody, this.footRBody, 0.8);

    // Strings: controller ↔ bar/hands and bar ↔ head
    addDistance(this.controllerBody, this.barBody, 0.9);
    addDistance(this.controllerBody, this.handLBody, 0.9);
    addDistance(this.controllerBody, this.handRBody, 0.9);
    addDistance(this.barBody, this.headBody, 0.8);

    // Ground plane at y = 0 so feet cannot penetrate the floor.
    this.world.addConstraint(new GroundConstraint(0));
  }

  step(dt: number, time: number): void {
    this.driveController(time);
    this.world.step(dt);
  }

  snapshot(): PuppetSnapshot {
    return {
      controller: this.controllerBody.position.clone(),
      bar: this.barBody.position.clone(),
      torso: this.torsoBody.position.clone(),
      head: this.headBody.position.clone(),
      handL: this.handLBody.position.clone(),
      handR: this.handRBody.position.clone(),
      footL: this.footLBody.position.clone(),
      footR: this.footRBody.position.clone()
    };
  }

  private driveController(time: number): void {
    const sway = Math.sin(time * 0.7) * 2.0;
    const upDown = Math.sin(time * 0.9) * 0.5;
    this.controllerBody.position.x = sway;
    this.controllerBody.position.y = 19 + upDown;
    this.controllerBody.position.z = 0;
  }
}

