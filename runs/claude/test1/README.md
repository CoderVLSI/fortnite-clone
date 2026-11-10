# Stage 1: 3D assets

All 21 asset sets from the brief, built headless with Blender 5.1 (`bpy` 5.1.2) from Python only. No downloaded models, no image textures, no generators.

Each folder holds `build_<id>.py`, `<id>.blend`, `<id>.glb`, `preview_<id>.png`, `report_<id>.md` and `stats_<id>.json`. Re-running a build script rebuilds that asset from an empty scene and overwrites its outputs. The scripts share `../common/brlib.py` (mesh helpers, vertex-colour painting, export, preview render) and `../common/gunlib.py` (weapon helpers).

```bash
pip install bpy==5.1.2 pillow
```

```bash
python runs/claude/test1/grenade/build_grenade.py
```

Budgets for multi-object sets are the per-object budget times the number of objects; per-object counts are in each `stats_<id>.json`. Sizes are the bounding box of the whole file in metres (X x Y x Z); multi-object sets are laid out in a row or grid.

| Asset | Objects | Triangles | Budget | Size (m) |
| --- | --- | --- | --- | --- |
| `grenade` | 4 | 1,904 | 2,500 | 0.07 x 0.09 x 0.10 |
| `bushes` | 2 | 5,444 | 8,000 | 3.31 x 1.40 x 1.09 |
| `rocks` | 5 | 5,966 | 7,500 | 11.03 x 1.42 x 2.18 |
| `farm_props` | 3 | 2,476 | 6,000 | 4.42 x 0.85 x 1.10 |
| `ammo_box` | 3 | 2,928 | 5,000 | 0.53 x 0.28 x 0.32 |
| `medkit` | 3 | 1,988 | 4,000 | 0.56 x 0.35 x 0.16 |
| `shield_potion` | 4 | 1,392 | 4,000 | 0.25 x 0.25 x 0.25 |
| `chest` | 3 | 2,784 | 8,000 | 1.06 x 0.80 x 0.77 |
| `pistol` | 3 | 868 | 3,000 | 0.04 x 0.26 x 0.18 |
| `shotgun` | 4 | 1,320 | 6,000 | 0.09 x 0.95 x 0.25 |
| `assault_rifle` | 5 | 1,756 | 8,000 | 0.09 x 0.85 x 0.29 |
| `sniper_rifle` | 5 | 2,432 | 9,000 | 0.11 x 1.25 x 0.29 |
| `rocket_launcher` | 6 | 1,696 | 8,000 | 0.27 x 1.30 x 0.39 |
| `supply_drop` | 2 | 2,596 | 15,000 | 4.16 x 4.16 x 6.20 |
| `trees` | 3 | 4,836 | 18,000 | 16.06 x 4.90 x 9.01 |
| `modular_kit` | 12 | 12,654 | 30,000 | 20.82 x 17.15 x 4.24 |
| `lookout_tower` | 3 | 4,332 | 12,000 | 4.55 x 4.87 x 10.00 |
| `warehouse` | 6 | 5,332 | 20,000 | 16.12 x 11.40 x 7.81 |
| `house` | 10 | 8,600 | 30,000 | 9.37 x 10.18 x 9.68 |
| `pickaxe` | 2 | 860 | 4,000 | 0.15 x 0.64 x 1.00 |
| `drop_vehicle` | 10 | 4,228 | 30,000 | 8.12 x 10.08 x 12.36 |

Total: 76,392 triangles.

Colour is stored as vertex colours (`Col`): a flat base colour per material with a soft bottom-to-top gradient. Materials are Principled BSDF only.

Two deliberate deviations from the reference sheets are explained in the reports: the warehouse orientation (`warehouse`) and the drop vehicle design (`drop_vehicle`).
