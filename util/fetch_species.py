#!/usr/bin/env python3
"""
Fetch species data from bitz.tools API for all companion quest/species entries.
Saves results to godot/data/species_data.json for offline fallback.
Run this whenever the companion list changes or species content updates.
"""

import json
import os
import re
import sys
import urllib.request
import urllib.error

BASE = "https://api.bitz.tools"
OUT_PATH = os.path.join(os.path.dirname(__file__), "godot", "data", "species_data.json")

# Must match companions.gd — quest_id → species indices
ENTRIES = {
    "de450767-b240-4eaa-95b4-ee0dbde6852c": [0],
    "010f83c9-b710-420f-9cf3-b78cab3f680c": [0, 1, 3, 6, 9],
    "21bb8e65-ce6b-4f79-8a96-864e56322ef6": [0],
    "96a85349-cb5c-46f6-a920-292e6126b6e5": [3, 9, 10, 11, 12, 15, 16, 18, 22, 25, 33, 34, 44, 45, 48, 50, 52, 54, 58, 61, 62, 65, 67, 68, 69, 70, 72, 76, 81, 84, 85],
    "4914a7b9-044f-4677-abf1-04c0566e0829": [0],
    "8323c860-51e2-4453-88ee-89684a531c39": [0, 2, 4],
    "82a95a52-0dc0-4932-8fdd-3645133808fb": [2],
    "0c3cb7a4-0693-4ef7-9aef-eba1ed32a466": [0, 2],
    "4503ee10-b0b7-4a10-a5da-13dafeae7946": [0],
    "102dad33-bbbf-4701-93d1-5eebf9f5286c": [0, 1, 5],
    "3611fe10-b560-480d-94bd-06577633f61f": [0, 4, 8],
    "dc23a859-8819-4c30-8cd1-97d83baf7d31": [0],
    "3f0417ba-12ad-49bb-af4e-3dee43268be9": [0, 1],
    "bd333070-8010-454b-876d-d094fe285dca": [3],
    "c2a481de-3a11-4289-be3f-3b00d1ac8dff": [0],
    "b790c8b7-44af-421e-b2cd-21ec0511fd00": [1],
    "3bd42395-eea0-43aa-a9a9-6cd5d975c6b5": [0, 1],
    "f7eb6983-2c10-47c7-bad4-b45d4a7f2d6c": [0, 1, 2, 3, 4, 5, 6, 8, 9, 10, 12, 14, 16, 17, 18, 19, 20, 23],
    "e089a595-122c-46f2-bcc9-9351f352d902": [2, 11],
    "dc287647-4c08-41e0-940a-6c431d95d732": [0, 1, 4, 10],
    "d8d027d0-cce9-4e03-89ad-2969f4413015": [5, 21],
    "3c91ae94-8fe2-40cc-86e9-774ce67bf05d": [2, 4, 6, 11, 12, 13, 14],
    "dd9fc895-30d0-4b83-a9f0-13cb869afa1a": [2],
    "3be47c5e-92f0-4906-aa57-cbbca0ad533c": [1, 2, 3],
    "2a89203e-9beb-4d23-8df5-f5e0b4a8f720": [0, 1],
    "8bd3e700-80a3-41d8-80e3-902d641ba169": [1, 2, 3, 8, 10],
    "2bf38e96-7ea1-4692-825e-02416d1bbbb8": [12],
    "68a82d2a-5357-4c54-b420-93985c0197bf": [3],
    "ea098515-5b40-4edf-a529-eb6049093975": [0],
    "ef854f14-e01d-4662-af11-fca6b4e38c78": [2, 3],
    "684b6a4f-5f48-41c4-bdce-ea2606e21810": [3, 4],
    "fb689419-f92d-4b43-8202-b3a29787ce58": [2, 7],
    "08f434d0-fb5b-4344-a881-b1f6ed5bc576": [1, 10, 13, 14],
    "2551dfa0-477d-4084-ab73-9d628393f662": [16, 17],
    "1ba4202a-1ab7-4575-b24c-b2c8072eea90": [3, 11],
    "f351819c-969b-4bb8-8c14-e823147da8b1": [5],
    "3a71666b-7c5f-4b98-971b-1cd5d778232e": [6],
    "ee2b5c86-3450-4ed1-aa54-b6470a8ff91b": [0, 7],
    "63ad4ec3-1857-462c-8809-62a070069e47": [0],
    "9b2a85d8-6f7e-4629-bf4c-c50e579ff051": [0],
    "3f178658-ae36-417c-8f5f-f9f1f9e19d91": [0, 4, 10],
    "997aceb0-3994-4aaf-9a44-23beee94106b": [1, 2, 10],
    "d8f4d3e7-40cf-4e9d-ace7-5a69338ca599": [0],
    "351b27fd-a883-40c4-8049-3afd18954769": [1],
    "73c96822-1bf6-4ea9-b109-e8e14c3cf459": [0, 1, 2, 3, 6, 9, 12, 13, 14, 15],
    "5b72018d-8628-4c81-84f6-1a4d7fe56fbb": [0],
    "05e75062-8f06-4d26-9d1b-8b92463e44f8": [1],
    "ca8db078-500a-4061-9c2e-e24c637f8780": [1, 4, 5, 7],
    "36be59a7-a0e9-4ec6-8d4c-d9049074cf9d": [3, 4, 5, 6, 7],
    "f1b320c6-f642-4385-88ab-8ad0c77fef02": [1, 3, 6, 8],
    "3e19d3ed-8f24-5bc5-8016-621a18fb0735": [20, 30, 48],
    "c920f7ee-db6e-58f0-a906-51c55b7a8982": [0, 1, 2, 14, 17],
    "00000000-0000-0000-0000-000000000000": [1, 2, 10, 11, 13, 18],
    "ff518a8d-2524-5d68-8557-95d2df04fc94": [6],
    "538cf4ae-2205-508f-944a-74697f02e24a": [11],
    "129fbb80-99e4-5b32-afaa-4d783bc561b7": [4],
    "8f32e0a4-e5d3-4e57-804b-2c2d1ae7f11f": [0, 3, 5],
    "75bececa-2dc7-4ebb-a3c8-8d37367128a2": [4, 5, 6, 8],
    "93bf7859-64a2-4c40-b9ce-51012bb11de4": [1, 2, 8, 9, 10, 11, 12],
    "1d458f8c-b00d-4601-9b7b-d3728ac43d44": [0],
    "c0255b39-922c-4ee5-bcef-38f3dc132b2c": [0],
    "bca9add2-6147-47c0-a8cf-ae223399aceb": [4],
    "ded6c6ef-c5d8-41b8-999d-4150c18ac5ff": [9, 13, 20],
    "cf5eff9d-d059-4853-a804-995bb7117ad2": [0, 3, 6, 9, 10],
    "e316ea2b-43c6-4184-91f1-264b3dee8ab9": [2],
    "51253f62-8d1b-4da5-9526-e3e7881e7da1": [0],
    "cc9e2dde-6c9e-472c-b8b8-f5e1fb021495": [0],
}

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

