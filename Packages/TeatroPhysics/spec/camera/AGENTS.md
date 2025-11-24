This directory owns the Teatro Stage Engine camera and view contract. Any implementation that wants to present the canonical Fadenpuppe room must follow this model: a true orthographic camera at a fixed elevation, orbiting around the scene, with predictable zoom behaviour.

Files in this folder describe:
- the numeric camera model (frustum size, distance, azimuth/elevation, look‑at target),
- how aspect ratio affects the orthographic bounds,
- how user input (pointer drag, wheel, pinch) maps to camera azimuth and zoom.

When the Three.js or Metal demos change their camera behaviour, update the spec here first, then align the code.

