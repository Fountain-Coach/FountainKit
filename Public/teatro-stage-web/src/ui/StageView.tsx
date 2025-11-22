import React, { useEffect, useRef } from "react";
import * as THREE from "three";
import type { PuppetSnapshot } from "../engine/puppetRig";

interface StageViewProps {
  snapshot: PuppetSnapshot;
}

export const StageView: React.FC<StageViewProps> = ({ snapshot }) => {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const snapshotRef = useRef<PuppetSnapshot>(snapshot);

  if (snapshotRef.current !== snapshot) {
    snapshotRef.current = snapshot;
  }

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const width = container.clientWidth || 800;
    const height = container.clientHeight || 600;

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    renderer.setSize(width, height);
    renderer.setClearColor(0xf4ead6, 1);
    container.appendChild(renderer.domElement);

    const scene = new THREE.Scene();

    const frustumSize = 40;
    const aspect = width / height;
    const camera = new THREE.OrthographicCamera(
      (frustumSize * aspect) / -2,
      (frustumSize * aspect) / 2,
      frustumSize / 2,
      -frustumSize / 2,
      0.1,
      1000
    );

    const distance = 60;
    let cameraAzimuth = Math.PI / 4;
    const cameraElevation = Math.atan(1 / Math.sqrt(2));

    const updateCameraPosition = () => {
      camera.position.set(
        distance * Math.cos(cameraAzimuth),
        distance * Math.sin(cameraElevation),
        distance * Math.sin(cameraAzimuth)
      );
      camera.lookAt(new THREE.Vector3(0, 5, 0));
      camera.updateProjectionMatrix();
    };
    updateCameraPosition();
    camera.zoom = 1;
    camera.updateProjectionMatrix();

    // Orbit and zoom interaction
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
      cameraAzimuth += dx * 0.003;
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
      const nextZoom = Math.max(0.5, Math.min(3.0, camera.zoom * factor));
      camera.zoom = nextZoom;
      camera.updateProjectionMatrix();
    };

    renderer.domElement.addEventListener("pointerdown", handlePointerDown);
    renderer.domElement.addEventListener("pointermove", handlePointerMove);
    renderer.domElement.addEventListener("pointerup", handlePointerUp);
    renderer.domElement.addEventListener("pointerleave", handlePointerUp);
    renderer.domElement.addEventListener("wheel", handleWheel, {
      passive: false
    });

    // Room
    const roomGroup = new THREE.Group();
    scene.add(roomGroup);
    const lineMat = new THREE.LineBasicMaterial({ color: 0x111111, linewidth: 1 });

    const addBoxEdges = (
      widthBox: number,
      heightBox: number,
      depthBox: number,
      position: THREE.Vector3
    ) => {
      const geo = new THREE.BoxGeometry(widthBox, heightBox, depthBox);
      const edges = new THREE.EdgesGeometry(geo);
      const line = new THREE.LineSegments(edges, lineMat);
      line.position.copy(position);
      roomGroup.add(line);
    };

    addBoxEdges(30, 0.01, 20, new THREE.Vector3(0, 0, 0));
    addBoxEdges(30, 20, 0.01, new THREE.Vector3(0, 10, -10));
    addBoxEdges(0.01, 20, 20, new THREE.Vector3(-15, 10, 0));
    addBoxEdges(0.01, 20, 20, new THREE.Vector3(15, 10, 0));

    // Puppet boxes
    const blackMat = new THREE.MeshBasicMaterial({ color: 0x111111 });
    const puppetMeshes: { [key: string]: THREE.Mesh } = {};

    const makeBoxMesh = (
      w: number,
      h: number,
      d: number,
      name: string
    ): THREE.Mesh => {
      const geo = new THREE.BoxGeometry(w, h, d);
      const mesh = new THREE.Mesh(geo, blackMat);
      scene.add(mesh);
      puppetMeshes[name] = mesh;
      return mesh;
    };

    makeBoxMesh(10, 0.2, 0.2, "bar");
    makeBoxMesh(1.6, 3, 0.8, "torso");
    makeBoxMesh(1.1, 1.1, 0.8, "head");
    makeBoxMesh(0.4, 2.0, 0.4, "handL");
    makeBoxMesh(0.4, 2.0, 0.4, "handR");
    makeBoxMesh(0.5, 2.2, 0.5, "footL");
    makeBoxMesh(0.5, 2.2, 0.5, "footR");

    // Simple floor spot (flat circle)
    const spotGeo = new THREE.CircleGeometry(4, 32);
    const spotMat = new THREE.MeshBasicMaterial({
      color: 0xf9f0e0,
      transparent: true,
      opacity: 0.7
    });
    const spot = new THREE.Mesh(spotGeo, spotMat);
    spot.rotation.x = -Math.PI / 2;
    spot.position.set(0, 0.01, 0);
    scene.add(spot);

    let lastTime = performance.now() / 1000;
    let frameId: number;

    const animate = () => {
      frameId = requestAnimationFrame(animate);
      const now = performance.now() / 1000;
      const dt = Math.min(now - lastTime, 1 / 30);
      lastTime = now;

      const snap = snapshotRef.current;

      puppetMeshes["bar"].position.set(snap.bar.x, snap.bar.y, snap.bar.z);
      puppetMeshes["torso"].position.set(
        snap.torso.x,
        snap.torso.y,
        snap.torso.z
      );
      puppetMeshes["head"].position.set(snap.head.x, snap.head.y, snap.head.z);
      puppetMeshes["handL"].position.set(
        snap.handL.x,
        snap.handL.y,
        snap.handL.z
      );
      puppetMeshes["handR"].position.set(
        snap.handR.x,
        snap.handR.y,
        snap.handR.z
      );
      puppetMeshes["footL"].position.set(
        snap.footL.x,
        snap.footL.y,
        snap.footL.z
      );
      puppetMeshes["footR"].position.set(
        snap.footR.x,
        snap.footR.y,
        snap.footR.z
      );

      renderer.render(scene, camera);
    };

    animate();

    const onResize = () => {
      if (!container) return;
      const w = container.clientWidth || width;
      const h = container.clientHeight || height;
      renderer.setSize(w, h);
      const aspectNew = w / h;
      camera.left = (frustumSize * aspectNew) / -2;
      camera.right = (frustumSize * aspectNew) / 2;
      camera.top = frustumSize / 2;
      camera.bottom = -frustumSize / 2;
      updateCameraPosition();
    };

    window.addEventListener("resize", onResize);

    return () => {
      cancelAnimationFrame(frameId);
      window.removeEventListener("resize", onResize);
      renderer.domElement.removeEventListener(
        "pointerdown",
        handlePointerDown
      );
      renderer.domElement.removeEventListener(
        "pointermove",
        handlePointerMove
      );
      renderer.domElement.removeEventListener("pointerup", handlePointerUp);
      renderer.domElement.removeEventListener(
        "pointerleave",
        handlePointerUp
      );
      renderer.domElement.removeEventListener("wheel", handleWheel);
      renderer.dispose();
      container.removeChild(renderer.domElement);
    };
  }, []);

  return <div ref={containerRef} style={{ width: "100%", height: "100%" }} />;
};
