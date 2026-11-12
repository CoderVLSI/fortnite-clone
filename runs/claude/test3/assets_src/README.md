# Extra weapon assets (built after stage 1)

The four guns added in the game's weapon expansion, built the same way as the stage 1 assets: headless Blender
(`bpy` 5.1.2) from Python only, with the shared helpers in `runs/claude/common/` (`brlib.py`, `gunlib.py`).
Same conventions as the stage 1 guns: barrel along -Y, origin at the grip, separate magazine/trigger objects.

| Asset | Look | Triangles | Size (m) |
|---|---|---|---|
| `smg` | slate receiver, suppressor, long straight magazine, wire stock, cyan red-dot | 1,360 | 0.57 long |
| `tactical_shotgun` | vented heat shield, slate and black body, side saddle with red shells | 1,640 | 0.89 long |
| `burst_rifle` | light grey body, olive furniture, carry-handle optic with a blue lens | 1,584 | 0.82 long |
| `hunting_rifle` | walnut stock, long barrel, iron sights (no scope), spare brass rounds | 1,424 | 1.14 long |

Build one: `python runs/claude/test3/assets_src/smg/build_smg.py` (writes the .blend, .glb, preview and stats next to it).
The .glb files are copied into `runs/claude/test3/game/assets/`.

## Upgrade bench

`upgrade_bench/` - the workbench in every town where weapons are upgraded with gold: plank top with metal corner caps,
a vise, an anvil, a pegboard with tools, a tray of gold bars, a glowing gold strip along the front and an arrow sign.
1,380 triangles, 1.8 m wide. Origin on the floor at the middle, working side facing -Y (+Z in Godot).
