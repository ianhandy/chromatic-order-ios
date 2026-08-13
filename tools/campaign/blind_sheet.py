"""Render the campaign boards with numbers only — no names.

Used for blind recognition testing: show a reader the shapes with nothing
but an index and ask what each one looks like. If the answers don't land
near the level's name, the shape isn't reading as the thing it's called.

    python3 blind_sheet.py            # writes blind-a.png .. blind-e.png
"""

from __future__ import annotations

import json
from pathlib import Path

from oklch import OKLCh, to_srgb8

HERE = Path(__file__).resolve().parent
CAMPAIGN = HERE.parents[1] / "ChromaticOrder" / "Resources" / "campaign.json"
PER_SHEET = 20
COLS = 5
CELL = 20


def render():
    from PIL import Image, ImageDraw

    campaign = json.loads(CAMPAIGN.read_text())
    levels = campaign["levels"]
    out_paths = []

    pad, label_h = 12, 20
    tile_w = 11 * CELL + pad * 2
    tile_h = 9 * CELL + pad + label_h

    for sheet_i in range(0, len(levels), PER_SHEET):
        batch = levels[sheet_i:sheet_i + PER_SHEET]
        rows = (len(batch) + COLS - 1) // COLS
        img = Image.new("RGB", (COLS * tile_w, rows * tile_h), (16, 16, 18))
        draw = ImageDraw.Draw(img)
        for i, lv in enumerate(batch):
            ox = (i % COLS) * tile_w
            oy = (i // COLS) * tile_h
            doc = lv["doc"]
            board = {}
            for g in doc["gradients"]:
                for c in g["cells"]:
                    board[(c["r"], c["c"])] = c
            gw, gh = doc["gridW"], doc["gridH"]
            x0 = ox + pad + (11 - gw) * CELL // 2
            y0 = oy + label_h + (9 - gh) * CELL // 2
            for (r, c), spec in board.items():
                rgb = to_srgb8(OKLCh(spec["L"], spec["C"], spec["h"]))
                x, y = x0 + c * CELL, y0 + r * CELL
                draw.rectangle([x, y, x + CELL - 2, y + CELL - 2], fill=rgb)
            # Number only — the name is what we're testing.
            draw.text((ox + 6, oy + 4), f"#{lv['index']}", fill=(190, 190, 195))
        name = f"blind-{chr(ord('a') + sheet_i // PER_SHEET)}.png"
        path = HERE / name
        img.save(path)
        out_paths.append((path, batch[0]["index"], batch[-1]["index"]))
    return out_paths


if __name__ == "__main__":
    for path, first, last in render():
        print(f"{path}  levels {first}-{last}")
