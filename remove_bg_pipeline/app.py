"""
BITZ Background Removal Micro-Service
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
GET /rembg/{quest_id}/{species_id}  → returns the masked PNG image
GET /rembg/{quest_id}/{species_id}?info=1  → returns JSON metadata

Results are cached in a local SQLite database so repeated requests
skip both the BITZ API and the Modal segmentation call.

Run:
    pip install fastapi uvicorn httpx
    uvicorn bitz_bg_service:app --reload --port 8787
"""

from __future__ import annotations

import base64
import hashlib
import os
import sqlite3
import time
from contextlib import asynccontextmanager
from pathlib import Path

import httpx
from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import JSONResponse, Response

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

BITZ_API = "https://api.bitz.tools"
MODAL_URL = "https://ruben-g-gres--grounded-sam2-api-segment.modal.run"
DB_PATH = Path(os.getenv("BITZ_CACHE_DB_PATH", "/var/lib/bitz-cache/bitz_cache.db"))
HTTP_TIMEOUT = 60.0  # Modal can be slow on cold starts

# ---------------------------------------------------------------------------
# SQLite cache
# ---------------------------------------------------------------------------


def _init_db(db: sqlite3.Connection):
    db.execute("""
        CREATE TABLE IF NOT EXISTS cache (
            key        TEXT PRIMARY KEY,
            image_png  BLOB NOT NULL,
            species    TEXT,
            labels     TEXT,
            scores     TEXT,
            created_at REAL NOT NULL
        )
    """)
    db.commit()


def _cache_key(quest_id: str, species_id: int) -> str:
    raw = f"{quest_id}:{species_id}"
    return hashlib.sha256(raw.encode()).hexdigest()


def _get_cached(db: sqlite3.Connection, key: str) -> sqlite3.Row | None:
    row = db.execute(
        "SELECT image_png, species, labels, scores FROM cache WHERE key = ?",
        (key,),
    ).fetchone()
    return row


def _put_cache(
    db: sqlite3.Connection,
    key: str,
    image_png: bytes,
    species: str,
    labels: str,
    scores: str,
):
    db.execute(
        "INSERT OR REPLACE INTO cache (key, image_png, species, labels, scores, created_at) "
        "VALUES (?, ?, ?, ?, ?, ?)",
        (key, image_png, species, labels, scores, time.time()),
    )
    db.commit()


# ---------------------------------------------------------------------------
# App lifecycle
# ---------------------------------------------------------------------------

db: sqlite3.Connection
client: httpx.AsyncClient


@asynccontextmanager
async def lifespan(_app: FastAPI):
    global db, client
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(DB_PATH, check_same_thread=False)
    db.row_factory = sqlite3.Row
    _init_db(db)
    client = httpx.AsyncClient(timeout=HTTP_TIMEOUT)
    yield
    await client.aclose()
    db.close()


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


async def fetch_species_image(quest_id: str, species_id: int) -> bytes:
    url = f"{BITZ_API}/explore/images/{quest_id}/{species_id}_image.jpg?res=medium"
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
    info: bool = Query(False, description="Return JSON metadata instead of image"),
):
    key = _cache_key(quest_id, species_id)

    # --- check cache ---
    cached = _get_cached(db, key)
    if cached is not None:
        if info:
            return JSONResponse({
                "cached": True,
                "species": cached["species"],
                "labels": cached["labels"],
                "scores": cached["scores"],
            })
        return Response(content=cached["image_png"], media_type="image/png")

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

    # --- store in cache ---
    _put_cache(db, key, image_png, species_name, labels, scores)

    if info:
        return JSONResponse({
            "cached": False,
            "species": species_name,
            "labels": labels,
            "scores": scores,
        })

    return Response(content=image_png, media_type="image/png")


@app.delete("/cache/{quest_id}/{species_id}")
async def invalidate_cache(quest_id: str, species_id: int):
    key = _cache_key(quest_id, species_id)
    db.execute("DELETE FROM cache WHERE key = ?", (key,))
    db.commit()
    return {"deleted": key}


@app.get("/health")
async def health():
    count = db.execute("SELECT COUNT(*) as n FROM cache").fetchone()["n"]
    return {"status": "ok", "cached_entries": count}