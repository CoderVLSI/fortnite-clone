# house

- Preview: `runs/claude/test1/house/preview_house.png` (front, side, 3/4, back)
- Triangles: 8,600 (budget 30,000)
- Size: footprint 8 x 7 m (9.4 x 10.2 m with roof overhang, porch steps and chimney), two floors of 3 m, ridge at 9.3 m, chimney top 9.6 m
- Objects: `house_shell` (hollow walls, ground slab, upper floor with stair well), `house_trim`, `house_windows`, `house_roof`, `house_porch`, `house_door_frame`, `house_door` (separate, pivot on its hinge edge), `house_stairs`, `house_chimney`, `house_furniture`
- Interior: walkable ground floor, 15-step staircase along the east wall, upper floor, table, stool and bed
- Self-correction loops: 1 (the chimney covered the back windows; moved them). The interior was checked in a separate cutaway render.

Weakest: the roof tiles are five broad courses per side rather than individual tiles, and the windows are solid panes, so they cannot be shot or looked through.
