"""Ammo box: olive case with a hinged lid, carry handle, latches and rounds inside."""
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'common'))
import bpy, bmesh
from mathutils import Vector
import brlib as B

B.reset()
OLIVE = B.mat('mat_olive', '#7d7f32', rough=0.7)
OLIVE_L = B.mat('mat_olive_light', '#969a40', rough=0.7)
OLIVE_D = B.mat('mat_olive_dark', '#55581f', rough=0.75)
IRON = B.mat('mat_iron', '#4b4e53', rough=0.5, metal=0.6)
BRASS = B.mat('mat_brass', '#d9a22c', rough=0.4, metal=0.6)
COPPER = B.mat('mat_copper', '#b5653a', rough=0.4, metal=0.6)

W, D, HB, HL = 0.50, 0.25, 0.155, 0.095       # width X, depth Y, base height, lid height

# ---- base
base = B.tub('base_shell', (W - 0.02, D - 0.02, HB), 0.018, HB - 0.03, material=OLIVE, inner=OLIVE_D, bevel=0.012, seg=2)
parts = [base]
def rim(prefix, z):
    # four bars, so the opening stays clear
    out = []
    for s in (-1, 1):
        out.append(B.box(f'{prefix}_x{s}', (W, 0.03, 0.022), loc=(0, s * (D / 2 - 0.015), z), material=OLIVE_L, bevel=0.006, seg=1))
        out.append(B.box(f'{prefix}_y{s}', (0.03, D - 0.06, 0.022), loc=(s * (W / 2 - 0.015), 0, z), material=OLIVE_L, bevel=0.006, seg=1))
    return out
parts += rim('base_rim', HB - 0.02)
for sx in (-1, 1):
    for sy in (-1, 1):
        parts.append(B.box(f'foot{sx}{sy}', (0.09, 0.07, 0.03), loc=(sx * (W / 2 - 0.05), sy * (D / 2 - 0.04), 0.015), material=OLIVE_D, bevel=0.008, seg=1))
    parts.append(B.box(f'end_panel{sx}', (0.012, D * 0.55, HB * 0.5), loc=(sx * (W / 2 - 0.008), 0, HB * 0.5), material=OLIVE_L, bevel=0.004, seg=1))
    # bullet emblem on each end
    parts.append(B.cyl(f'emblem{sx}', 0.014, 0.07, loc=(sx * (W / 2 - 0.001), -0.008, HB * 0.5), material=OLIVE_D, rot=(math.radians(90), 0, 0), verts=8))
    parts.append(B.cyl(f'emblem_tip{sx}', 0.014, 0.03, loc=(sx * (W / 2 - 0.001), 0.042, HB * 0.5), material=OLIVE_D, rot=(math.radians(-90), 0, 0), verts=8, r2=0.003))
parts.append(B.box('front_panel', (W * 0.5, 0.012, HB * 0.45), loc=(0, -(D / 2 - 0.008), HB * 0.45), material=OLIVE_L, bevel=0.004, seg=1))
parts.append(B.box('back_panel', (W * 0.5, 0.012, HB * 0.45), loc=(0, (D / 2 - 0.008), HB * 0.45), material=OLIVE_L, bevel=0.004, seg=1))
for sx in (-1, 1):                              # latch plates and hinge leaves on the base
    parts.append(B.box(f'latch_plate{sx}', (0.06, 0.014, 0.05), loc=(sx * 0.15, -(D / 2 + 0.002), HB - 0.05), material=IRON, bevel=0.004, seg=1))
    parts.append(B.box(f'hinge_low{sx}', (0.065, 0.012, 0.045), loc=(sx * 0.15, D / 2 + 0.002, HB - 0.035), material=IRON, bevel=0.004, seg=1))
    parts.append(B.cyl(f'hinge_pin{sx}', 0.009, 0.075, loc=(sx * 0.15, D / 2 + 0.008, HB), material=IRON, rot=(0, math.radians(90), 0), verts=8))
base = B.join('ammo_box_base', parts)
base['keep_normals'] = True

# ---- rounds inside (two rows of four)
rounds = []
for i in range(4):
    for j, y in enumerate((-0.05, 0.05)):
        x = -0.165 + i * 0.11
        zc = 0.088 + (0.004 if (i + j) % 2 else 0)
        rounds.append(B.cyl(f'case{i}{j}', 0.021, 0.085, loc=(x - 0.012, y, zc), material=BRASS, rot=(0, math.radians(90), 0), verts=10))
        rounds.append(B.cyl(f'tip{i}{j}', 0.019, 0.04, loc=(x + 0.05, y, zc), material=COPPER, rot=(0, math.radians(90), 0), verts=10, r2=0.004))
        rounds.append(B.cyl(f'rimr{i}{j}', 0.023, 0.008, loc=(x - 0.056, y, zc), material=BRASS, rot=(0, math.radians(90), 0), verts=10))
rounds = B.join('ammo_box_rounds', rounds)

# ---- lid (separate, hinged at the back edge)
lid = [B.tub('lid_shell', (W - 0.02, D - 0.02, HL - 0.02), 0.018, HL - 0.045, loc=(0, 0, 0), material=OLIVE, inner=OLIVE_D)]
lid[0].rotation_euler = (math.radians(180), 0, 0)
lid[0].location = (0, 0, HB + HL - 0.02)
B.add_bevel(lid[0], 0.012, 2)
lid += rim('lid_rim', HB + 0.012)
lid.append(B.box('lid_top', (W * 0.78, D * 0.66, 0.018), loc=(0, 0, HB + HL - 0.014), material=OLIVE_L, bevel=0.006, seg=1))
for sx in (-1, 1):
    lid.append(B.box(f'latch{sx}', (0.05, 0.016, 0.07), loc=(sx * 0.15, -(D / 2 + 0.008), HB + 0.005), material=IRON, bevel=0.005, seg=1))
    lid.append(B.box(f'latch_top{sx}', (0.062, 0.02, 0.022), loc=(sx * 0.15, -(D / 2 + 0.006), HB + 0.04), material=IRON, bevel=0.005, seg=1))
    lid.append(B.box(f'hinge_up{sx}', (0.065, 0.012, 0.04), loc=(sx * 0.15, D / 2 + 0.002, HB + 0.03), material=IRON, bevel=0.004, seg=1))
    lid.append(B.box(f'handle_foot{sx}', (0.035, 0.045, 0.02), loc=(sx * 0.125, 0, HB + HL + 0.002), material=IRON, bevel=0.005, seg=1))
zt = HB + HL
path = [(-0.125, 0, zt), (-0.118, 0, zt + 0.035), (-0.09, 0, zt + 0.052), (0.09, 0, zt + 0.052), (0.118, 0, zt + 0.035), (0.125, 0, zt)]
lid.append(B.tube('handle_bar', path, 0.011, IRON, verts=8))
lid.append(B.cyl('handle_grip', 0.019, 0.15, loc=(0, 0, zt + 0.052), material=OLIVE, rot=(0, math.radians(90), 0), verts=10, bevel=0.004, seg=1))
lid = B.join('ammo_box_lid', lid)
lid['keep_normals'] = True
B.set_pivot(lid, (0, D / 2 + 0.008, HB))

OUT = os.environ.get('BR_OUT', HERE)
if os.environ.get('BR_OPEN'):                 # pose check only; the shipped files have the lid closed
    lid.rotation_euler.x = math.radians(-105)
B.finish('ammo_box', OUT, budget=5000)