def _sci_score(s):
    s = s.strip()
    if not s:
        return 0
    words = s.split()
    first = words[0]
    if re.search(r"[-'0-9]", first):
        return 0
    if len(words) == 1:
        if re.search(r'(idae|inae|aceae|ales|iformes)$', first):
            return 3
        if first[0].isupper() and re.fullmatch(r'[A-Za-z]+', first) and len(first) > 5:
            return 1
        return 0
    if not first[0].isupper():
        return 0
    rest = [w for w in words[1:] if w not in ('×', 'x')]
    if not rest:
        return 0
    second = rest[0]
    if second in ('spp.', 'sp.', 'var.', 'subsp.', 'f.'):
        return 3
    if not second[0].islower():
        return 0
    clean = second.lower().rstrip('.')
    if re.search(r'(oides|ensis|ense|alis|are|aris|inus|ina|inum|atus|ata|atum|'
                 r'arius|aria|arium|icus|ica|icum|ifera|ifer|ans|ens)$', clean):
        return 3
    if len(clean) >= 5 and re.search(r'(us|um|is)$', clean):
        return 3
    if len(clean) >= 6 and clean.endswith('a'):
        return 3
    if len(clean) >= 4 and clean.endswith('i'):
        return 3
    # Multi-word binomial with unrecognized epithet suffix — still likely scientific
    return 2


