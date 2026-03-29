"""
BITZ Background Removal Micro-Service
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
GET /rembg/{quest_id}/{species_id}  → returns the masked PNG image
GET /rembg/{quest_id}/{species_id}?info=1  → returns JSON metadata

Results are cached as files on disk so repeated requests skip both the
BITZ API and the Modal segmentation call.  Each entry produces two files
inside CACHE_DIR:  {key}.png  and  {key}.json

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
# Max dimension (width or height) for companion textures served to the client.
# Point-cloud particles don't need full-res images; 512 px is plenty.
MAX_TEXTURE_SIZE = int(os.getenv("BITZ_MAX_TEXTURE_SIZE", "512"))

# ---------------------------------------------------------------------------
# Filesystem cache
# ---------------------------------------------------------------------------


def _cache_key(quest_id: str, species_id: int) -> str:
    return f"{quest_id}_{species_id}"


def _png_path(key: str) -> Path:
    return CACHE_DIR / f"{key}.png"


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


def _downscale_png(png_bytes: bytes, max_side: int = MAX_TEXTURE_SIZE) -> bytes:
    """Downscale a PNG image so the longest side is at most *max_side* px."""
    img = Image.open(io.BytesIO(png_bytes))
    if max(img.size) <= max_side:
        return png_bytes
    img.thumbnail((max_side, max_side), Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    return buf.getvalue()


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
    info: bool = Query(False, description="Return JSON metadata instead of image"),
):
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
        return Response(
            content=cached["image_png"],
            media_type="image/png",
            headers={
                "Cache-Control": "public, max-age=86400, immutable",
                "ETag": f'"{key[:16]}"',
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
    image_png = _downscale_png(image_png)
    labels = str(data.get("labels", []))
    scores = str(data.get("scores", []))

    # --- store in cache ---
    _put_cache(key, image_png, species_name, labels, scores)

    if info:
        return JSONResponse({
            "cached": False,
            "species": species_name,
            "labels": labels,
            "scores": scores,
        })

    return Response(
        content=image_png,
        media_type="image/png",
        headers={
            "Cache-Control": "public, max-age=86400, immutable",
            "ETag": f'"{key[:16]}"',
        },
    )


@app.delete("/cache/{quest_id}/{species_id}")
async def invalidate_cache(quest_id: str, species_id: int):
    key = _cache_key(quest_id, species_id)
    _png_path(key).unlink(missing_ok=True)
    _meta_path(key).unlink(missing_ok=True)
    return {"deleted": key}


@app.get("/health")
async def health():
    count = sum(1 for f in CACHE_DIR.glob("*.png")) if CACHE_DIR.exists() else 0
    return {"status": "ok", "cached_entries": count}