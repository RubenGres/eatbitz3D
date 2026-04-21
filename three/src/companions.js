import * as THREE from "three";
import { REMBG_BASE, COMPANIONS, RING_RADII, RING_CAPACITIES, MAX_CONCURRENT_FETCHES, SPAWN_INTERVAL_MS } from "./config.js";

const PLACEHOLDER = new THREE.CanvasTexture(createPlaceholderCanvas());

function createPlaceholderCanvas() {
  const c = document.createElement("canvas");
  c.width = c.height = 8;
  const ctx = c.getContext("2d");
  ctx.fillStyle = "rgba(0,0,0,0)";
  ctx.fillRect(0, 0, 8, 8);
  return c;
}

const textureLoader = new THREE.TextureLoader();

/**
 * A single companion: a sprite (camera-facing quad) that orbits a target
 * with a firefly motion and fades in/out on a lifetime cycle.
 * Mirrors godot/Scenes/3D_scene/PointCloudObject/point_cloud_from_bitz.gd.
 */
export class Companion {
  constructor({ questId, speciesId, target, orbitRadius }) {
    this.questId = questId;
    this.speciesId = speciesId;
    this.target = target;

    const material = new THREE.SpriteMaterial({
      map: PLACEHOLDER,
      transparent: true,
      depthWrite: false,
      opacity: 1,
    });
    this.sprite = new THREE.Sprite(material);
    this.sprite.scale.setScalar(0.01);
    this.sprite.userData.companion = this;
    this.sprite.userData.selectable = true;
    this.sprite.userData.type = "companion";
    this.sprite.visible = true;
    this.sprite.frustumCulled = false;

    // Orbit params (same as Godot defaults).
    this.orbitRadius = orbitRadius + (Math.random() * 0.6 - 0.3);
    this.driftSpeed = 0.8 + (Math.random() * 0.8 - 0.4);
    this.wanderStrength = 0.5;
    this.wanderFrequency = 0.6;
    this.phase = Math.random() * Math.PI * 2;

    const axis = new THREE.Vector3(
      Math.random() * 2 - 1,
      Math.random() * 2 - 1,
      Math.random() * 2 - 1,
    ).normalize();
    this.orbitQuat = new THREE.Quaternion().setFromAxisAngle(axis, Math.random() * Math.PI * 2);

    // Scale falloff.
    this.scaleMin = 0.5;
    this.scaleMax = 8.4;

    // Lifecycle.
    this.lifetime = 25.0 + Math.random() * 5.0;
    this.sleepTime = 10.0;
    this.fadeIn = 0.8;
    this.fadeOut = 1.2;
    this.state = "LOADING";
    this.stateTimer = 0;
    this.aliveStart = Math.random() * this.lifetime;
    this.lifeStarted = false;

    this.textureLoaded = false;

    this._tmp = new THREE.Vector3();
    this._localPos = new THREE.Vector3();
    this.time = 0;
    this.proximityScale = 1;
    this.baseSize = 0.667 * 10; // match godot packed_companion quad size (~0.6 of 10)
  }

  setTextureFromImage(img) {
    const tex = new THREE.Texture(img);
    tex.needsUpdate = true;
    if ("colorSpace" in tex) tex.colorSpace = THREE.SRGBColorSpace;
    tex.minFilter = THREE.LinearFilter;
    tex.magFilter = THREE.LinearFilter;
    const mat = this.sprite.material;
    if (mat.map && mat.map !== PLACEHOLDER) mat.map.dispose();
    mat.map = tex;
    mat.needsUpdate = true;
    // Scale sprite to match image aspect.
    const w = img.naturalWidth || img.width || 1;
    const h = img.naturalHeight || img.height || 1;
    const aspect = w / h;
    const base = 1.2;
    this.baseWidth = aspect >= 1 ? base : base * aspect;
    this.baseHeight = aspect >= 1 ? base / aspect : base;
    this.textureLoaded = true;
    if (this.state === "LOADING") this._beginFadeIn();
  }

  _beginFadeIn() {
    this.state = "FADE_IN";
    this.stateTimer = 0;
    if (!this.lifeStarted && this.lifetime > 0) this.lifeStarted = true;
  }
  _beginFadeOut() {
    this.state = "FADE_OUT";
    this.stateTimer = 0;
  }

