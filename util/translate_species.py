#!/usr/bin/env python3
"""
Translate species_data.json text fields to Brazilian Portuguese (pt-BR).
Keeps scientific names intact, translates common names + all descriptive text.

Usage:
    GEMINI_API_KEY=... python3 translate_species.py
"""

import json
import os
from google import genai
from google.genai import types

IN_PATH = os.path.join(os.path.dirname(__file__), "godot", "data", "species_data.json")
OUT_PATH = IN_PATH  # overwrite in-place

SYSTEM_PROMPT = """You are a precise scientific translator. Translate the given JSON object to Brazilian Portuguese (pt-BR).

Rules:
- Translate all string values EXCEPT the "scientific_name" field — leave it exactly as-is
- For "name" fields: keep the Latin/scientific name exactly as-is, translate only the common name in parentheses
  Example: "Raphanus raphanistrum (Wild Radish)" → "Raphanus raphanistrum (Rabanete Silvestre)"
  Example: "Ant (Formicidae)" → "Formiga (Formicidae)"  [reverse: common first, scientific in parens stays]
- Translate "common_name" fields normally
- Keep all JSON keys in English (do not translate keys)
- Do not add or remove any JSON fields
- Return ONLY valid JSON, no explanation or markdown fences
"""

def translate_batch(client, entries: list[dict]) -> list[dict]:
    payload = json.dumps(entries, ensure_ascii=False, indent=2)
    response = client.models.generate_content(
        model="gemini-2.5-pro",
        config=types.GenerateContentConfig(
            system_instruction=SYSTEM_PROMPT,
            temperature=0.1,
        ),
        contents=f"Translate these species entries to Brazilian Portuguese (pt-BR). Return the same JSON structure with translated values:\n\n{payload}",
    )
    text = response.text.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[1]
        text = text.rsplit("```", 1)[0]
    return json.loads(text)


def main():
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        print("ERROR: Set GEMINI_API_KEY environment variable")
        return

    client = genai.Client(api_key=api_key)

    with open(IN_PATH, encoding="utf-8") as f:
        data = json.load(f)

    all_entries = []  # list of (quest_id, sp_id, entry_dict)
    for quest_id, species_map in data.items():
        for sp_id, entry in species_map.items():
            all_entries.append((quest_id, sp_id, entry))

    print(f"Translating {len(all_entries)} species entries...")

    BATCH_SIZE = 5
    translated_data = {quest_id: {} for quest_id in data}

    for i in range(0, len(all_entries), BATCH_SIZE):
        batch = all_entries[i:i + BATCH_SIZE]
        batch_entries = [e for _, _, e in batch]

        print(f"  Batch {i // BATCH_SIZE + 1}/{(len(all_entries) + BATCH_SIZE - 1) // BATCH_SIZE} ({len(batch)} entries)...")

        try:
            translated = translate_batch(client, batch_entries)
            if not isinstance(translated, list) or len(translated) != len(batch):
                print(f"  WARNING: unexpected response shape, keeping originals for this batch")
                translated = batch_entries
        except Exception as e:
            print(f"  ERROR: {e} — keeping originals for this batch")
            translated = batch_entries

        for (quest_id, sp_id, _), t_entry in zip(batch, translated):
            translated_data[quest_id][sp_id] = t_entry

    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(translated_data, f, ensure_ascii=False, indent=2)

    print(f"\nDone. Saved → {OUT_PATH}")


if __name__ == "__main__":
    main()