def split_species_name(name):
    """Split a combined species name into (scientific_name, common_name)."""
    name = name.strip()
    if not name:
        return ('', '')
    paren_groups = re.findall(r'\([^)]+\)', name)
    if len(paren_groups) >= 2:
        return ('', name)
    m = re.match(r'^(.+?)\s*\(([^)]+)\)\s*$', name)
    if m:
        outer, inner = m.group(1).strip(), m.group(2).strip()
        os_, is_ = _sci_score(outer), _sci_score(inner)
        if os_ > is_:
            return (outer, inner)
        elif is_ > os_:
            return (inner, outer)
        elif is_ > 0:
            # Tie: multi-word binomial beats single word
            outer_multi = len(outer.split()) >= 2
            inner_multi = len(inner.split()) >= 2
            if outer_multi and not inner_multi:
                return (outer, inner)
            return (inner, outer)
        elif len(inner.split()) == 1 and inner[0].isupper() and inner.isalpha():
            return (inner, outer)
        return ('', name)
    if ' and ' in name.lower():
        return ('', name)
    if ' - ' in name:
        a, b = [x.strip() for x in name.split(' - ', 1)]
        sa, sb = _sci_score(a), _sci_score(b)
        if sa > sb: return (a, b)
        if sb > sa: return (b, a)
        if len(a.split()) >= 2 and len(b.split()) < 2: return (a, b)
        return ('', name)
    if ' / ' in name:
        a, b = [x.strip() for x in name.split(' / ', 1)]
        sa, sb = _sci_score(a), _sci_score(b)
        if sa > sb: return (a, b)
        if sb > sa: return (b, a)
        return ('', name)
    m2 = re.search(r'\s+or\s+', name, re.IGNORECASE)
    if m2:
        a = name[:m2.start()].strip()
        b = name[m2.end():].strip()
        sa, sb = _sci_score(a), _sci_score(b)
        if sa > sb: return (a, b)
        if sb > sa: return (b, a)
        return ('', name)
    if _sci_score(name) >= 2:
        return (name, '')
    return ('', name)


def parse_assistant(assistant_raw):
    """Parse assistant field and return the species_identification dict."""
    if not assistant_raw:
        return None

    raw = assistant_raw.strip()
    if not raw or raw in ('""', "''", '{}', '[]', 'null', ''):
        return None

    parsed = None
    try:
        parsed = json.loads(raw)
    except Exception:
        pass

    if parsed is None:
        try:
            fixed = ""
            for i, c in enumerate(raw):
                if c == "'":
                    prev_is_letter = i > 0 and raw[i - 1].lower() != raw[i - 1].upper()
                    next_is_letter = i < len(raw) - 1 and raw[i + 1].lower() != raw[i + 1].upper()
                    fixed += "'" if (prev_is_letter and next_is_letter) else '"'
                else:
                    fixed += c
            parsed = json.loads(fixed)
        except Exception:
            pass

    if parsed is None:
        return None

    if not isinstance(parsed, dict):
        return None
    si = parsed.get("species_identification")
    if isinstance(si, list):
        si = si[0] if si else None
    return si if isinstance(si, dict) else None

def main():
    history_cache = {}

    print("Fetching history.json files...")
    for quest_id in ENTRIES:
        for pattern in URL_PATTERNS:
            url = pattern.format(base=BASE, quest_id=quest_id)
            raw, status = try_fetch(url)
            if raw is not None:
                try:
                    history_cache[quest_id] = json.loads(raw)
                    print(f"  OK  {quest_id}")
                    break
                except Exception:
                    print(f"  PARSE_ERR  {quest_id}")
            else:
                print(f"  {status}  {quest_id} @ {url}")

    print()
    result = {}
    ok_count = 0
    fail_count = 0

    for quest_id, species_ids in ENTRIES.items():
        history_data = history_cache.get(quest_id)
        quest_result = {}
        for sp_id in species_ids:
            if history_data is None:
                print(f"  SKIP  {quest_id} sp={sp_id}  (fetch failed)")
                fail_count += 1
                continue
            history = history_data.get("history", history_data if isinstance(history_data, list) else [])
            if sp_id >= len(history):
                print(f"  OOB   {quest_id} sp={sp_id}  (index out of range, len={len(history)})")
                fail_count += 1
                continue
            entry = history[sp_id]
            assistant_raw = entry.get("assistant", "") if isinstance(entry, dict) else ""
            species_info = parse_assistant(assistant_raw)
            if species_info:
                raw_name = species_info.get('name') or ''
                sci, com = split_species_name(raw_name)
                species_info['scientific_name'] = sci
                species_info['common_name'] = com
                quest_result[str(sp_id)] = species_info
                print(f"  OK    {quest_id} sp={sp_id}  {raw_name}")
                ok_count += 1
            else:
                print(f"  EMPTY {quest_id} sp={sp_id}")
                fail_count += 1

        if quest_result:
            result[quest_id] = quest_result

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)

    print(f"\nSaved {ok_count} entries ({fail_count} failed) → {OUT_PATH}")

if __name__ == "__main__":
    main()
