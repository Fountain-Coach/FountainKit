export class Vec3 {
  x: number;
  y: number;
  z: number;

  constructor(x = 0, y = 0, z = 0) {
    this.x = x;
    this.y = y;
    this.z = z;
  }

  clone(): Vec3 {
    return new Vec3(this.x, this.y, this.z);
  }

  add(v: Vec3): Vec3 {
    this.x += v.x;
    this.y += v.y;
    this.z += v.z;
    return this;
  }

  sub(v: Vec3): Vec3 {
    this.x -= v.x;
    this.y -= v.y;
    this.z -= v.z;
    return this;
  }

  scale(s: number): Vec3 {
    this.x *= s;
    this.y *= s;
    this.z *= s;
    return this;
  }

  length(): number {
    return Math.sqrt(this.x * this.x + this.y * this.y + this.z * this.z);
  }

  normalize(): Vec3 {
    const len = this.length();
    if (len > 0) {
      const inv = 1 / len;
      this.x *= inv;
      this.y *= inv;
      this.z *= inv;
    }
    return this;
  }

  static subtract(a: Vec3, b: Vec3): Vec3 {
    return new Vec3(a.x - b.x, a.y - b.y, a.z - b.z);
  }

  static add(a: Vec3, b: Vec3): Vec3 {
    return new Vec3(a.x + b.x, a.y + b.y, a.z + b.z);
  }

  static scale(v: Vec3, s: number): Vec3 {
    return new Vec3(v.x * s, v.y * s, v.z * s);
  }
}

export class Body {
  position: Vec3;
  velocity: Vec3;
  mass: number;
  invMass: number;

  constructor(position: Vec3, mass: number) {
    this.position = position;
    this.velocity = new Vec3();
    this.mass = mass;
    this.invMass = mass > 0 ? 1 / mass : 0;
  }
}

export interface Constraint {
  solve(dt: number): void;
}

export class DistanceConstraint implements Constraint {
  readonly bodyA: Body;
  readonly bodyB: Body;
  readonly restLength: number;
  readonly stiffness: number;

  constructor(bodyA: Body, bodyB: Body, restLength: number, stiffness = 1.0) {
    this.bodyA = bodyA;
    this.bodyB = bodyB;
    this.restLength = restLength;
    this.stiffness = stiffness;
  }

  solve(_dt: number): void {
    const delta = Vec3.subtract(this.bodyB.position, this.bodyA.position);
    const dist = delta.length();
    if (dist < 1e-6) return;
    const diff = (dist - this.restLength) / dist;
    const impulse = delta.scale(0.5 * this.stiffness * diff);
    if (this.bodyA.invMass > 0) {
      this.bodyA.position.add(impulse);
    }
    if (this.bodyB.invMass > 0) {
      this.bodyB.position.sub(impulse);
    }
  }
}

export class World {
  bodies: Body[] = [];
  constraints: Constraint[] = [];
  gravity = new Vec3(0, -9.82, 0);
  linearDamping = 0.02;

  addBody(body: Body): void {
    this.bodies.push(body);
  }

  addConstraint(constraint: Constraint): void {
    this.constraints.push(constraint);
  }

  step(dt: number): void {
    if (dt <= 0) return;

    for (const body of this.bodies) {
      if (body.invMass === 0) continue;
      const acc = Vec3.scale(this.gravity, body.invMass);
      body.velocity.add(Vec3.scale(acc, dt));
      const damping = Math.max(0, 1 - this.linearDamping);
      body.velocity.scale(damping);
      body.position.add(Vec3.scale(body.velocity, dt));
    }

    for (const c of this.constraints) {
      c.solve(dt);
    }
  }
}

