"""Generates data/definitions/map_large.json and map_large_objects.json.

    python tools/generate_large_map.py

80 x 48 cells (4000 x 2400 world units). The left half is designed by hand
below and mirrored onto the right half, so both players get the same terrain.
A river splits the map with four fords; there are lakes, forests and hills.
Edit the shapes and run it again to change the map.
"""
import json
import os

COLS, ROWS, CELL = 80, 48, 50
HALF = COLS // 2
OUT = os.path.join(os.path.dirname(__file__), "..", "data", "definitions")

grid = [["P"] * COLS for _ in range(ROWS)]


def rect(col, row, w, h, code):
    for r in range(row, row + h):
        for c in range(col, col + w):
            if 0 <= r < ROWS and 0 <= c < HALF:
                grid[r][c] = code


def blob(col, row, radius, code):
    for r in range(ROWS):
        for c in range(HALF):
            if ((c - col) / radius) ** 2 + ((r - row) / (radius * 0.8)) ** 2 <= 1.0:
                grid[r][c] = code


# --- Left half (the right half is its mirror) -------------------------------
# Forests
rect(10, 3, 6, 5, "F")
rect(26, 10, 5, 7, "F")
rect(12, 30, 7, 6, "F")
rect(27, 33, 5, 6, "F")
rect(3, 40, 6, 4, "F")
# Hills
rect(18, 19, 4, 4, "H")
rect(33, 21, 3, 6, "H")
rect(6, 9, 3, 3, "H")
rect(20, 40, 4, 3, "H")
# Lakes
blob(20, 11, 3.2, "W")
blob(23, 31, 2.6, "W")
# The river (columns 39 and 40 after mirroring) with four fords.
for r in range(ROWS):
    grid[r][39] = "W"
for ford in (6, 18, 29, 41):
    grid[ford][39] = "P"
    grid[ford + 1][39] = "P"

# Keep the deployment area around the spawn clear.
SPAWN = (8, 24)
rect(SPAWN[0] - 5, SPAWN[1] - 7, 13, 15, "P")

for r in range(ROWS):
    for c in range(HALF):
        grid[r][COLS - 1 - c] = grid[r][c]

tiles = ["".join(row) for row in grid]
spawns = [
    {"x": (SPAWN[0] + 0.5) * CELL, "y": (SPAWN[1] + 0.5) * CELL},
    {"x": (COLS - 1 - SPAWN[0] + 0.5) * CELL, "y": (SPAWN[1] + 0.5) * CELL},
]


def mirror_cell(col, size=1):
    return COLS - col - size


def passable(col, row, w=1, h=1):
    return all(tiles[r][c] != "W" for r in range(row, row + h) for c in range(col, col + w))


buildings = []
for b in [("barracks", 3, 14, 2), ("storehouse", 4, 34, 1), ("barracks", 13, 22, 2)]:
    btype, col, row, size = b
    assert passable(col, row, size, size), b
    buildings.append({"type": btype, "side": 0, "cell": {"x": col, "y": row}})
    buildings.append({"type": btype, "side": 1, "cell": {"x": mirror_cell(col, size), "y": row}})

resources = []
for r in [("FOOD", 15, 26, 1500), ("FOOD", 6, 18, 1000), ("WOOD", 17, 5, 900), ("WOOD", 19, 33, 900),
          ("STONE", 22, 20, 700), ("STONE", 32, 25, 700), ("GOLD", 36, 7, 2000), ("GOLD", 36, 42, 2000)]:
    rtype, col, row, amount = r
    assert passable(col, row), r
    resources.append({"type": rtype, "cell": {"x": col, "y": row}, "amount": amount})
    resources.append({"type": rtype, "cell": {"x": mirror_cell(col), "y": row}, "amount": amount})

with open(os.path.join(OUT, "map_large.json"), "w", encoding="utf-8") as f:
    json.dump({
        "_comment": "Generado por tools/generate_large_map.py (no editar a mano). 80x48 casillas, simetrico.",
        "cell_size": CELL, "tiles": tiles, "spawns": spawns,
    }, f, indent=2)

with open(os.path.join(OUT, "map_large_objects.json"), "w", encoding="utf-8") as f:
    json.dump({
        "_comment": "Generado por tools/generate_large_map.py. Edificios y recursos del mapa grande (solo cliente).",
        "cols": COLS, "rows": ROWS, "base_building": "anthill",
        "buildings": buildings, "resources": resources,
    }, f, indent=2)

print("map_large.json: %dx%d, %d agua, %d bosque, %d colina" % (
    COLS, ROWS, sum(t.count("W") for t in tiles), sum(t.count("F") for t in tiles), sum(t.count("H") for t in tiles)))
for t in tiles:
    print(t)
