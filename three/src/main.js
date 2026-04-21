import * as THREE from "three";
import { INGREDIENTS } from "./config.js";
import { buildIngredients } from "./ingredients.js";
import { CompanionSpawner } from "./companions.js";
import { LookController, setupGyro } from "./controls.js";
import { UI } from "./ui.js";
import { loadSpeciesData } from "./data.js";

const IS_TOUCH = matchMedia("(pointer: coarse)").matches ||
  ("ontouchstart" in window && navigator.maxTouchPoints > 0);

const canvas = document.getElementById("scene");

const renderer = new THREE.WebGLRenderer({
  canvas,
  antialias: !IS_TOUCH,
  alpha: false,
  powerPreference: "high-performance",
});
renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, IS_TOUCH ? 1.5 : 2));
renderer.setSize(window.innerWidth, window.innerHeight, false);
if ("outputColorSpace" in renderer) renderer.outputColorSpace = THREE.SRGBColorSpace;

const scene = new THREE.Scene();
scene.background = new THREE.Color(0x000000);
scene.fog = new THREE.Fog(0x000000, 12, 40);

const camera = new THREE.PerspectiveCamera(
  70,
  window.innerWidth / window.innerHeight,
  0.05,
  200,
);
camera.position.set(0, 0, 0);

// Lights.
const hemi = new THREE.HemisphereLight(0xffffff, 0x222233, 0.9);
scene.add(hemi);
const key = new THREE.DirectionalLight(0xffffff, 1.2);
key.position.set(6, 8, 4);
scene.add(key);
const fill = new THREE.DirectionalLight(0xa0b3ff, 0.4);
fill.position.set(-6, -2, -6);
scene.add(fill);

// "Target" — the thing the companions orbit. In the Godot scene they orbited
// the camera/head; here we use a dedicated node at the scene origin.
const target = new THREE.Object3D();
target.position.set(0, 0, 0);
scene.add(target);

// Raycasting.
const raycaster = new THREE.Raycaster();
raycaster.params.Points = { threshold: 0.1 };

// Look controller.
const look = new LookController(camera, canvas);
const gyro = setupGyro(look);

// UI.
const ui = new UI({
  isTouch: IS_TOUCH,
  onExplore: enterExplore,
  onReturn: returnToLanding,
  onLocaleChange: (locale) => {
    loadSpeciesData(locale).catch(() => {});
  },
});

// Scene builds.
let ingredients = [];
const spawner = new CompanionSpawner({ scene, target });

buildIngredients(INGREDIENTS, scene).then((list) => {
  ingredients = list;
  spawner.spawn();
});

// Interaction state.
let hovered = null;
let exploring = false;
const HOLD_DURATION = 0.2;
const HOLD_MAX_DRIFT = 20;
let touchState = null;

// --- Input handlers (aside from LookController's own motion) ---
const pointer = new THREE.Vector2();

canvas.addEventListener("mousemove", (e) => {
  const rect = canvas.getBoundingClientRect();
  pointer.x = ((e.clientX - rect.left) / rect.width) * 2 - 1;
  pointer.y = -((e.clientY - rect.top) / rect.height) * 2 + 1;
});

canvas.addEventListener("mousedown", (e) => {
  if (IS_TOUCH) return;
  if (ui.isInfoOpen() || ui.isCreditsOpen()) return;
  if (!exploring) return;
  if (e.button !== 0) return;
  if (hovered) {
    openSelected(hovered);
  }
});

canvas.addEventListener("touchstart", (e) => {
  if (!IS_TOUCH || !exploring) return;
  if (ui.isInfoOpen() || ui.isCreditsOpen()) return;
  const t = e.touches[0];
  touchState = {
    id: t.identifier,
    startX: t.clientX,
    startY: t.clientY,
    start: performance.now() / 1000,
    held: true,
  };
  updateHoverFromTouch(t.clientX, t.clientY);
}, { passive: true });

canvas.addEventListener("touchmove", (e) => {
  if (!touchState) return;
  for (const t of e.touches) {
    if (t.identifier === touchState.id) {
      if (Math.hypot(t.clientX - touchState.startX, t.clientY - touchState.startY) > HOLD_MAX_DRIFT) {
        touchState.held = false;
        ui.hideHold();
      }
      break;
    }
  }
}, { passive: true });

