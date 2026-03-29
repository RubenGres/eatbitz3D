"""Export every image blob from the old SQLite cache to disk.

Usage:
    python migrate_cache.py [db_path] [output_dir]

Defaults:
    db_path    = /var/lib/bitz-cache/bitz_cache.db
    output_dir = /opt/EATBITZ/rembg
"""

import json
import sqlite3
import sys
from pathlib import Path

db_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/var/lib/bitz-cache/bitz_cache.db")
out_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("/opt/EATBITZ/rembg")

out_dir.mkdir(parents=True, exist_ok=True)

db = sqlite3.connect(db_path)
db.row_factory = sqlite3.Row
rows = db.execute("SELECT key, image_png, species, labels, scores FROM cache").fetchall()

for row in rows:
    key = row["key"]
    (out_dir / f"{key}.png").write_bytes(row["image_png"])
    (out_dir / f"{key}.json").write_text(json.dumps({
        "species": row["species"],
        "labels": row["labels"],
        "scores": row["scores"],
    }))

db.close()
print(f"Exported {len(rows)} entries to {out_dir}")
