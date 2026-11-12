"""Upgrade bench: a sturdy workbench where weapons are upgraded with gold. Plank top with metal corner caps, a vise,
a small anvil, a pegboard with tools, a tray of gold bars and a glowing gold strip along the front. Z up, origin on the
floor at the middle of the bench, the working side facing -Y."""
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', '..', 'common'))
import bpy
import brlib as B

B.reset()
WOOD = B.mat('mat_bench_wood', '#8c5a32', rough=0.8)
WOOD_D = B.mat('mat_bench_wood_dark', '#6b4224', rough=0.85)
STEEL = B.mat('mat_steel', '#6d7380', rough=0.45, metal=0.6)
STEEL_D = B.mat('mat_steel_dark', '#3c4049', rough=0.5, metal=0.6)
GOLD = B.mat('mat_gold', '#f2b632', rough=0.25, metal=0.8)
GLOW = B.mat('mat_gold_glow', '#ffc34a', rough=0.3, emit=2.5)
BOARD = B.mat('mat_pegboard', '#c9a77a', rough=0.9)
RED = B.mat('mat_handle_red', '#c23a2c', rough=0.6)

W, D, H = 1.8, 0.8, 0.95                       # top size and height
parts = []
# the top: five planks with gaps, and a frame under it
for i in range(5):
    y = -D / 2 + D * (i + 0.5) / 5
    parts.append(B.box(f'plank{i}', (W, D / 5 - 0.012, 0.07), loc=(0, y, H - 0.035), material=WOOD if i % 2 else WOOD_D, bevel=0.006, seg=1))
parts.append(B.box('apron_f', (W - 0.1, 0.05, 0.12), loc=(0, -D / 2 + 0.06, H - 0.13), material=WOOD_D, bevel=0.005, seg=1))
parts.append(B.box('apron_b', (W - 0.1, 0.05, 0.12), loc=(0, D / 2 - 0.06, H - 0.13), material=WOOD_D, bevel=0.005, seg=1))
for sx in (-1, 1):
    for sy in (-1, 1):
        parts.append(B.box(f'leg{sx}{sy}', (0.1, 0.1, H - 0.07), loc=(sx * (W / 2 - 0.09), sy * (D / 2 - 0.09), (H - 0.07) / 2), material=WOOD_D, bevel=0.008, seg=1))
        parts.append(B.box(f'cap{sx}{sy}', (0.09, 0.09, 0.025), loc=(sx * (W / 2 - 0.045), sy * (D / 2 - 0.045), H + 0.0125), material=STEEL, bevel=0.004, seg=1))
parts.append(B.box('shelf', (W - 0.22, D - 0.22, 0.05), loc=(0, 0, 0.28), material=WOOD, bevel=0.005, seg=1))
wood = B.join('bench_wood', parts)

# the glowing strip along the front edge, and gold bars on a little tray
glow = B.box('bench_glow', (W - 0.2, 0.02, 0.035), loc=(0, -D / 2 - 0.002, H - 0.1), material=GLOW)
gold = [B.box('tray', (0.42, 0.26, 0.03), loc=(-0.45, -0.05, H + 0.015), material=STEEL_D, bevel=0.005, seg=1)]
for i, (x, y, z, rz) in enumerate([(-0.53, -0.08, 0.06, 0.0), (-0.37, -0.08, 0.06, 0.0), (-0.45, -0.02, 0.115, math.pi / 2)]):
    gold.append(B.prism(f'bar{i}', [(-0.075, 0.0), (0.075, 0.0), (0.055, 0.045), (-0.055, 0.045)], 0.07, loc=(x, y, H + z - 0.035), material=GOLD, rot=(0, 0, rz), axis='Y'))
gold = B.join('bench_gold', gold)

# metal: the vise on the right, an anvil in the middle, the pegboard's tools
metal = [B.box('vise_body', (0.22, 0.2, 0.14), loc=(0.62, -0.18, H + 0.07), material=STEEL, bevel=0.01, seg=1),
         B.box('vise_jaw', (0.22, 0.05, 0.12), loc=(0.62, -0.32, H + 0.08), material=STEEL_D, bevel=0.006, seg=1),
         B.cyl('vise_screw', 0.015, 0.22, loc=(0.62, -0.42, H + 0.07), material=STEEL_D, rot=(math.pi / 2, 0, 0), verts=8),
         B.cyl('vise_handle', 0.012, 0.22, loc=(0.62, -0.53, H + 0.07), material=RED, rot=(0, math.pi / 2, 0), verts=8),
         B.box('anvil_base', (0.14, 0.12, 0.09), loc=(0.12, -0.05, H + 0.045), material=STEEL_D, bevel=0.01, seg=1),
         B.box('anvil_top', (0.3, 0.14, 0.06), loc=(0.14, -0.05, H + 0.12), material=STEEL, bevel=0.012, seg=1),
         B.cyl('anvil_horn', 0.05, 0.14, loc=(-0.07, -0.05, H + 0.125), material=STEEL, rot=(0, math.pi / 2, 0), verts=10, r2=0.006)]
# pegboard at the back with a hammer, a wrench and a saw outline
board = [B.box('pegboard', (1.2, 0.03, 0.62), loc=(0.05, D / 2 - 0.03, H + 0.36), material=BOARD, bevel=0.005, seg=1)]
for i in range(2):
    board.append(B.box(f'post{i}', (0.05, 0.05, 0.7), loc=(-0.57 + i * 1.24, D / 2 - 0.03, H + 0.33), material=WOOD_D, bevel=0.005, seg=1))
metal += [B.box('hammer_handle', (0.03, 0.02, 0.3), loc=(-0.3, D / 2 - 0.06, H + 0.36), material=WOOD_D),
          B.box('hammer_head', (0.12, 0.04, 0.05), loc=(-0.3, D / 2 - 0.06, H + 0.52), material=STEEL_D, bevel=0.004, seg=1),
          B.box('wrench', (0.03, 0.015, 0.28), loc=(0.05, D / 2 - 0.055, H + 0.38), material=STEEL, rot=(0, 0.3, 0)),
          B.box('saw_blade', (0.28, 0.01, 0.1), loc=(0.42, D / 2 - 0.055, H + 0.42), material=STEEL),
          B.box('saw_grip', (0.08, 0.025, 0.1), loc=(0.6, D / 2 - 0.06, H + 0.42), material=RED, bevel=0.005, seg=1)]
metal = B.join('bench_metal', metal)
board = B.join('bench_board', board)
# a sign above the board: an up arrow
sign = [B.box('sign', (0.36, 0.03, 0.22), loc=(0.05, D / 2 - 0.02, H + 0.8), material=STEEL_D, bevel=0.006, seg=1),
        B.prism('sign_arrow', [(-0.08, -0.07), (0.08, -0.07), (0.08, 0.0), (0.0, 0.08), (-0.08, 0.0)], 0.012, loc=(0.05, D / 2 - 0.04, H + 0.8), material=GLOW, axis='Y')]
sign = B.join('bench_sign', sign)
for o in (wood, glow, gold, metal, board, sign):
    B.set_pivot(o, (0, 0, 0))
B.finish('upgrade_bench', HERE, budget=6000, ground=True)