  update(dt) {
    if (!this.target) return;
    this.time += dt * this.driftSpeed;
    const t = this.time + this.phase;
    const r = this.orbitRadius;
    this._localPos.set(
      Math.cos(t) * r,
      Math.sin(t * 0.71) * r * 0.3,
      Math.sin(t) * r,
    );
    this._tmp.set(
      Math.sin(t * this.wanderFrequency * 0.91) * this.wanderStrength,
      Math.cos(t * this.wanderFrequency * 0.67) * this.wanderStrength,
      Math.sin(t * this.wanderFrequency * 1.13) * this.wanderStrength,
    );
    this._localPos.add(this._tmp);
    this._localPos.applyQuaternion(this.orbitQuat);
    this._localPos.add(this.target.position);
    this.sprite.position.copy(this._localPos);

    // Proximity scale.
    const dist = this.sprite.position.distanceTo(this.target.position);
    let t_scale = (dist - this.scaleMin) / (this.scaleMax - this.scaleMin);
    t_scale = Math.max(0, Math.min(1, t_scale));
    this.proximityScale = Math.max(0.001, t_scale);

    // Lifecycle.
    let scaleFactor;
    switch (this.state) {
      case "LOADING":
        scaleFactor = 0.0001;
        break;
      case "FADE_IN": {
        this.stateTimer += dt;
        const u = Math.min(1, this.stateTimer / Math.max(0.001, this.fadeIn));
        const eased = 1 - Math.pow(1 - u, 3);
        scaleFactor = this.proximityScale * eased;
        if (this.stateTimer >= this.fadeIn) {
          this.state = "ALIVE";
          this.stateTimer = this.aliveStart;
          this.aliveStart = 0;
        }
        break;
      }
      case "ALIVE":
        scaleFactor = this.proximityScale;
        if (this.lifetime > 0) {
          this.stateTimer += dt;
          if (this.stateTimer >= this.lifetime) this._beginFadeOut();
        }
        break;
      case "FADE_OUT": {
        this.stateTimer += dt;
        const u = Math.min(1, this.stateTimer / Math.max(0.001, this.fadeOut));
        const eased = Math.pow(u, 3);
        scaleFactor = this.proximityScale * (1 - eased);
        if (this.stateTimer >= this.fadeOut) {
          this.state = "SLEEPING";
          this.stateTimer = 0;
        }
        break;
      }
      case "SLEEPING":
        scaleFactor = 0.0001;
        if (this.sleepTime > 0) {
          this.stateTimer += dt;
          if (this.stateTimer >= this.sleepTime) this._beginFadeIn();
        }
        break;
    }
    scaleFactor = Math.max(0.0001, scaleFactor);
    const w = (this.baseWidth || 1) * scaleFactor;
    const h = (this.baseHeight || 1) * scaleFactor;
    this.sprite.scale.set(w, h, 1);
  }

  dispose() {
    const mat = this.sprite.material;
    if (mat.map && mat.map !== PLACEHOLDER) mat.map.dispose();
    mat.dispose();
  }
}

function ringFor(index) {
  let remaining = index;
  for (let r = 0; r < RING_CAPACITIES.length; r++) {
    if (remaining < RING_CAPACITIES[r]) return { ring: r, slot: remaining };
    remaining -= RING_CAPACITIES[r];
  }
  const last = RING_CAPACITIES.length - 1;
  return { ring: last, slot: remaining % Math.max(RING_CAPACITIES[last], 1) };
}

/**
 * Spawner: queues companions, throttles HTTP image fetches, appends sprites.
 * Loosely follows bitzfarmsspawner.gd.
 */
export class CompanionSpawner {
  constructor({ scene, target }) {
    this.scene = scene;
    this.target = target;
    this.companions = [];
    this.pending = [];
    this.fetchQueue = [];
    this.inFlight = 0;
    this._spawnTimer = null;
  }

  spawn() {
    // Clear existing.
    for (const c of this.companions) {
      this.scene.remove(c.sprite);
      c.dispose();
    }
    this.companions = [];
    this.pending = [];
    this.fetchQueue = [];
    this.inFlight = 0;

    for (const [qid, ids] of Object.entries(COMPANIONS)) {
      for (const sid of ids) this.pending.push({ questId: qid, speciesId: sid });
    }

    if (this._spawnTimer) clearInterval(this._spawnTimer);
    this._spawnTimer = setInterval(() => {
      if (!this.pending.length) {
        clearInterval(this._spawnTimer);
        this._spawnTimer = null;
        return;
      }
      this._spawnOne(this.pending.shift());
    }, SPAWN_INTERVAL_MS);
  }

  _spawnOne(entry) {
    const index = this.companions.length;
    const { ring } = ringFor(index);
    const radius = RING_RADII[Math.min(ring, RING_RADII.length - 1)];
    const c = new Companion({
      questId: entry.questId,
      speciesId: entry.speciesId,
      target: this.target,
      orbitRadius: radius,
    });
    this.companions.push(c);
    this.scene.add(c.sprite);
    this.fetchQueue.push(c);
    this._pumpFetches();
  }

  _pumpFetches() {
    while (this.inFlight < MAX_CONCURRENT_FETCHES && this.fetchQueue.length) {
      const c = this.fetchQueue.shift();
      this.inFlight++;
      this._fetchCompanion(c)
        .catch(() => { /* swallow: let others proceed */ })
        .finally(() => {
          this.inFlight--;
          this._pumpFetches();
        });
    }
  }

  async _fetchCompanion(c) {
    const url = `${REMBG_BASE}/${c.questId}/${c.speciesId}?res=icon`;
    const img = await loadImage(url);
    c.setTextureFromImage(img);
  }

  update(dt) {
    for (const c of this.companions) c.update(dt);
  }
}

function loadImage(src) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.crossOrigin = "anonymous";
    img.onload = () => resolve(img);
    img.onerror = reject;
    img.src = src;
  });
}
