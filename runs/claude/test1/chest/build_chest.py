"""Treasure chest: plank body, arched hinged lid, iron straps, gold rivets and padlock, glowing inside."""
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'common'))
import bpy, bmesh
from mathutils import Vector
import brlib as B

B.reset()
WOOD = B.mat('mat_wood', '#a4542a', rough=0.75)
WOOD_L = B.mat('mat_wood_light', '#bb6a33', rough=0.75)
WOOD_D = B.mat('mat_wood_dark', '#6e3519', rough=0.8)
IRON = B.mat('mat_iron', '#4a4b52', rough=0.5, metal=0.6)
GOLD = B.mat('mat_gold', '#e3a92b', rough=0.35, metal=0.6)
GLOW = B.mat('mat_glow', '#ffc23a', rough=0.5, emit=2.5)

W, D, HB = 1.0, 0.65, 0.42
RL = D / 2 + 0.005                         # lid arch radius, total height HB + RL = 0.75
SX = 0.33                                  # strap positions


def rivet(name, loc, axis, r=0.032):
    rot = {'x': (0, math.radians(90), 0), '-x': (0, math.radians(-90), 0), 'y': (math.radians(-90), 0, 0),
           '-y': (math.radians(90), 0, 0), 'z': (0, 0, 0)}[axis]
    return B.cyl(name, r, 0.03, loc=loc, material=GOLD, rot=rot, verts=8, r2=r * 0.45)

# ---- base: open box, three planks per side, iron straps and corner brackets
parts = [B.tub('base_shell', (W - 0.08, D - 0.08, HB), 0.04, HB - 0.06, material=WOOD_D, inner=WOOD_D)]
ph = (HB - 0.02) / 3
for i in range(3):
    z = 0.01 + ph * (i + 0.5)
    m = WOOD if i % 2 == 0 else WOOD_L
    for s in (-1, 1):
        parts.append(B.box(f'plank_y{s}{i}', (W - 0.05, 0.05, ph - 0.012), loc=(0, s * (D / 2 - 0.035), z), material=m, bevel=0.012, seg=1))
        parts.append(B.box(f'plank_x{s}{i}', (0.05, D - 0.1, ph - 0.012), loc=(s * (W / 2 - 0.035), 0, z), material=m, bevel=0.012, seg=1))
for s in (-1, 1):
    for t in (-1, 1):
        parts.append(B.box(f'strap{s}{t}', (0.1, 0.03, HB), loc=(s * SX, t * (D / 2 - 0.005), HB / 2), material=IRON, bevel=0.008, seg=1))
        parts.append(rivet(f'strap_rv{s}{t}', (s * SX, t * (D / 2 + 0.012), HB * 0.72), 'y' if t > 0 else '-y'))
        # chunky corner brackets
        parts.append(B.box(f'corner{s}{t}', (0.17, 0.17, 0.16), loc=(s * (W / 2 - 0.07), t * (D / 2 - 0.07), 0.08), material=IRON, bevel=0.02, seg=1))
        parts.append(rivet(f'corner_rv_y{s}{t}', (s * (W / 2 - 0.08), t * (D / 2 + 0.017), 0.08), 'y' if t > 0 else '-y', 0.036))
        parts.append(rivet(f'corner_rv_x{s}{t}', (s * (W / 2 + 0.017), t * (D / 2 - 0.08), 0.08), 'x' if s > 0 else '-x', 0.036))
        parts.append(B.box(f'corner_top{s}{t}', (0.12, 0.12, 0.05), loc=(s * (W / 2 - 0.05), t * (D / 2 - 0.05), HB - 0.025), material=IRON, bevel=0.012, seg=1))
    parts.append(B.box(f'hinge_low{s}', (0.13, 0.03, 0.1), loc=(s * SX, D / 2 + 0.02, HB - 0.07), material=IRON, bevel=0.01, seg=1))
    parts.append(B.cyl(f'hinge_barrel{s}', 0.032, 0.15, loc=(s * SX, D / 2 + 0.035, HB), material=IRON, rot=(0, math.radians(90), 0), verts=10, bevel=0.006, seg=1))
