import * as THREE from "three";
import { OBJLoader } from "three/addons/loaders/OBJLoader.js";

const objLoader = new OBJLoader();
const texLoader = new THREE.TextureLoader();
const modelCache = new Map();

async function loadModel(name) {
  if (modelCache.has(name)) return modelCache.get(name);
  const p = (async () => {
    const [obj, texture] = await Promise.all([
      new Promise((resolve, reject) =>
        objLoader.load(`assets/models/${name}/model.obj`, resolve, undefined, reject),
      ),
      new Promise((resolve, reject) =>
        texLoader.load(`assets/models/${name}/texture.jpg`, resolve, undefined, reject),
      ),
    ]);
    if ("colorSpace" in texture) texture.colorSpace = THREE.SRGBColorSpace;
    texture.anisotropy = 4;
    const material = new THREE.MeshStandardMaterial({
      map: texture,
      roughness: 0.85,
      metalness: 0.05,
      emissive: new THREE.Color(0x111111),
      emissiveMap: texture,
      emissiveIntensity: 0.25,
      transparent: false,
      side: THREE.DoubleSide,
    });

    // Merge all geometry into one for cleaner highlight/outline control.
    const geometries = [];
    obj.traverse((child) => {
      if (child.isMesh) {
        child.geometry.computeVertexNormals();
        geometries.push(child.geometry);
      }
    });
    const merged = geometries.length === 1 ? geometries[0] : mergeGeometries(geometries);
    merged.center();
    return { geometry: merged, material };
  })();
  modelCache.set(name, p);
  return p;
}

// Simple geometry merge (attributes-only, no groups). Works for Meshy OBJ output.
function mergeGeometries(geometries) {
  const merged = new THREE.BufferGeometry();
  const attrNames = Object.keys(geometries[0].attributes);

  for (const name of attrNames) {
    let totalCount = 0;
    const arrays = [];
    let itemSize = 0;
    for (const g of geometries) {
      const a = g.attributes[name];
      if (!a) { arrays.length = 0; break; }
      itemSize = a.itemSize;
      arrays.push(a.array);
      totalCount += a.array.length;
    }
    if (!arrays.length) continue;
    const Ctor = arrays[0].constructor;
    const out = new Ctor(totalCount);
    let offset = 0;
    for (const arr of arrays) {
      out.set(arr, offset);
      offset += arr.length;
    }
    merged.setAttribute(name, new THREE.BufferAttribute(out, itemSize));
  }
  return merged;
}

export class Ingredient {
  constructor(config) {
    this.config = config;
    this.group = new THREE.Group();
    this.group.position.fromArray(config.position);
    this.group.userData.ingredient = this;
    this.group.userData.selectable = true;
    this.group.userData.type = "ingredient";
    this.mesh = null;
    this.outline = null;
    this._highlighted = false;
    this._rotSpeed = 0.1 + Math.random() * 0.05;
  }

  async load() {
    const { geometry, material } = await loadModel(this.config.model);
    this.mesh = new THREE.Mesh(geometry, material);
    this.mesh.scale.setScalar(this.config.scale);
    this.mesh.rotation.y = this.config.rotY || 0;
    this.mesh.userData.ingredient = this;
    this.mesh.userData.selectable = true;

    const outlineMat = new THREE.MeshBasicMaterial({
      color: 0xffffff,
      side: THREE.BackSide,
      transparent: true,
      opacity: 0.25,
      depthWrite: false,
    });
    this.outline = new THREE.Mesh(geometry, outlineMat);
    this.outline.scale.copy(this.mesh.scale).multiplyScalar(1.06);
    this.outline.rotation.copy(this.mesh.rotation);
    this.outline.visible = false;
    this.outline.renderOrder = -1;

    this.group.add(this.outline);
    this.group.add(this.mesh);
  }

  setHighlighted(v) {
    this._highlighted = v;
    if (this.outline) this.outline.visible = v;
  }

  update(dt) {
    if (this.mesh) this.mesh.rotation.y += this._rotSpeed * dt;
    if (this.outline) this.outline.rotation.y = this.mesh.rotation.y;
  }
}

export async function buildIngredients(configs, parent) {
  const list = [];
  for (const cfg of configs) {
    const ing = new Ingredient(cfg);
    await ing.load();
    parent.add(ing.group);
    list.push(ing);
  }
  return list;
}
