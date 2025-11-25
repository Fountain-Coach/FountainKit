import * as CANNON from "cannon-es";

export interface BodyPose {
  position: { x: number; y: number; z: number };
  quaternion: { x: number; y: number; z: number; w: number };
}

export interface PuppetSnapshot {
  bar: BodyPose;
  torso: BodyPose;
  head: BodyPose;
  handL: BodyPose;
  handR: BodyPose;
  footL: BodyPose;
  footR: BodyPose;
  strings: Array<{ a: { x: number; y: number; z: number }; b: { x: number; y: number; z: number } }>;
}

// Canonical rig constants lifted from demo1.html (Three.js + Cannon).
const RIG = {
  bar: { size: { x: 10, y: 0.2, z: 0.2 }, mass: 0.1, pos: { x: 0, y: 15, z: 0 } },
  torso: { size: { x: 1.6, y: 3.0, z: 0.8 }, mass: 1.0, pos: { x: 0, y: 8, z: 0 } },
  head: { size: { x: 1.1, y: 1.1, z: 0.8 }, mass: 0.5, pos: { x: 0, y: 10, z: 0 } },
  handL: { size: { x: 0.4, y: 2.0, z: 0.4 }, mass: 0.3, pos: { x: -1.8, y: 8, z: 0 } },
  handR: { size: { x: 0.4, y: 2.0, z: 0.4 }, mass: 0.3, pos: { x: 1.8, y: 8, z: 0 } },
  footL: { size: { x: 0.5, y: 2.2, z: 0.5 }, mass: 0.4, pos: { x: -0.6, y: 5, z: 0 } },
  footR: { size: { x: 0.5, y: 2.2, z: 0.5 }, mass: 0.4, pos: { x: 0.6, y: 5, z: 0 } }
} as const;

const STRING_PIVOTS = {
  barToHead: { a: new CANNON.Vec3(0, 0, 0), b: new CANNON.Vec3(0, 0.5, 0) },
  barToHandL: { a: new CANNON.Vec3(-2.5, 0, 0), b: new CANNON.Vec3(0, 1.0, 0) },
  barToHandR: { a: new CANNON.Vec3(2.5, 0, 0), b: new CANNON.Vec3(0, 1.0, 0) }
} as const;

export class PuppetRig {
  readonly world: CANNON.World;
  private readonly barBody: CANNON.Body;
  private readonly torsoBody: CANNON.Body;
  private readonly headBody: CANNON.Body;
  private readonly handLBody: CANNON.Body;
  private readonly handRBody: CANNON.Body;
  private readonly footLBody: CANNON.Body;
  private readonly footRBody: CANNON.Body;
  private readonly stringConstraints: CANNON.DistanceConstraint[];
  private readonly barBase: CANNON.Vec3;