parts.append(B.box('lock_plate', (0.09, 0.03, 0.11), loc=(0, -(D / 2 + 0.01), HB - 0.11), material=GOLD, bevel=0.012, seg=1))
base = B.join('chest_base', parts)
base['keep_normals'] = True

glow = B.box('chest_glow', (W - 0.17, D - 0.17, 0.02), loc=(0, 0, HB - 0.1), material=GLOW)
coins = [B.cyl(f'coin{i}', 0.05, 0.016, loc=(x, y, HB - 0.08 + 0.01 * (i % 3)), material=GOLD, rot=(0.3 * ((i % 3) - 1), 0.25 * ((i % 2) - 0.5), 0), verts=10)
         for i, (x, y) in enumerate([(-0.3, -0.1), (-0.15, 0.1), (0.0, -0.05), (0.18, 0.12), (0.3, -0.08), (-0.05, 0.15), (0.12, -0.14), (-0.28, 0.14)])]
glow = B.join('chest_glow', [glow] + coins)

# ---- lid: hollow half-barrel of planks, hinged along the back top edge
N = 8
def arc(r, n=N):
    return [(r * math.cos(math.pi * i / n), r * math.sin(math.pi * i / n)) for i in range(n + 1)]
outer = arc(RL - 0.012)
inner = list(reversed(arc(RL - 0.07)))
lid = [B.prism('lid_planks', outer + inner, W - 0.05, loc=(0, 0, HB), material=WOOD, axis='X')]
lid[0]['flat'] = True
# end walls
ends = arc(RL - 0.03)
for s in (-1, 1):
    lid.append(B.prism(f'lid_end{s}', ends, 0.05, loc=(s * (W / 2 - 0.035), 0, HB), material=WOOD_L, axis='X'))
    # iron straps over the arch
    lid.append(B.prism(f'lid_strap{s}', arc(RL + 0.004) + list(reversed(arc(RL - 0.03))), 0.1, loc=(s * SX, 0, HB), material=IRON, axis='X'))
    for a in (25, 90, 155):
        ar = math.radians(a)
        o = B.cyl(f'lid_rv{s}{a}', 0.032, 0.03, loc=(s * SX, RL * math.cos(ar), HB + RL * math.sin(ar) + 0.006), material=GOLD,
                  rot=(-(math.pi / 2 - ar), 0, 0), verts=8, r2=0.014)
        lid.append(o)
    lid.append(B.box(f'hinge_up{s}', (0.13, 0.03, 0.09), loc=(s * SX, D / 2 + 0.02, HB + 0.06), material=IRON, bevel=0.01, seg=1))
# padlock hangs from the lid's front edge
lz = HB - 0.02
lid.append(B.box('lock_body', (0.17, 0.06, 0.15), loc=(0, -(D / 2 + 0.045), lz - 0.05), material=GOLD, bevel=0.02, seg=1))
lid.append(B.cyl('lock_keyhole', 0.02, 0.012, loc=(0, -(D / 2 + 0.076), lz - 0.035), material=WOOD_D, rot=(math.radians(90), 0, 0), verts=8))
lid.append(B.box('lock_keyslot', (0.016, 0.012, 0.045), loc=(0, -(D / 2 + 0.076), lz - 0.065), material=WOOD_D))
lid.append(B.tube('lock_shackle', [(-0.045, -(D / 2 + 0.045), lz + 0.02), (-0.045, -(D / 2 + 0.045), lz + 0.08), (-0.025, -(D / 2 + 0.045), lz + 0.11),
                                   (0.025, -(D / 2 + 0.045), lz + 0.11), (0.045, -(D / 2 + 0.045), lz + 0.08), (0.045, -(D / 2 + 0.045), lz + 0.02)], 0.017, GOLD, verts=8))
lid = B.join('chest_lid', lid)
lid['smooth_angle'] = 15
B.set_pivot(lid, (0, D / 2 + 0.035, HB))

OUT = os.environ.get('BR_OUT', HERE)
if os.environ.get('BR_OPEN'):
    lid.rotation_euler.x = math.radians(-70)
B.finish('chest', OUT, budget=8000)
