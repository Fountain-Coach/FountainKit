#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef struct BulletWorld BulletWorld;
typedef struct BulletRigidBody BulletRigidBody;
typedef struct BulletConstraint BulletConstraint;

BulletWorld *BulletCreateWorld(double gravityX, double gravityY, double gravityZ);
void BulletDestroyWorld(BulletWorld *world);

BulletRigidBody *BulletCreateStaticPlane(BulletWorld *world,
                                         double normalX,
                                         double normalY,
                                         double normalZ,
                                         double constant);

BulletRigidBody *BulletCreateSphere(BulletWorld *world,
                                    double radius,
                                    double mass,
                                    double posX,
                                    double posY,
                                    double posZ);

BulletRigidBody *BulletCreateBox(BulletWorld *world,
                                 double halfX,
                                 double halfY,
                                 double halfZ,
                                 double mass,
                                 double posX,
                                 double posY,
                                 double posZ);

void BulletStepWorld(BulletWorld *world,
                     double timeStep,
                     int maxSubSteps,
                     double fixedTimeStep);

BulletConstraint *BulletAddPointConstraint(BulletWorld *world,
                                           BulletRigidBody *bodyA,
                                           BulletRigidBody *bodyB,
                                           double anchorAX, double anchorAY, double anchorAZ,
                                           double anchorBX, double anchorBY, double anchorBZ);

void BulletGetBodyPosition(const BulletRigidBody *body, double *outX, double *outY, double *outZ);
void BulletGetBodyLinearVelocity(const BulletRigidBody *body, double *outX, double *outY, double *outZ);
int BulletBodyIsActive(const BulletRigidBody *body);

#ifdef __cplusplus
}
#endif
