#!/usr/bin/env python3
"""
Fetch species data from bitz.tools API for specific quest/species entries.
Tries multiple URL patterns to find a working file-serving endpoint.
"""

import json
import urllib.request
import urllib.error

BASE = "https://api.bitz.tools"

ENTRIES = {
    "de450767-b240-4eaa-95b4-ee0dbde6852c": [0],
    "010f83c9-b710-420f-9cf3-b78cab3f680c": [0, 1, 3],
    "21bb8e65-ce6b-4f79-8a96-864e56322ef6": [0],
    "96a85349-cb5c-46f6-a920-292e6126b6e5": [9, 10, 18, 22, 33, 34, 44, 45, 52, 58, 69, 85],
    "4503ee10-b0b7-4a10-a5da-13dafeae7946": [0],
    "8323c860-51e2-4453-88ee-89684a531c39": [4],
    "102dad33-bbbf-4701-93d1-5eebf9f5286c": [1, 5],
    "3be47c5e-92f0-4906-aa57-cbbca0ad533c": [2],
    "997aceb0-3994-4aaf-9a44-23beee94106b": [2, 10],
    "08f434d0-fb5b-4344-a881-b1f6ed5bc576": [14],
    "3e19d3ed-8f24-5bc5-8016-621a18fb0735": [20, 30, 48],
    "c920f7ee-db6e-58f0-a906-51c55b7a8982": [0, 1, 2, 14, 17],
    "00000000-0000-0000-0000-000000000000": [1, 2, 10, 11, 13, 18],
    "ff518a8d-2524-5d68-8557-95d2df04fc94": [6],
    "538cf4ae-2205-508f-944a-74697f02e24a": [11],
    "129fbb80-99e4-5b32-afaa-4d783bc561b7": [4],
    "73c96822-1bf6-4ea9-b109-e8e14c3cf459": [13],
}

# URL patterns to try (in order)
URL_PATTERNS = [
    "{base}/explore/data/{quest_id}/history.json",
    "{base}/api/quest/{quest_id}/history",
    "{base}/quest/{quest_id}/history.json",
]

def try_fetch(url):
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0", "Accept": "application/json,*/*"})
        with urllib.request.urlopen(req, timeout=15) as resp:
            return resp.read().decode("utf-8"), resp.status
    except urllib.error.HTTPError as e:
        return None, e.code
    except Exception as e:
        return None, str(e)

def extract_name(assistant_raw):
    """Try to extract species name from assistant field (various formats)."""
    if not assistant_raw:
        return None, "EMPTY_FIELD"

    raw = assistant_raw.strip()
    if not raw or raw in ('""', "''", '{}', '[]', 'null', ''):
        return None, "EMPTY_STRING"

    # Try direct JSON parse
    parsed = None
    try:
        parsed = json.loads(raw)
    except Exception:
        pass

    # Try fixing single quotes -> double quotes
    if parsed is None:
        try:
            fixed = raw.replace("'", '"')
            parsed = json.loads(fixed)
        except Exception:
            pass

    # Try double-encoded JSON (string containing JSON)
    if parsed is None:
        try:
            inner = json.loads(json.loads(raw))
            parsed = inner
        except Exception:
            pass

    if parsed is not None:
        # Look for name in various keys
        for key_path in [
            ["species_identification", "name"],
            ["species", "name"],
            ["identification", "name"],
            ["name"],
            ["species_name"],
            ["common_name"],
            ["scientific_name"],
        ]:
            obj = parsed
            try:
                for k in key_path:
                    obj = obj[k]
                if obj and isinstance(obj, str):
                    return obj, None
            except (KeyError, TypeError):
                pass

        # Fallback: return all top-level keys
        if isinstance(parsed, dict):
            return f"KEYS:{list(parsed.keys())}", None

    # Could not parse - return raw snippet
    return None, f"PARSE_FAIL"

def main():
    cache = {}  # quest_id -> (history_data or None, error)

    print("Fetching history.json files...\n")

    # Fetch all unique quest IDs
    for quest_id in ENTRIES:
        data, status = None, None
        for pattern in URL_PATTERNS:
            url = pattern.format(base=BASE, quest_id=quest_id)
            raw, status = try_fetch(url)
            if raw is not None:
                try:
                    data = json.loads(raw)
                    print(f"  OK  {quest_id} via {url}")
                    break
                except Exception as e:
                    print(f"  PARSE_ERR {quest_id}: {e}")
                    data = None
            else:
                print(f"  {status}  {quest_id} @ {url}")
        cache[quest_id] = data

    print("\n" + "="*120)
    print(f"{'quest_id':<40} {'sp_id':<6} {'name_found':<40} {'raw_assistant_snippet (first 200 chars)'}")
    print("="*120)

    for quest_id, species_ids in ENTRIES.items():
        history_data = cache.get(quest_id)
        for sp_id in species_ids:
            if history_data is None:
                print(f"{quest_id:<40} {sp_id:<6} {'FETCH_FAILED':<40} -")
                continue

            history = history_data.get("history", history_data if isinstance(history_data, list) else [])
            if sp_id >= len(history):
                print(f"{quest_id:<40} {sp_id:<6} {'INDEX_OUT_OF_RANGE':<40} -")
                continue

            entry = history[sp_id]
            assistant_raw = entry.get("assistant", "") if isinstance(entry, dict) else ""
            snippet = str(assistant_raw)[:200].replace("\n", " ")

            name, err = extract_name(assistant_raw)
            if name:
                name_display = str(name)[:38]
            else:
                name_display = f"EMPTY ({err})" if err else "EMPTY"

            print(f"{quest_id:<40} {sp_id:<6} {name_display:<40} {snippet}")

    print("\nDone.")

if __name__ == "__main__":
    main()
