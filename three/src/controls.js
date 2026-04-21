import * as THREE from "three";

/**
 * First-person look controller supporting:
 *  - mouse motion (desktop)
 *  - touch drag (mobile)
 *  - device gyroscope (mobile, when enabled)
 *  - edge-of-screen rotation (desktop explore mode)
 * Mirrors godot/addons/Basic FPS Player/Src/basic_player_startup.gd.
 */
export class LookController {
  constructor(camera, canvas) {
    this.camera = camera;
    this.canvas = canvas;
    this.yaw = 0;
    this.pitch = 0;
    this.targetYaw = 0;
    this.targetPitch = 0;
    this.smoothing = 50;
    this.sensitivity = 0.001 * 0.12; // KEY_BIND_MOUSE_SENS * default sensitivity_scale
    this.exploreSensitivity = 0.001 * 1.0;
    this.pitchMin = -Math.PI / 2;
    this.pitchMax = Math.PI / 2;

    this.enabled = false;
    this.mouseMode = false;    // desktop hover-look, no click needed
    this.edgeMode = false;     // desktop explore: edge rotation
    this.touchMode = false;    // mobile touch drag
    this.gyroMode = false;     // mobile gyro
    this.edgeDirection = new THREE.Vector2(0, 0);
    this.edgeIntensity = 0;

    this._activeTouchId = null;
    this._lastTouch = null;
    this._dragging = false;
    this._lastPointer = null;
    this.edgeZone = 0.40;
    this.edgeSpeed = 1.0;
    this._mousePos = { x: 0.5, y: 0.5 };

    this._bindEvents();
  }

  setMode({ mouse = false, edge = false, touch = false, gyro = false }) {
    this.mouseMode = mouse;
    this.edgeMode = edge;
    this.touchMode = touch;
    this.gyroMode = gyro;
    this.enabled = mouse || edge || touch || gyro;
  }

  _bindEvents() {
    // Mouse: always-on look when enabled.
    window.addEventListener("mousemove", (e) => {
      if (!this.enabled) return;
      const rect = this.canvas.getBoundingClientRect();
      this._mousePos.x = (e.clientX - rect.left) / rect.width;
      this._mousePos.y = (e.clientY - rect.top) / rect.height;
      if (this.mouseMode && !this.edgeMode && !this.touchMode) {
        // Hover-look: tie yaw/pitch directly to cursor position relative to center.
        this._applyMotion(e.movementX || 0, e.movementY || 0);
      }
    });

    // Touch drag.
    this.canvas.addEventListener("touchstart", (e) => {
      if (!this.enabled || !this.touchMode) return;
      if (e.touches.length > 0 && this._activeTouchId === null) {
        const t = e.touches[0];
        this._activeTouchId = t.identifier;
        this._lastTouch = { x: t.clientX, y: t.clientY };
      }
    }, { passive: true });

    this.canvas.addEventListener("touchmove", (e) => {
      if (!this.enabled || !this.touchMode) return;
      for (const t of e.touches) {
        if (t.identifier === this._activeTouchId) {
          const dx = t.clientX - this._lastTouch.x;
          const dy = t.clientY - this._lastTouch.y;
          this._lastTouch = { x: t.clientX, y: t.clientY };
          // Godot did `-event.relative / 5.0` then applied same sensitivity.
          this._applyMotion(-dx / 5, -dy / 5);
          break;
        }
      }
    }, { passive: true });

    const endTouch = (e) => {
      let active = false;
      for (const t of e.touches) if (t.identifier === this._activeTouchId) active = true;
      if (!active) {
        this._activeTouchId = null;
        this._lastTouch = null;
      }
    };
    this.canvas.addEventListener("touchend", endTouch);
    this.canvas.addEventListener("touchcancel", endTouch);
  }

  _applyMotion(dx, dy) {
    const s = this.edgeMode ? this.exploreSensitivity : this.sensitivity;
    this.targetYaw += -dx * s;
    this.targetPitch += -dy * s;
    this.targetPitch = Math.max(this.pitchMin, Math.min(this.pitchMax, this.targetPitch));
  }

  _applyEdgeRotation(dt) {
    if (!this.edgeMode) {
      this.edgeDirection.set(0, 0);
      this.edgeIntensity = 0;
      return;
    }
    const nx = this._mousePos.x;
    const ny = this._mousePos.y;
    let ex = 0, ey = 0;
    const z = this.edgeZone;
    if (nx < z) ex = -smoothstep(z, 0, nx);
    else if (nx > 1 - z) ex = smoothstep(1 - z, 1, nx);
    if (ny < z) ey = -smoothstep(z, 0, ny);
    else if (ny > 1 - z) ey = smoothstep(1 - z, 1, ny);
    this.edgeDirection.set(ex, ey);
    this.edgeIntensity = Math.min(1, Math.hypot(ex, ey));
    this.targetYaw += -ex * this.edgeSpeed * dt;
    this.targetPitch += -ey * this.edgeSpeed * dt;
    this.targetPitch = Math.max(this.pitchMin, Math.min(this.pitchMax, this.targetPitch));
  }

  _applyGyro(dt, gyro) {
    if (!this.gyroMode || !gyro) return;
    // gyro: {alpha (z), beta (x), gamma (y)} rotation rates — not all browsers
    // expose `rotationRate` deltas. We use orientation deltas instead.
    // Implemented in setupGyro().
  }

  update(dt) {
    this._applyEdgeRotation(dt);
    // Smooth to targets.
    const k = Math.min(1, dt * this.smoothing);
    this.yaw += (this.targetYaw - this.yaw) * k;
    this.pitch += (this.targetPitch - this.pitch) * k;
    this.camera.rotation.set(0, 0, 0, "YXZ");
    this.camera.rotation.order = "YXZ";
    this.camera.rotation.y = this.yaw;
    this.camera.rotation.x = this.pitch;
  }
}

function smoothstep(edge0, edge1, x) {
  if (edge0 === edge1) return 0;
  let t = (x - edge0) / (edge1 - edge0);
  t = Math.max(0, Math.min(1, t));
  return t * t * (3 - 2 * t);
}

/** Set up gyroscope rotation deltas using deviceorientation. */
export function setupGyro(look) {
  let lastAlpha = null, lastBeta = null, lastGamma = null;
  const handler = (e) => {
    if (!look.gyroMode) return;
    if (e.alpha == null || e.beta == null || e.gamma == null) return;
    if (lastAlpha === null) {
      lastAlpha = e.alpha; lastBeta = e.beta; lastGamma = e.gamma;
      return;
    }
    let dAlpha = e.alpha - lastAlpha;
    let dBeta = e.beta - lastBeta;
    // Handle alpha wrap.
    if (dAlpha > 180) dAlpha -= 360;
    else if (dAlpha < -180) dAlpha += 360;
    lastAlpha = e.alpha; lastBeta = e.beta; lastGamma = e.gamma;

    const toRad = Math.PI / 180;
    look.targetYaw += dAlpha * toRad;
    look.targetPitch += dBeta * toRad * -1;
    look.targetPitch = Math.max(look.pitchMin, Math.min(look.pitchMax, look.targetPitch));
  };
  const start = async () => {
    if (typeof DeviceOrientationEvent !== "undefined" &&
        typeof DeviceOrientationEvent.requestPermission === "function") {
      try {
        const r = await DeviceOrientationEvent.requestPermission();
        if (r !== "granted") return false;
      } catch {
        return false;
      }
    }
    window.addEventListener("deviceorientation", handler, true);
    return true;
  };
  return { start };
}
