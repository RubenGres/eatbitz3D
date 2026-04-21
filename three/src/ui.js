import { INGREDIENT_STRINGS, UI_STRINGS, CREDITS_HTML } from "./i18n.js";
import { getSpecies } from "./data.js";
import { REMBG_BASE } from "./config.js";

const $ = (sel) => document.querySelector(sel);

export class UI {
  constructor({ onExplore, onReturn, onLocaleChange, isTouch }) {
    this.locale = "en";
    this.isTouch = isTouch;
    this.callbacks = { onExplore, onReturn, onLocaleChange };

    this.panel = $("#info-panel");
    this.nameEl = $("#info-name");
    this.sciEl = $("#info-scientific");
    this.descEl = $("#info-desc");
    this.extraEl = $("#info-extra");
    this.imageEl = $("#info-image");
    this.descTitleEl = $("#info-desc-title");
    this.extraTitleEl = $("#info-extra-title");

    this.welcome = $("#welcome");
    this.exploreBtn = $("#explore-btn");
    this.creditsBtn = $("#credits-btn");
    this.creditsOverlay = $("#credits-overlay");
    this.creditsContent = $("#credits-content");
    this.welcomeDesc = $("#welcome-desc");
    this.welcomeControls = $("#welcome-controls");
    this.welcomeCTA = $("#welcome-cta");
    this.welcomeFooter = $("#welcome-footer");
    this.langEn = $("#lang-en");
    this.langPt = $("#lang-pt");
    this.holdIndicator = $("#hold-indicator");
    this.holdProgress = $("#hold-progress");
    this.edgeOverlay = $("#edge-overlay");
    this.reticle = $("#reticle");

    this._bind();
    this.setLocale("en");
    this.showWelcome();
  }

  _bind() {
    this.exploreBtn.addEventListener("click", () => this.callbacks.onExplore?.());
    this.creditsBtn.addEventListener("click", (e) => {
      e.stopPropagation();
      this.openCredits();
    });
    $(".credits-backdrop").addEventListener("click", () => this.closeCredits());
    $("#credits-close").addEventListener("click", () => this.closeCredits());
    $("#info-close").addEventListener("click", () => this.closeInfo());
    this.panel.addEventListener("click", (e) => {
      if (e.target === this.panel) this.closeInfo();
    });
    this.langEn.addEventListener("click", (e) => { e.stopPropagation(); this.setLocale("en"); });
    this.langPt.addEventListener("click", (e) => { e.stopPropagation(); this.setLocale("pt"); });
    window.addEventListener("keydown", (e) => {
      if (e.key !== "Escape") return;
      if (!this.creditsOverlay.hidden) this.closeCredits();
      else if (this.panel.classList.contains("open")) this.closeInfo();
      else if (this.welcome.hidden) this.callbacks.onReturn?.();
    });
  }

  setLocale(locale) {
    this.locale = locale;
    const t = UI_STRINGS[locale];
    this.welcomeDesc.innerHTML = t.welcome_desc;
    this.welcomeControls.innerHTML = this.isTouch ? t.controls_touch : t.controls_mouse;
    this.welcomeCTA.textContent = this.isTouch ? t.cta_touch : t.cta_mouse;
    this.welcomeFooter.textContent = t.footer;
    this.creditsBtn.textContent = t.about;
    $("#credits-close").textContent = t.close;
    this.creditsContent.innerHTML = CREDITS_HTML[locale];
    this.langEn.classList.toggle("selected", locale === "en");
    this.langPt.classList.toggle("selected", locale === "pt");
    this.callbacks.onLocaleChange?.(locale);
    if (this._lastFocused) this._refreshInfoPanel();
  }

  showWelcome() {
    this.welcome.hidden = false;
    this.reticle.hidden = true;
  }
  hideWelcome() {
    this.welcome.hidden = true;
  }
  openCredits() {
    this.creditsOverlay.hidden = false;
  }
  closeCredits() {
    this.creditsOverlay.hidden = true;
  }

  setExploreMode(on) {
    if (on && !this.isTouch) {
      this.edgeOverlay.classList.add("active");
      this.reticle.hidden = false;
    } else {
      this.edgeOverlay.classList.remove("active");
      this.reticle.hidden = true;
    }
  }

  openInfoForIngredient(ingredient) {
    this._lastFocused = { kind: "ingredient", ref: ingredient };
    const key = ingredient.config.key;
    const t = INGREDIENT_STRINGS[this.locale];
    this.nameEl.textContent = (t[`${key}_NAME`] || key).split("(")[0].split("/")[0].trim();
    this.sciEl.textContent = "";
    this.descEl.textContent = t[`${key}_DESC`] || "";
    this.extraEl.textContent = "";
    this.descTitleEl.hidden = true;
    this.extraTitleEl.hidden = true;
    this.imageEl.src = ingredient.config.card;
    this.panel.classList.add("open");
    this.panel.setAttribute("aria-hidden", "false");
  }

  async openInfoForCompanion(companion) {
    this._lastFocused = { kind: "companion", ref: companion };
    this.nameEl.textContent = "…";
    this.sciEl.textContent = "";
    this.descEl.textContent = "";
    this.extraEl.textContent = "";
    this.imageEl.src = "";
    this.panel.classList.add("open");
    this.panel.setAttribute("aria-hidden", "false");

    const [species] = await Promise.all([
      getSpecies(this.locale, companion.questId, companion.speciesId),
    ]);
    if (this._lastFocused?.ref !== companion) return;
    if (species) {
      const common = (species.common_name && species.common_name.trim())
        ? species.common_name
        : (species.name || "").split("(")[0].split("/")[0].trim() || "Unknown";
      this.nameEl.textContent = common;
      this.sciEl.textContent = species.scientific_name || "";
      this.descEl.textContent = species.what_is_it || "";
      this.extraEl.textContent = species.information || "";
    }
    // Load higher-res inspection image.
    const res = (window.innerWidth <= 720) ? "small" : "medium";
    this.imageEl.src = `${REMBG_BASE}/${companion.questId}/${companion.speciesId}?res=${res}`;
  }

  _refreshInfoPanel() {
    if (!this._lastFocused) return;
    if (!this.panel.classList.contains("open")) return;
    if (this._lastFocused.kind === "ingredient") this.openInfoForIngredient(this._lastFocused.ref);
    else this.openInfoForCompanion(this._lastFocused.ref);
  }

  closeInfo() {
    this.panel.classList.remove("open");
    this.panel.setAttribute("aria-hidden", "true");
    this._lastFocused = null;
  }

  isInfoOpen() {
    return this.panel.classList.contains("open");
  }
  isCreditsOpen() {
    return !this.creditsOverlay.hidden;
  }

  showHold(x, y, progress) {
    this.holdIndicator.hidden = false;
    this.holdIndicator.style.left = x + "px";
    this.holdIndicator.style.top = y + "px";
    const circ = 2 * Math.PI * 16;
    const offset = circ * (1 - progress);
    this.holdProgress.setAttribute("stroke-dashoffset", offset.toFixed(2));
  }
  hideHold() {
    this.holdIndicator.hidden = true;
  }
}