const endTouch = () => {
  touchState = null;
  ui.hideHold();
};
canvas.addEventListener("touchend", endTouch);
canvas.addEventListener("touchcancel", endTouch);

function updateHoverFromTouch(x, y) {
  const rect = canvas.getBoundingClientRect();
  pointer.x = ((x - rect.left) / rect.width) * 2 - 1;
  pointer.y = -((y - rect.top) / rect.height) * 2 + 1;
}

function enterExplore() {
  exploring = true;
  ui.hideWelcome();
  if (IS_TOUCH) {
    look.setMode({ touch: true, gyro: true });
    gyro.start();
  } else {
    look.setMode({ mouse: true, edge: true });
    ui.setExploreMode(true);
  }
}

function returnToLanding() {
  exploring = false;
  ui.closeInfo();
  ui.closeCredits();
  ui.setExploreMode(false);
  look.setMode({});
  ui.showWelcome();
}

function openSelected(target) {
  if (target.userData.type === "ingredient") {
    ui.openInfoForIngredient(target.userData.ingredient);
  } else if (target.userData.type === "companion") {
    ui.openInfoForCompanion(target.userData.companion);
  }
  clearHighlight();
}

function clearHighlight() {
  if (hovered && hovered.userData.ingredient) {
    hovered.userData.ingredient.setHighlighted(false);
  }
  hovered = null;
}

// --- Resize ---
function onResize() {
  const w = window.innerWidth, h = window.innerHeight;
  renderer.setSize(w, h, false);
  camera.aspect = w / h;
  camera.updateProjectionMatrix();
}
window.addEventListener("resize", onResize);
window.addEventListener("orientationchange", () => setTimeout(onResize, 100));

// --- Pick: return the selectable object under the current pointer. ---
function pickSelectable() {
  if (!exploring) return null;
  if (ui.isInfoOpen() || ui.isCreditsOpen()) return null;

  if (IS_TOUCH) {
    // On touch: ray from screen center (the player is "looking at the center")
    // feels wrong; we raycast through the last touch pointer.
    raycaster.setFromCamera(pointer, camera);
  } else if (look.edgeMode) {
    // Desktop explore: reticle is at screen center.
    raycaster.setFromCamera({ x: 0, y: 0 }, camera);
  } else {
    raycaster.setFromCamera(pointer, camera);
  }
  const candidates = [];
  for (const ing of ingredients) if (ing.mesh) candidates.push(ing.mesh);
  for (const c of spawner.companions) candidates.push(c.sprite);
  const hits = raycaster.intersectObjects(candidates, false);
  for (const h of hits) {
    const obj = h.object;
    if (obj.userData.selectable) return obj;
  }
  return null;
}

// --- Animation loop ---
const clock = new THREE.Clock();
function tick() {
  const dt = Math.min(0.05, clock.getDelta());

  look.update(dt);
  for (const ing of ingredients) ing.update(dt);
  spawner.update(dt);

  // Hover / touch-hold.
  if (exploring && !ui.isInfoOpen() && !ui.isCreditsOpen()) {
    const picked = pickSelectable();
    if (picked !== hovered) {
      if (hovered && hovered.userData.ingredient) {
        hovered.userData.ingredient.setHighlighted(false);
      }
      hovered = picked;
      if (hovered && hovered.userData.ingredient) {
        hovered.userData.ingredient.setHighlighted(true);
      }
    }

    if (IS_TOUCH && touchState && touchState.held) {
      const elapsed = performance.now() / 1000 - touchState.start;
      if (hovered) {
        ui.showHold(touchState.startX, touchState.startY, Math.min(1, elapsed / HOLD_DURATION));
        if (elapsed >= HOLD_DURATION) {
          const h = hovered;
          touchState.held = false;
          ui.hideHold();
          openSelected(h);
        }
      } else {
        ui.hideHold();
      }
    }
  } else if (hovered) {
    clearHighlight();
  }

  renderer.render(scene, camera);
  requestAnimationFrame(tick);
}

onResize();
tick();
