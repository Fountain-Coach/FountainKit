import { Body, DistanceConstraint, Vec3, World } from "./physics";

export interface PuppetSnapshot {
  bar: Vec3;
  torso: Vec3;
  head: Vec3;
  handL: Vec3;
  handR: Vec3;
  footL: Vec3;
  footR: Vec3;
}

export class PuppetRig {
  readonly world: World;
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

    this.barBody = new Body(new Vec3(0, 15, 0), 0.1);
    this.torsoBody = new Body(new Vec3(0, 8, 0), 1.0);
    this.headBody = new Body(new Vec3(0, 10, 0), 0.5);
    this.handLBody = new Body(new Vec3(-1.8, 8, 0), 0.3);
    this.handRBody = new Body(new Vec3(1.8, 8, 0), 0.3);
    this.footLBody = new Body(new Vec3(-0.6, 5, 0), 0.4);
    this.footRBody = new Body(new Vec3(0.6, 5, 0), 0.4);

    const bodies = [
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

    // Skeleton
    addDistance(this.torsoBody, this.headBody, 0.8);
    addDistance(this.torsoBody, this.handLBody, 0.8);
    addDistance(this.torsoBody, this.handRBody, 0.8);
    addDistance(this.torsoBody, this.footLBody, 0.8);
    addDistance(this.torsoBody, this.footRBody, 0.8);
    // Strings
    addDistance(this.barBody, this.headBody, 0.9);
    addDistance(this.barBody, this.handLBody, 0.9);
    addDistance(this.barBody, this.handRBody, 0.9);
  }

  step(dt: number, time: number): void {
    this.driveBar(time);
    this.world.step(dt);
  }

  snapshot(): PuppetSnapshot {
    return {
      bar: this.barBody.position.clone(),
      torso: this.torsoBody.position.clone(),
      head: this.headBody.position.clone(),
      handL: this.handLBody.position.clone(),
      handR: this.handRBody.position.clone(),
      footL: this.footLBody.position.clone(),
      footR: this.footRBody.position.clone()
    };
  }

  private driveBar(time: number): void {
    const sway = Math.sin(time * 0.7) * 2.0;
    const upDown = Math.sin(time * 0.9) * 0.5;
    this.barBody.position.x = sway;
    this.barBody.position.y = 15 + upDown;
    this.barBody.position.z = 0;
  }
}