  constructor() {
    this.world = new CANNON.World();
    this.world.broadphase = new CANNON.NaiveBroadphase();
    this.world.gravity.set(0, -9.82, 0);
    this.world.solver.iterations = 20;

    // Ground plane (y=0).
    const ground = new CANNON.Body({ mass: 0, shape: new CANNON.Plane() });
    ground.quaternion.setFromAxisAngle(new CANNON.Vec3(1, 0, 0), -Math.PI / 2);
    this.world.addBody(ground);

    // Helper to build a body.
    const makeBoxBody = (size: { x: number; y: number; z: number }, mass: number, pos: { x: number; y: number; z: number }) => {
      const shape = new CANNON.Box(new CANNON.Vec3(size.x / 2, size.y / 2, size.z / 2));
      const body = new CANNON.Body({ mass, shape });
      body.position.set(pos.x, pos.y, pos.z);
      body.linearDamping = 0.02;
      this.world.addBody(body);
      return body;
    };

    this.barBody = makeBoxBody(RIG.bar.size, RIG.bar.mass, RIG.bar.pos);
    this.barBody.type = CANNON.Body.KINEMATIC;
    this.barBody.updateMassProperties();
    this.barBody.allowSleep = false;
    this.barBody.angularDamping = 1.0;
    this.barBody.linearDamping = 1.0;
    this.torsoBody = makeBoxBody(RIG.torso.size, RIG.torso.mass, RIG.torso.pos);
    this.headBody = makeBoxBody(RIG.head.size, RIG.head.mass, RIG.head.pos);
    this.handLBody = makeBoxBody(RIG.handL.size, RIG.handL.mass, RIG.handL.pos);
    this.handRBody = makeBoxBody(RIG.handR.size, RIG.handR.mass, RIG.handR.pos);
    this.footLBody = makeBoxBody(RIG.footL.size, RIG.footL.mass, RIG.footL.pos);
    this.footRBody = makeBoxBody(RIG.footR.size, RIG.footR.mass, RIG.footR.pos);

    const addP2P = (bodyA: CANNON.Body, pivotA: CANNON.Vec3, bodyB: CANNON.Body, pivotB: CANNON.Vec3) => {
      const c = new CANNON.PointToPointConstraint(bodyA, pivotA, bodyB, pivotB, 1e4);
      this.world.addConstraint(c);
    };

    // Skeleton constraints
    addP2P(this.torsoBody, new CANNON.Vec3(0, 1.6, 0), this.headBody, new CANNON.Vec3(0, -0.5, 0)); // torso ↔ head
    addP2P(this.torsoBody, new CANNON.Vec3(-0.8, 1.2, 0), this.handLBody, new CANNON.Vec3(0, 1.0, 0)); // torso ↔ handL
    addP2P(this.torsoBody, new CANNON.Vec3(0.8, 1.2, 0), this.handRBody, new CANNON.Vec3(0, 1.0, 0)); // torso ↔ handR
    addP2P(this.torsoBody, new CANNON.Vec3(-0.4, -1.4, 0), this.footLBody, new CANNON.Vec3(0, 1.0, 0)); // torso ↔ footL
    addP2P(this.torsoBody, new CANNON.Vec3(0.4, -1.4, 0), this.footRBody, new CANNON.Vec3(0, 1.0, 0)); // torso ↔ footR

    // Strings (DistanceConstraint with stored pivots for rendering)
    this.stringConstraints = [];
    const addString = (bodyA: CANNON.Body, pivotA: CANNON.Vec3, bodyB: CANNON.Body, pivotB: CANNON.Vec3) => {
      const c = new CANNON.DistanceConstraint(bodyA, bodyB, undefined, 5e3);
      (c as any).pivotA = pivotA.clone();
      (c as any).pivotB = pivotB.clone();
      this.world.addConstraint(c);
      this.stringConstraints.push(c);
    };

    addString(this.barBody, STRING_PIVOTS.barToHead.a, this.headBody, STRING_PIVOTS.barToHead.b);
    addString(this.barBody, STRING_PIVOTS.barToHandL.a, this.handLBody, STRING_PIVOTS.barToHandL.b);
    addString(this.barBody, STRING_PIVOTS.barToHandR.a, this.handRBody, STRING_PIVOTS.barToHandR.b);

    this.barBase = this.barBody.position.clone();
  }

  step(dtSeconds: number, timeSeconds: number): void {
    if (dtSeconds <= 0) return;
    // Drive bar motion (same as demo1).
    const sway = Math.sin(timeSeconds * 0.7) * 2.0;
    const upDown = Math.sin(timeSeconds * 0.9) * 0.5;
    this.barBody.position.x = this.barBase.x + sway;
    this.barBody.position.y = this.barBase.y + upDown;
    this.barBody.position.z = this.barBase.z;
    this.barBody.quaternion.set(0, 0, 0, 1);
    this.barBody.velocity.set(0, 0, 0);
    this.barBody.angularVelocity.set(0, 0, 0);

    // Clamp dt like the demo to avoid instability.
    const dtClamped = Math.min(dtSeconds, 1 / 30);
    this.world.step(1 / 60, dtClamped, 3);
  }

  snapshot(): PuppetSnapshot {
    const pose = (body: CANNON.Body): BodyPose => ({
      position: { x: body.position.x, y: body.position.y, z: body.position.z },
      quaternion: {
        x: body.quaternion.x,
        y: body.quaternion.y,
        z: body.quaternion.z,
        w: body.quaternion.w
      }
    });

    const strings = this.stringConstraints.map((c) => {
      const pa = new CANNON.Vec3();
      const pb = new CANNON.Vec3();
      const pivotA = (c as any).pivotA as CANNON.Vec3;
      const pivotB = (c as any).pivotB as CANNON.Vec3;
      c.bodyA.pointToWorldFrame(pivotA, pa);
      c.bodyB.pointToWorldFrame(pivotB, pb);
      return {
        a: { x: pa.x, y: pa.y, z: pa.z },
        b: { x: pb.x, y: pb.y, z: pb.z }
      };
    });

    return {
      bar: pose(this.barBody),
      torso: pose(this.torsoBody),
      head: pose(this.headBody),
      handL: pose(this.handLBody),
      handR: pose(this.handRBody),
      footL: pose(this.footLBody),
      footR: pose(this.footRBody),
      strings
    };
  }
}
