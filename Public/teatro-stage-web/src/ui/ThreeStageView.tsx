import React, { useEffect, useRef } from "react";
import * as THREE from "three";
import { type StageSnapshot } from "../engine/stage";

interface ThreeStageViewProps {
  snapshot: StageSnapshot;
}

// Dimensions pulled from TeatroStageEngine specs / legacy threejs demo.
const ROOM_HALF_WIDTH = 15;
const ROOM_HALF_DEPTH = 10;
const ROOM_HEIGHT = 20;
const DOOR_MIN_Y = 0;
const DOOR_MAX_Y = 8;
const DOOR_MIN_Z = -4;
const DOOR_MAX_Z = -1;

// Camera setup aligned with the canonical orthographic view.
const FRUSTUM_SIZE = 40;
const CAMERA_ELEVATION = Math.atan(1 / Math.sqrt(2)); // ~35°
const CAMERA_DISTANCE = 50;
const LOOK_AT = new THREE.Vector3(0, 5, 0);

export const ThreeStageView: React.FC<ThreeStageViewProps> = ({ snapshot }) => {
  const mountRef = useRef<HTMLDivElement | null>(null);
  const rendererRef = useRef<THREE.WebGLRenderer>();
  const sceneRef = useRef<THREE.Scene>();
  const cameraRef = useRef<THREE.OrthographicCamera>();
  const puppetMeshesRef = useRef<{
    torso: THREE.Mesh;
    head: THREE.Mesh;
    bar: THREE.Mesh;
    handL: THREE.Mesh;
    handR: THREE.Mesh;
    footL: THREE.Mesh;
    footR: THREE.Mesh;
    strings: THREE.LineSegments;
  }>();

  useEffect(() => {
    const mount = mountRef.current;
    if (!mount) return;

    const scene = new THREE.Scene();
    scene.background = new THREE.Color("#f4ead6");

    const aspect = mount.clientWidth / mount.clientHeight;
    const camera = new THREE.OrthographicCamera(
      (-FRUSTUM_SIZE * aspect) / 2,
      (FRUSTUM_SIZE * aspect) / 2,
      FRUSTUM_SIZE / 2,
      -FRUSTUM_SIZE / 2,
      0.1,
      200
    );
    const azimuth = Math.PI / 4;
    camera.position.set(
      CAMERA_DISTANCE * Math.cos(azimuth),
      CAMERA_DISTANCE * Math.sin(CAMERA_ELEVATION),
      CAMERA_DISTANCE * Math.sin(azimuth)
    );
    camera.lookAt(LOOK_AT);

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setPixelRatio(window.devicePixelRatio || 1);
    renderer.setSize(mount.clientWidth, mount.clientHeight);
    mount.appendChild(renderer.domElement);

    // Stage wireframe (floor, walls, door)
    const lineMat = new THREE.LineBasicMaterial({ color: 0x111111, linewidth: 1 });
    const stageGeometry = new THREE.BufferGeometry();
    const stageVerts: number[] = [];

    const pushLine = (a: THREE.Vector3, b: THREE.Vector3) => {
      stageVerts.push(a.x, a.y, a.z, b.x, b.y, b.z);
    };

    const corners = {
      fl: new THREE.Vector3(-ROOM_HALF_WIDTH, 0, ROOM_HALF_DEPTH),
      fr: new THREE.Vector3(ROOM_HALF_WIDTH, 0, ROOM_HALF_DEPTH),
      br: new THREE.Vector3(ROOM_HALF_WIDTH, 0, -ROOM_HALF_DEPTH),
      bl: new THREE.Vector3(-ROOM_HALF_WIDTH, 0, -ROOM_HALF_DEPTH),
      flTop: new THREE.Vector3(-ROOM_HALF_WIDTH, ROOM_HEIGHT, ROOM_HALF_DEPTH),
      frTop: new THREE.Vector3(ROOM_HALF_WIDTH, ROOM_HEIGHT, ROOM_HALF_DEPTH),
      brTop: new THREE.Vector3(ROOM_HALF_WIDTH, ROOM_HEIGHT, -ROOM_HALF_DEPTH),
      blTop: new THREE.Vector3(-ROOM_HALF_WIDTH, ROOM_HEIGHT, -ROOM_HALF_DEPTH)
    };

    // Floor
    pushLine(corners.fl, corners.fr);
    pushLine(corners.fr, corners.br);
    pushLine(corners.br, corners.bl);
    pushLine(corners.bl, corners.fl);
    // Vertical edges
    pushLine(corners.fl, corners.flTop);
    pushLine(corners.fr, corners.frTop);
    pushLine(corners.br, corners.brTop);
    pushLine(corners.bl, corners.blTop);
    // Ceiling perimeter
    pushLine(corners.flTop, corners.frTop);
    pushLine(corners.frTop, corners.brTop);
    pushLine(corners.brTop, corners.blTop);
    pushLine(corners.blTop, corners.flTop);
    // Door (right wall)
    pushLine(
      new THREE.Vector3(ROOM_HALF_WIDTH, DOOR_MIN_Y, DOOR_MIN_Z),
      new THREE.Vector3(ROOM_HALF_WIDTH, DOOR_MAX_Y, DOOR_MIN_Z)
    );
    pushLine(
      new THREE.Vector3(ROOM_HALF_WIDTH, DOOR_MAX_Y, DOOR_MIN_Z),
      new THREE.Vector3(ROOM_HALF_WIDTH, DOOR_MAX_Y, DOOR_MAX_Z)
    );
    pushLine(
      new THREE.Vector3(ROOM_HALF_WIDTH, DOOR_MAX_Y, DOOR_MAX_Z),
      new THREE.Vector3(ROOM_HALF_WIDTH, DOOR_MIN_Y, DOOR_MAX_Z)
    );

    stageGeometry.setAttribute(
      "position",
      new THREE.Float32BufferAttribute(stageVerts, 3)
    );
    const stageLines = new THREE.LineSegments(stageGeometry, lineMat);
    scene.add(stageLines);

    // Puppet meshes (simple boxes/circle)
    const black = 0x111111;
    const mat = new THREE.MeshBasicMaterial({ color: black });
    const box = (hx: number, hy: number, hz: number) =>
      new THREE.BoxGeometry(hx * 2, hy * 2, hz * 2);

    const torso = new THREE.Mesh(box(0.6, 1.2, 0.4), mat);
    const head = new THREE.Mesh(new THREE.SphereGeometry(0.6, 16, 12), mat);
    const bar = new THREE.Mesh(box(1.6, 0.1, 0.2), mat);
    const handL = new THREE.Mesh(box(0.3, 0.3, 0.2), mat);
    const handR = handL.clone();
    const footL = new THREE.Mesh(box(0.4, 0.3, 0.2), mat);
    const footR = footL.clone();

    const stringGeom = new THREE.BufferGeometry();
    stringGeom.setAttribute("position", new THREE.Float32BufferAttribute(16 * 3, 3)); // 8 segments → 16 points
    const strings = new THREE.LineSegments(stringGeom, lineMat);

    scene.add(torso, head, bar, handL, handR, footL, footR, strings);

    puppetMeshesRef.current = {
      torso,
      head,
      bar,
      handL,
      handR,
      footL,
      footR,
      strings
    };

    sceneRef.current = scene;
    cameraRef.current = camera;
    rendererRef.current = renderer;

    const handleResize = () => {
      if (!rendererRef.current || !cameraRef.current || !mountRef.current) return;
      const { clientWidth, clientHeight } = mountRef.current;
      const aspectResize = clientWidth / clientHeight;
      const cam = cameraRef.current;
      cam.left = (-FRUSTUM_SIZE * aspectResize) / 2;
      cam.right = (FRUSTUM_SIZE * aspectResize) / 2;
      cam.top = FRUSTUM_SIZE / 2;
      cam.bottom = -FRUSTUM_SIZE / 2;
      cam.updateProjectionMatrix();
      rendererRef.current.setSize(clientWidth, clientHeight);
    };

    window.addEventListener("resize", handleResize);
    handleResize();

    return () => {
      window.removeEventListener("resize", handleResize);
      renderer.dispose();
    };
  }, []);

  useEffect(() => {
    const renderer = rendererRef.current;
    const scene = sceneRef.current;
    const camera = cameraRef.current;
    const meshes = puppetMeshesRef.current;
    if (!renderer || !scene || !camera || !meshes) return;

    const { puppet } = snapshot;

    meshes.torso.position.set(puppet.torso.x, puppet.torso.y, puppet.torso.z ?? 0);
    meshes.head.position.set(puppet.head.x, puppet.head.y, puppet.head.z ?? 0);
    meshes.bar.position.set(puppet.bar.x, puppet.bar.y, puppet.bar.z ?? 0);
    meshes.handL.position.set(puppet.handL.x, puppet.handL.y, puppet.handL.z ?? 0);
    meshes.handR.position.set(puppet.handR.x, puppet.handR.y, puppet.handR.z ?? 0);
    meshes.footL.position.set(puppet.footL.x, puppet.footL.y, puppet.footL.z ?? 0);
    meshes.footR.position.set(puppet.footR.x, puppet.footR.y, puppet.footR.z ?? 0);

    // Strings: controller→bar, controller→hands, bar→head, torso→hands/feet/head
    const positions = meshes.strings.geometry.getAttribute(
      "position"
    ) as THREE.BufferAttribute;
    const setSegment = (i: number, a: THREE.Vector3, b: THREE.Vector3) => {
      const offset = i * 6;
      positions.setXYZ(offset / 3 + 0, a.x, a.y, a.z);
      positions.setXYZ(offset / 3 + 1, b.x, b.y, b.z);
    };
    const controller = new THREE.Vector3(
      puppet.controller.x,
      puppet.controller.y,
      puppet.controller.z ?? 0
    );
    setSegment(0, controller, meshes.bar.position);
    setSegment(1, controller, meshes.handL.position);
    setSegment(2, controller, meshes.handR.position);
    setSegment(3, meshes.bar.position, meshes.head.position);
    setSegment(4, meshes.torso.position, meshes.handL.position);
    setSegment(5, meshes.torso.position, meshes.handR.position);
    setSegment(6, meshes.torso.position, meshes.footL.position);
    setSegment(7, meshes.torso.position, meshes.footR.position);
    positions.needsUpdate = true;

    renderer.render(scene, camera);
  }, [snapshot]);

  return <div ref={mountRef} style={{ width: "100%", height: "100%" }} />;
};
