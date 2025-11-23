import * as CANNON from "cannon-es";

// Minimal Cannon‑ES wrappers aligned with TeatroStageEngine physics specs.
// World coordinates:
// - right‑handed, y up
// - floor plane at y = 0
// - stage room: X ∈ [-15, 15], Z ∈ [-10, 10], Y ∈ [0, 20]

export class Vec3 extends CANNON.Vec3 {
  constructor(x = 0, y = 0, z = 0) {
    super(x, y, z);
  }

  clone(): Vec3 {
    return new Vec3(this.x, this.y, this.z);
  }

  static subtract(a: CANNON.Vec3, b: CANNON.Vec3): Vec3 {
    const out = new Vec3();
    a.vsub(b, out);
    return out;
  }
}

export class Body extends CANNON.Body {
  constructor(position: Vec3, mass: number, halfExtents?: Vec3) {
    const shape =
      halfExtents != null
        ? new CANNON.Box(
            new CANNON.Vec3(halfExtents.x, halfExtents.y, halfExtents.z)
          )
        : undefined;
    super({
      mass,
      position,
      shape
    });
  }
}

export interface Constraint {
  attach(world: World): void;
}

export class DistanceConstraint implements Constraint {
  private readonly cannon: CANNON.DistanceConstraint;

  constructor(bodyA: Body, bodyB: Body, restLength: number, stiffness = 1.0) {
    // Cannon's DistanceConstraint uses a "max force" parameter; use a scaled value.
    this.cannon = new CANNON.DistanceConstraint(
      bodyA,
      bodyB,
      restLength,
      stiffness * 1e3
    );
  }

  attach(world: World): void {
    world.world.addConstraint(this.cannon);
  }
}

export class GroundConstraint implements Constraint {
  private static groundBody: CANNON.Body | null = null;
  private readonly floorY: number;
  private readonly restitution: number;

  constructor(floorY = 0, restitution = 0) {
    this.floorY = floorY;
    this.restitution = restitution;
  }

  attach(world: World): void {
    if (!GroundConstraint.groundBody) {
      const plane = new CANNON.Body({
        mass: 0,
        shape: new CANNON.Plane()
      });
      // Rotate plane so its normal points up and position it at floorY.
      plane.quaternion.setFromAxisAngle(
        new CANNON.Vec3(1, 0, 0),
        -Math.PI / 2
      );
      plane.position.set(0, this.floorY, 0);
      if (this.restitution > 0) {
        const floorMaterial = new CANNON.Material("floor");
        plane.material = floorMaterial;
        const ballMaterial = new CANNON.Material("ball");
        const contact = new CANNON.ContactMaterial(ballMaterial, floorMaterial, {
          restitution: this.restitution
        });
        world.world.addContactMaterial(contact);
      }
      world.world.addBody(plane);
      GroundConstraint.groundBody = plane;
    }
  }
}

export class World {
  readonly world: CANNON.World;
  private gravityVec: Vec3;
  linearDamping = 0.02;

  constructor() {
    this.world = new CANNON.World();
    this.world.broadphase = new CANNON.NaiveBroadphase();
    this.world.gravity.set(0, -9.82, 0);
    this.world.solver.iterations = 10;
    this.gravityVec = new Vec3(0, -9.82, 0);
  }

  get gravity(): Vec3 {
    return this.gravityVec.clone();
  }

  set gravity(v: Vec3) {
    this.gravityVec = v.clone();
    this.world.gravity.copy(v);
  }

  addBody(body: Body): void {
    body.linearDamping = this.linearDamping;
    this.world.addBody(body);
  }

  addConstraint(constraint: Constraint): void {
    constraint.attach(this);
  }

  step(dt: number): void {
    if (dt <= 0) return;
    const fixedTimeStep = 1 / 60;
    this.world.step(fixedTimeStep, dt, 3);
  }
}
