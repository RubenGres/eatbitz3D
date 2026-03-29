"""
BITZ Background Removal Micro-Service
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
GET /rembg/{quest_id}/{species_id}           → returns the full-size masked PNG
GET /rembg/{quest_id}/{species_id}?res=icon  → returns a resized variant
GET /rembg/{quest_id}/{species_id}?info=1    → returns JSON metadata

Supported res values: icon (50), thumb (150), small (300), medium (800), large (1600)
Omit res to get the original segmented image.

Results are cached as files on disk.  Each entry produces:
  {key}.png            — full-size masked image
  {key}_{res}.png      — resized variant (created on first request)
  {key}.json           — metadata (species, labels, scores)

Run:
    pip install fastapi uvicorn httpx
    uvicorn bitz_bg_service:app --reload --port 8787
"""

from __future__ import annotations

import base64
import io
import json
import os
from contextlib import asynccontextmanager
from pathlib import Path

import httpx
from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import JSONResponse, Response
from PIL import Image

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

BITZ_API = "https://api.bitz.tools"
MODAL_URL = "https://ruben-g-gres--grounded-sam2-api-segment.modal.run"
CACHE_DIR = Path(os.getenv("BITZ_CACHE_DIR", "/opt/EATBITZ/rembg"))
HTTP_TIMEOUT = 240.0  # Modal can be slow on cold starts

SIZES = {
    "icon":   (50, 50),
    "thumb":  (150, 150),
    "small":  (300, 300),
    "medium": (800, 800),
    "large":  (1600, 1600),
}

# ---------------------------------------------------------------------------
# Filesystem cache
# ---------------------------------------------------------------------------


def _cache_key(quest_id: str, species_id: int) -> str:
    return f"{quest_id}_{species_id}"


def _png_path(key: str) -> Path:
    return CACHE_DIR / f"{key}.png"


def _resized_path(key: str, res: str) -> Path:
    return CACHE_DIR / f"{key}_{res}.png"


def _meta_path(key: str) -> Path:
    return CACHE_DIR / f"{key}.json"


def _get_cached(key: str) -> dict | None:
    png = _png_path(key)
    meta = _meta_path(key)
    if not png.exists() or not meta.exists():
        return None
    return {
        "image_png": png.read_bytes(),
        **json.loads(meta.read_text()),
    }


def _put_cache(
    key: str,
    image_png: bytes,
    species: str,
    labels: str,
    scores: str,
):
    _png_path(key).write_bytes(image_png)
    _meta_path(key).write_text(json.dumps({
        "species": species,
        "labels": labels,
        "scores": scores,
    }))


def _get_resized(key: str, res: str, source_png: bytes) -> bytes:
    """Return a resized variant, generating and caching it if needed."""
    path = _resized_path(key, res)
    if path.exists():
        return path.read_bytes()
    max_side = SIZES[res]
    img = Image.open(io.BytesIO(source_png))
    img.thumbnail(max_side, Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    data = buf.getvalue()
    path.write_bytes(data)
    return data


# ---------------------------------------------------------------------------
# App lifecycle
# ---------------------------------------------------------------------------

client: httpx.AsyncClient


@asynccontextmanager
async def lifespan(_app: FastAPI):
    global client
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    client = httpx.AsyncClient(timeout=HTTP_TIMEOUT)
    yield
    await client.aclose()


app = FastAPI(title="BITZ Background Removal", lifespan=lifespan)

# ---------------------------------------------------------------------------
# BITZ helpers
# ---------------------------------------------------------------------------


async def fetch_species_data(quest_id: str, species_id: int) -> dict:
    url = f"{BITZ_API}/explore/data/{quest_id}/history.json"
    r = await client.get(url)
    if r.status_code != 200:
        raise HTTPException(502, f"BITZ history request failed ({r.status_code})")
    history = r.json().get("history", [])
    if species_id >= len(history):
        raise HTTPException(404, f"species_id {species_id} out of range ({len(history)} entries)")
    return history[species_id]


async def fetch_species_image(quest_id: str, species_id: int, quality: str = "medium") -> bytes:
    url = f"{BITZ_API}/explore/images/{quest_id}/{species_id}_image.jpg?res={quality}"
    r = await client.get(url)
    if r.status_code != 200:
        raise HTTPException(502, f"BITZ image request failed ({r.status_code})")
    return r.content


async def remove_bg(image_bytes: bytes, prompt: str) -> dict:
    b64 = base64.b64encode(image_bytes).decode()
    r = await client.post(MODAL_URL, json={"image_base64": b64, "prompt": prompt})
    if r.status_code != 200:
        raise HTTPException(502, f"Modal segmentation failed ({r.status_code})")
    return r.json()


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------


@app.get("/rembg/{quest_id}/{species_id}")
async def get_rembg(
    quest_id: str,
    species_id: int,
    res: str | None = Query(None, description="Resolution preset: icon, thumb, small, medium, large"),
    info: bool = Query(False, description="Return JSON metadata instead of image"),
):
    if res is not None and res not in SIZES:
        raise HTTPException(400, f"Unknown res '{res}'. Choose from: {', '.join(SIZES)}")

    key = _cache_key(quest_id, species_id)

    # --- check cache ---
    cached = _get_cached(key)
    if cached is not None:
        if info:
            return JSONResponse({
                "cached": True,
                "species": cached["species"],
                "labels": cached["labels"],
                "scores": cached["scores"],
            })
        image_png = _get_resized(key, res, cached["image_png"]) if res else cached["image_png"]
        etag = f"{key}_{res}" if res else key
        return Response(
            content=image_png,
            media_type="image/png",
            headers={
                "Cache-Control": "public, max-age=86400, immutable",
                "ETag": f'"{etag[:16]}"',
            },
        )

    # --- fetch from BITZ ---
    species_info = await fetch_species_data(quest_id, species_id)
    species_name = species_info.get("name", "Unknown")

    image_bytes = await fetch_species_image(quest_id, species_id)

    # --- segment via Modal ---
    data = await remove_bg(image_bytes, species_name)

    masked_b64 = data.get("masked_image_base64", "")
    if not masked_b64:
        raise HTTPException(502, "Modal returned no masked image")

    image_png = base64.b64decode(masked_b64)
    labels = str(data.get("labels", []))
    scores = str(data.get("scores", []))

    # --- store full-size in cache ---
    _put_cache(key, image_png, species_name, labels, scores)

    if info:
        return JSONResponse({
            "cached": False,
            "species": species_name,
            "labels": labels,
            "scores": scores,
        })

    out = _get_resized(key, res, image_png) if res else image_png
    etag = f"{key}_{res}" if res else key
    return Response(
        content=out,
        media_type="image/png",
        headers={
            "Cache-Control": "public, max-age=86400, immutable",
            "ETag": f'"{etag[:16]}"',
        },
    )


@app.delete("/cache/{quest_id}/{species_id}")
async def invalidate_cache(quest_id: str, species_id: int):
    key = _cache_key(quest_id, species_id)
    _png_path(key).unlink(missing_ok=True)
    _meta_path(key).unlink(missing_ok=True)
    for res_name in SIZES:
        _resized_path(key, res_name).unlink(missing_ok=True)
    return {"deleted": key}


@app.get("/health")
async def health():
    count = sum(1 for f in CACHE_DIR.glob("*.png")) if CACHE_DIR.exists() else 0
    return {"status": "ok", "cached_entries": count}