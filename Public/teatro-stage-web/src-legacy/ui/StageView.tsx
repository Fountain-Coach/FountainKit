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

    // Room — draw the Teatro stage box (floor at y = 0, walls to y = 20)
    const roomGroup = new THREE.Group();
    scene.add(roomGroup);
    const lineMat = new THREE.LineBasicMaterial({
      color: 0x111111,
      linewidth: 1
    });
    const stageOffsetY = 0;

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

    // Floor at stageOffsetY (y = 0), walls rising 20 units above
    addBoxEdges(30, 0.01, 20, new THREE.Vector3(0, stageOffsetY, 0));
    addBoxEdges(30, 20, 0.01, new THREE.Vector3(0, stageOffsetY + 10, -10));
    addBoxEdges(0.01, 20, 20, new THREE.Vector3(-15, stageOffsetY + 10, 0));
    addBoxEdges(0.01, 20, 20, new THREE.Vector3(15, stageOffsetY + 10, 0));

    // Door cut-out on the right wall (z from −4 to −1, y from 0 to 8)
    const doorGeo = new THREE.BufferGeometry().setFromPoints([
      new THREE.Vector3(15, stageOffsetY + 0, -4),
      new THREE.Vector3(15, stageOffsetY + 8, -4),
      new THREE.Vector3(15, stageOffsetY + 8, -1),
      new THREE.Vector3(15, stageOffsetY + 0, -1),
      new THREE.Vector3(15, stageOffsetY + 0, -4)
    ]);
    const door = new THREE.Line(doorGeo, lineMat);
    roomGroup.add(door);

    // Overhead rig (simple truss above the stage)
    const rigGroup = new THREE.Group();
    scene.add(rigGroup);
    const rigMat = new THREE.LineBasicMaterial({
      color: 0x111111,
      linewidth: 1
    });
    const rigGeo = new THREE.BufferGeometry().setFromPoints([
      new THREE.Vector3(-15, 19, -10),
      new THREE.Vector3(15, 19, -10),
      new THREE.Vector3(15, 19, 10),
      new THREE.Vector3(-15, 19, 10),
      new THREE.Vector3(-15, 19, -10)
    ]);
    const rigOutline = new THREE.Line(rigGeo, rigMat);
    rigGroup.add(rigOutline);

    // Controller cross: a movable cross inside the rig, driven by the controller body
    const controllerGroup = new THREE.Group();
    const crossHalfW = 5;
    const crossHalfD = 3;
    const controllerMat = new THREE.LineBasicMaterial({
      color: 0x111111,
      linewidth: 1
    });
    const horizGeo = new THREE.BufferGeometry().setFromPoints([
      new THREE.Vector3(-crossHalfW, 0, 0),
      new THREE.Vector3(crossHalfW, 0, 0)
    ]);
    const vertGeo = new THREE.BufferGeometry().setFromPoints([
      new THREE.Vector3(0, 0, -crossHalfD),
      new THREE.Vector3(0, 0, crossHalfD)
    ]);
    const horizLine = new THREE.Line(horizGeo, controllerMat);
    const vertLine = new THREE.Line(vertGeo, controllerMat);
    controllerGroup.add(horizLine);
    controllerGroup.add(vertLine);
    scene.add(controllerGroup);

    // Strings: from controller cross to bar/head/hands
    const stringMat = new THREE.LineBasicMaterial({
      color: 0x111111,
      linewidth: 1
    });
    const makeString = (): THREE.Line => {
      const geo = new THREE.BufferGeometry();
      const positions = new Float32Array(6); // 2 points
      geo.setAttribute(
        "position",
        new THREE.BufferAttribute(positions, 3)
      );
      const line = new THREE.Line(geo, stringMat);
      scene.add(line);
      return line;
    };
    const stringControllerBar = makeString();
    const stringControllerHandL = makeString();
    const stringControllerHandR = makeString();
    const stringBarHead = makeString();

    // Puppet boxes (including visible bar)
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

    // Visible bar above the head
    makeBoxMesh(10, 0.2, 0.2, "bar");
    // Torso + head + limbs
    makeBoxMesh(1.6, 3, 0.8, "torso");
    makeBoxMesh(1.1, 1.1, 0.8, "head");
    makeBoxMesh(0.4, 2.0, 0.4, "handL");
    makeBoxMesh(0.4, 2.0, 0.4, "handR");
    makeBoxMesh(0.5, 2.2, 0.5, "footL");
    makeBoxMesh(0.5, 2.2, 0.5, "footR");

    // Floor spot: inner disc and softer outer ring
    const spotInnerGeo = new THREE.CircleGeometry(3.2, 48);
    const spotOuterGeo = new THREE.CircleGeometry(4.0, 48);
    const spotInnerMat = new THREE.MeshBasicMaterial({
      color: 0xf9f0e0,
      transparent: true,
      opacity: 0.7
    });
    const spotOuterMat = new THREE.MeshBasicMaterial({
      color: 0xf9f0e0,
      transparent: true,
      opacity: 0.35
    });
    const spotInner = new THREE.Mesh(spotInnerGeo, spotInnerMat);
    spotInner.rotation.x = -Math.PI / 2;
    spotInner.position.set(0, stageOffsetY + 0.01, 0);
    const spotOuter = new THREE.Mesh(spotOuterGeo, spotOuterMat);
    spotOuter.rotation.x = -Math.PI / 2;
    spotOuter.position.set(0, stageOffsetY + 0.011, 0);
    scene.add(spotInner);
    scene.add(spotOuter);

    // Back-wall wash behind the puppet
    const washGeo = new THREE.PlaneGeometry(12, 8);
    const washMat = new THREE.MeshBasicMaterial({
      color: 0xf7efe0,
      transparent: true,
      opacity: 0.5
    });
    const wash = new THREE.Mesh(washGeo, washMat);
    wash.position.set(0, stageOffsetY + 8, -10.01);
    scene.add(wash);

    // Head backlight outline attached to head mesh (created later)
    const headBacklightGeo = new THREE.BoxGeometry(1.2, 1.2, 0.85);
    const headBacklightEdges = new THREE.EdgesGeometry(headBacklightGeo);
    const headBacklightMat = new THREE.LineBasicMaterial({
      color: 0xfaf2e4,
      linewidth: 2
    });
    const headBacklight = new THREE.LineSegments(
      headBacklightEdges,
      headBacklightMat
    );

    let lastTime = performance.now() / 1000;
    let frameId: number;

    const animate = () => {
      frameId = requestAnimationFrame(animate);
      const now = performance.now() / 1000;
      const dt = Math.min(now - lastTime, 1 / 30);
      lastTime = now;

      const snap = snapshotRef.current;
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

      // Visible bar follows the bar body centre
      const barMesh = puppetMeshes["bar"];
      barMesh.position.set(snap.bar.x, snap.bar.y, snap.bar.z);

      // Attach head backlight to the head mesh once
      if (!headBacklight.parent && puppetMeshes["head"]) {
        puppetMeshes["head"].add(headBacklight);
      }

      // Controller cross follows the controller body
      const controllerCenter = new THREE.Vector3(
        snap.controller.x,
        snap.controller.y,
        snap.controller.z
      );
      controllerGroup.position.copy(controllerCenter);

      // Strings: controller centre → bar, controller ends → hands, bar → head
      const updateString = (
        line: THREE.Line,
        from: THREE.Vector3,
        to: THREE.Vector3
      ) => {
        const attr = line.geometry.getAttribute(
          "position"
        ) as THREE.BufferAttribute;
        attr.setXYZ(0, from.x, from.y, from.z);
        attr.setXYZ(1, to.x, to.y, to.z);
        attr.needsUpdate = true;
      };

      const controllerLeft = new THREE.Vector3(
        controllerCenter.x - crossHalfW,
        controllerCenter.y,
        controllerCenter.z
      );
      const controllerRight = new THREE.Vector3(
        controllerCenter.x + crossHalfW,
        controllerCenter.y,
        controllerCenter.z
      );

      // Controller centre → bar
      updateString(
        stringControllerBar,
        controllerCenter,
        new THREE.Vector3(snap.bar.x, snap.bar.y, snap.bar.z)
      );

      // Controller ends → hands
      updateString(
        stringControllerHandL,
        controllerLeft,
        new THREE.Vector3(snap.handL.x, snap.handL.y, snap.handL.z)
      );
      updateString(
        stringControllerHandR,
        controllerRight,
        new THREE.Vector3(snap.handR.x, snap.handR.y, snap.handR.z)
      );

      // Bar → head
      updateString(
        stringBarHead,
        new THREE.Vector3(snap.bar.x, snap.bar.y, snap.bar.z),
        new THREE.Vector3(snap.head.x, snap.head.y, snap.head.z)
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
