"""Export every image blob from the old SQLite cache to disk with readable names.

Fetches quest/species combos from the BITZ API, computes the SHA-256 hash
for each, and matches against the DB keys to recover the original IDs.

Usage:
    python migrate_cache.py [db_path] [output_dir]

Defaults:
    db_path    = /var/lib/bitz-cache/bitz_cache.db
    output_dir = /opt/EATBITZ/rembg
"""

import hashlib
import json
import sqlite3
import sys
import urllib.request
from pathlib import Path

BITZ_API = "https://api.bitz.tools"

db_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/var/lib/bitz-cache/bitz_cache.db")
out_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("/opt/EATBITZ/rembg")

out_dir.mkdir(parents=True, exist_ok=True)

db = sqlite3.connect(db_path)
db.row_factory = sqlite3.Row
rows = {row["key"]: row for row in db.execute(
    "SELECT key, image_png, species, labels, scores FROM cache"
).fetchall()}

print(f"Found {len(rows)} entries in DB, fetching quests from BITZ API...")

with urllib.request.urlopen(f"{BITZ_API}/explore/quests") as resp:
    quests = json.loads(resp.read())

renamed = 0
for quest in quests:
    quest_id = quest["id"]
    with urllib.request.urlopen(f"{BITZ_API}/explore/data/{quest_id}/history.json") as resp:
        history = json.loads(resp.read()).get("history", [])

    for species_id in range(len(history)):
        key = hashlib.sha256(f"{quest_id}:{species_id}".encode()).hexdigest()
        if key not in rows:
            continue

        row = rows.pop(key)
        readable = f"{quest_id}_{species_id}"
        (out_dir / f"{readable}.png").write_bytes(row["image_png"])
        (out_dir / f"{readable}.json").write_text(json.dumps({
            "species": row["species"],
            "labels": row["labels"],
            "scores": row["scores"],
        }))
        renamed += 1
        print(f"  {key[:12]}... -> {readable}")

    if not rows:
        break

if rows:
    print(f"\n{len(rows)} entries could not be matched, saving with hash names:")
    for key, row in rows.items():
        (out_dir / f"{key}.png").write_bytes(row["image_png"])
        (out_dir / f"{key}.json").write_text(json.dumps({
            "species": row["species"],
            "labels": row["labels"],
            "scores": row["scores"],
        }))
        print(f"  {key[:12]}... (unmatched)")

db.close()
print(f"\nDone: {renamed} renamed, {len(rows)} unmatched")
