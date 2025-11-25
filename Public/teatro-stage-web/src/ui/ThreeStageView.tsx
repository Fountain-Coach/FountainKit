import React, { useEffect, useRef } from "react";
import * as THREE from "three";
import { type StageSnapshot } from "../engine/stage";

interface ThreeStageViewProps {
  snapshot: StageSnapshot;
}

// Stage geometry (matches demo1.html).
const ROOM_HALF_WIDTH = 15;
const ROOM_HALF_DEPTH = 10;
const ROOM_HEIGHT = 20;
const DOOR_MIN_Y = 0;
const DOOR_MAX_Y = 8;
const DOOR_MIN_Z = -4;
const DOOR_MAX_Z = -1;

// Puppet geometry (matches demo1.html).
const RIG = {
  bar: { size: { x: 10, y: 0.2, z: 0.2 } },
  torso: { size: { x: 1.6, y: 3.0, z: 0.8 } },
  head: { size: { x: 1.1, y: 1.1, z: 0.8 } },
  hand: { size: { x: 0.4, y: 2.0, z: 0.4 } },
  foot: { size: { x: 0.5, y: 2.2, z: 0.5 } }
} as const;

// Camera setup aligned with the canonical orthographic view.
const FRUSTUM_SIZE = 40;
const CAMERA_ELEVATION = Math.atan(1 / Math.sqrt(2)); // ~35°
const CAMERA_DISTANCE = 60;
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
    const azimuthRef = { value: Math.PI / 4 };
    const zoomRef = { value: 1 };
    const updateCameraPosition = () => {
      camera.position.set(
        CAMERA_DISTANCE * Math.cos(azimuthRef.value),
        CAMERA_DISTANCE * Math.sin(CAMERA_ELEVATION),
        CAMERA_DISTANCE * Math.sin(azimuthRef.value)
      );
      camera.lookAt(LOOK_AT);
      camera.zoom = zoomRef.value;
      camera.updateProjectionMatrix();
    };
    updateCameraPosition();

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

    // Puppet meshes with outlines to match the demo look.
    const black = 0x111111;
    const outlineColor = 0xf4ead6;
    const mat = new THREE.MeshBasicMaterial({ color: black });
    const addOutline = (geo: THREE.BufferGeometry, mesh: THREE.Mesh) => {
      const edges = new THREE.EdgesGeometry(geo);
      const outline = new THREE.LineSegments(
        edges,
        new THREE.LineBasicMaterial({ color: outlineColor, linewidth: 2 })
      );
      mesh.add(outline);
    };

    const box = (w: number, h: number, d: number) => new THREE.BoxGeometry(w, h, d);

    const bar = new THREE.Mesh(box(RIG.bar.size.x, RIG.bar.size.y, RIG.bar.size.z), mat);
    addOutline(bar.geometry as THREE.BufferGeometry, bar);

    const torso = new THREE.Mesh(box(RIG.torso.size.x, RIG.torso.size.y, RIG.torso.size.z), mat);
    addOutline(torso.geometry as THREE.BufferGeometry, torso);

    const headGeom = box(RIG.head.size.x, RIG.head.size.y, RIG.head.size.z);
    const head = new THREE.Mesh(headGeom, mat);
    addOutline(headGeom, head);

    const handGeom = box(RIG.hand.size.x, RIG.hand.size.y, RIG.hand.size.z);
    const handL = new THREE.Mesh(handGeom, mat);
    addOutline(handGeom, handL);
    const handR = handL.clone();

    const footGeom = box(RIG.foot.size.x, RIG.foot.size.y, RIG.foot.size.z);
    const footL = new THREE.Mesh(footGeom, mat);
    addOutline(footGeom, footL);
    const footR = footL.clone();

    const stringGeom = new THREE.BufferGeometry();
    stringGeom.setAttribute("position", new THREE.Float32BufferAttribute(3 * 2 * 3, 3)); // 3 strings
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
      updateCameraPosition();
      rendererRef.current.setSize(clientWidth, clientHeight);
    };

    // Orbit + zoom controls
    let dragging = false;
    let lastX = 0;
    const handlePointerDown = (e: PointerEvent) => {
      dragging = true;
      lastX = e.clientX;
      renderer.domElement.setPointerCapture(e.pointerId);
    };
    const handlePointerMove = (e: PointerEvent) => {
      if (!dragging) return;
      const dx = e.clientX - lastX;
      lastX = e.clientX;
      azimuthRef.value += dx * 0.003;
      updateCameraPosition();
    };
    const handlePointerUp = (e: PointerEvent) => {
      dragging = false;
      try {
        renderer.domElement.releasePointerCapture(e.pointerId);
      } catch {
        // ignore
      }
    };
    const handleWheel = (e: WheelEvent) => {
      e.preventDefault();
      const factor = e.deltaY > 0 ? 0.9 : 1.1;
      zoomRef.value = Math.max(0.5, Math.min(3, zoomRef.value * factor));
      updateCameraPosition();
    };

    renderer.domElement.addEventListener("pointerdown", handlePointerDown, { passive: false });
    renderer.domElement.addEventListener("pointermove", handlePointerMove, { passive: false });
    renderer.domElement.addEventListener("pointerup", handlePointerUp, { passive: false });
    renderer.domElement.addEventListener("wheel", handleWheel, { passive: false });

    window.addEventListener("resize", handleResize);
    handleResize();

    return () => {
      window.removeEventListener("resize", handleResize);
      renderer.domElement.removeEventListener("pointerdown", handlePointerDown);
      renderer.domElement.removeEventListener("pointermove", handlePointerMove);
      renderer.domElement.removeEventListener("pointerup", handlePointerUp);
      renderer.domElement.removeEventListener("wheel", handleWheel);
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

    const setPose = (
      mesh: THREE.Mesh,
      pose: { position: { x: number; y: number; z: number }; quaternion: { x: number; y: number; z: number; w: number } }
    ) => {
      mesh.position.set(pose.position.x, pose.position.y, pose.position.z);
      mesh.quaternion.set(pose.quaternion.x, pose.quaternion.y, pose.quaternion.z, pose.quaternion.w);
    };

    setPose(meshes.torso, puppet.torso);
    setPose(meshes.head, puppet.head);
    setPose(meshes.bar, puppet.bar);
    setPose(meshes.handL, puppet.handL);
    setPose(meshes.handR, puppet.handR);
    setPose(meshes.footL, puppet.footL);
    setPose(meshes.footR, puppet.footR);

    const strings = puppet.strings ?? [];
    const positions = meshes.strings.geometry.getAttribute("position") as THREE.BufferAttribute;
    if (positions.count !== strings.length * 2) {
      meshes.strings.geometry.setAttribute("position", new THREE.Float32BufferAttribute(strings.length * 2 * 3, 3));
    }
    strings.forEach((s, idx) => {
      positions.setXYZ(idx * 2 + 0, s.a.x, s.a.y, s.a.z);
      positions.setXYZ(idx * 2 + 1, s.b.x, s.b.y, s.b.z);
    });
    positions.needsUpdate = true;

    renderer.render(scene, camera);
  }, [snapshot]);

  return <div ref={mountRef} style={{ width: "100%", height: "100%" }} />;
};
