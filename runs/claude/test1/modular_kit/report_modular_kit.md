# modular_kit

- Preview: `runs/claude/test1/modular_kit/preview_modular_kit.png` (3/4, front, top, 3/4 back)
- Objects (12): `kit_wall_*`, `kit_floor_*`, `kit_ramp_*`, `kit_cone_*` for `wood`, `brick` and `metal`
- Triangles per piece: 724 to 2,128 (budget 2,500 each; the brick ramp is the heaviest); see `stats_modular_kit.json`
- Size: every piece fits a 4 x 4 m cell. Wall 4 x 4 x 0.25 m; floor 4 x 4 x 0.25 m; ramp rises 4 m over 4 m (low edge at -Y); pyramid roof 4 x 4 m base, 2 m tall
- Origins: bottom centre of the cell (walls: bottom centre of the wall), so pieces snap to a 4 m grid
- Self-correction loops: 2 (floors were offset from the cell centre by a wrong rotation sign; the ramp's low edge dipped below Z=0)

Weakest: the metal sheet's corrugation is too shallow to read at a distance, and the pyramid faces use plain course lines instead of planks, bricks or ribs.
