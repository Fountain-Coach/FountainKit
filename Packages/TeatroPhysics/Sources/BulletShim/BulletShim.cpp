#include "BulletShim.h"

#include <memory>
#include <vector>

#include <btBulletDynamicsCommon.h>

struct BulletWorld {
    std::unique_ptr<btDefaultCollisionConfiguration> collisionConfiguration;
    std::unique_ptr<btCollisionDispatcher> dispatcher;
    std::unique_ptr<btDbvtBroadphase> broadphase;
    std::unique_ptr<btSequentialImpulseConstraintSolver> solver;
    std::unique_ptr<btDiscreteDynamicsWorld> world;
    std::vector<std::unique_ptr<btCollisionShape>> shapes;
    std::vector<std::unique_ptr<btRigidBody>> bodies;
    std::vector<std::unique_ptr<btTypedConstraint>> constraints;
};

struct BulletRigidBody {
    btRigidBody *body;
};

struct BulletConstraint {
    btTypedConstraint *constraint;
};

static BulletRigidBody *wrapBody(std::unique_ptr<btRigidBody> body, BulletWorld *world) {
    auto *wrapper = new BulletRigidBody();
    wrapper->body = body.get();
    world->world->addRigidBody(wrapper->body);
    world->bodies.push_back(std::move(body));
    return wrapper;
}

static BulletConstraint *wrapConstraint(std::unique_ptr<btTypedConstraint> c, BulletWorld *world) {
    auto *wrapper = new BulletConstraint();
    wrapper->constraint = c.get();
    world->world->addConstraint(wrapper->constraint);
    world->constraints.push_back(std::move(c));
    return wrapper;
}

BulletWorld *BulletCreateWorld(double gravityX, double gravityY, double gravityZ) {
    auto world = std::make_unique<BulletWorld>();
    world->collisionConfiguration = std::make_unique<btDefaultCollisionConfiguration>();
    world->dispatcher = std::make_unique<btCollisionDispatcher>(world->collisionConfiguration.get());
    world->broadphase = std::make_unique<btDbvtBroadphase>();
    world->solver = std::make_unique<btSequentialImpulseConstraintSolver>();
    world->world = std::make_unique<btDiscreteDynamicsWorld>(
        world->dispatcher.get(),
        world->broadphase.get(),
        world->solver.get(),
        world->collisionConfiguration.get());
    world->world->setGravity(btVector3(gravityX, gravityY, gravityZ));
    return world.release();
}

void BulletDestroyWorld(BulletWorld *world) {
    if (!world) { return; }
    delete world;
}

BulletRigidBody *BulletCreateStaticPlane(BulletWorld *world,
                                         double normalX,
                                         double normalY,
                                         double normalZ,
                                         double constant) {
    if (!world) { return nullptr; }
    auto shape = std::make_unique<btStaticPlaneShape>(btVector3(normalX, normalY, normalZ), constant);
    auto motionState = std::make_unique<btDefaultMotionState>();
    btRigidBody::btRigidBodyConstructionInfo info(0.0, motionState.release(), shape.get());
    auto body = std::make_unique<btRigidBody>(info);
    world->shapes.push_back(std::move(shape));
    return wrapBody(std::move(body), world);
}

BulletRigidBody *BulletCreateSphere(BulletWorld *world,
                                    double radius,
                                    double mass,
                                    double posX,
                                    double posY,
                                    double posZ) {
    if (!world) { return nullptr; }
    auto shape = std::make_unique<btSphereShape>(radius);
    btTransform transform;
    transform.setIdentity();
    transform.setOrigin(btVector3(posX, posY, posZ));
    btVector3 inertia(0, 0, 0);
    if (mass > 0.0) {
        shape->calculateLocalInertia(mass, inertia);
    }
    auto motionState = std::make_unique<btDefaultMotionState>(transform);
    btRigidBody::btRigidBodyConstructionInfo info(mass, motionState.release(), shape.get(), inertia);
    auto body = std::make_unique<btRigidBody>(info);
    world->shapes.push_back(std::move(shape));
    return wrapBody(std::move(body), world);
}

BulletRigidBody *BulletCreateBox(BulletWorld *world,
                                 double halfX,
                                 double halfY,
                                 double halfZ,
                                 double mass,
                                 double posX,
                                 double posY,
                                 double posZ) {
    if (!world) { return nullptr; }
    auto shape = std::make_unique<btBoxShape>(btVector3(halfX, halfY, halfZ));
    btTransform transform;
    transform.setIdentity();
    transform.setOrigin(btVector3(posX, posY, posZ));
    btVector3 inertia(0, 0, 0);
    if (mass > 0.0) {
        shape->calculateLocalInertia(mass, inertia);
    }
    auto motionState = std::make_unique<btDefaultMotionState>(transform);
    btRigidBody::btRigidBodyConstructionInfo info(mass, motionState.release(), shape.get(), inertia);
    auto body = std::make_unique<btRigidBody>(info);
    world->shapes.push_back(std::move(shape));
    return wrapBody(std::move(body), world);
}

BulletConstraint *BulletAddPointConstraint(BulletWorld *world,
                                           BulletRigidBody *bodyA,
                                           BulletRigidBody *bodyB,
                                           double anchorAX, double anchorAY, double anchorAZ,
                                           double anchorBX, double anchorBY, double anchorBZ) {
    if (!world || !bodyA || !bodyB) { return nullptr; }
    auto constraint = std::make_unique<btPoint2PointConstraint>(
        *bodyA->body,
        *bodyB->body,
        btVector3(anchorAX, anchorAY, anchorAZ),
        btVector3(anchorBX, anchorBY, anchorBZ)
    );
    return wrapConstraint(std::move(constraint), world);
}

void BulletStepWorld(BulletWorld *world,
                     double timeStep,
                     int maxSubSteps,
                     double fixedTimeStep) {
    if (!world) { return; }
    world->world->stepSimulation(timeStep, maxSubSteps, fixedTimeStep);
}

void BulletGetBodyPosition(const BulletRigidBody *body, double *outX, double *outY, double *outZ) {
    if (!body || !body->body) { return; }
    const btVector3 pos = body->body->getCenterOfMassPosition();
    if (outX) { *outX = pos.x(); }
    if (outY) { *outY = pos.y(); }
    if (outZ) { *outZ = pos.z(); }
}

void BulletGetBodyLinearVelocity(const BulletRigidBody *body, double *outX, double *outY, double *outZ) {
    if (!body || !body->body) { return; }
    const btVector3 vel = body->body->getLinearVelocity();
    if (outX) { *outX = vel.x(); }
    if (outY) { *outY = vel.y(); }
    if (outZ) { *outZ = vel.z(); }
}

int BulletBodyIsActive(const BulletRigidBody *body) {
    if (!body || !body->body) { return 0; }
    return body->body->isActive() ? 1 : 0;
}

