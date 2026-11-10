"""Supply drop: armoured olive crate with glowing strips under a striped parachute."""
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'common'))
import bpy, bmesh
from mathutils import Vector
import brlib as B

B.reset()
OLIVE = B.mat('mat_olive', '#6b7340', rough=0.7)
OLIVE_L = B.mat('mat_olive_light', '#7f8850', rough=0.7)
IRON = B.mat('mat_iron', '#4a4c52', rough=0.5, metal=0.5)
RIVET = B.mat('mat_rivet', '#8a7d6a', rough=0.45, metal=0.6)
BLUE = B.mat('mat_glow_blue', '#3fb4ff', rough=0.4, emit=3.0)
ORANGE = B.mat('mat_canopy_orange', '#e2622a', rough=0.85)
CREAM = B.mat('mat_canopy_cream', '#e6d4b0', rough=0.85)
ROPE = B.mat('mat_rope', '#b99262', rough=0.9)
for m in (ORANGE, CREAM):
    m.use_backface_culling = False

S = 1.2
h = S / 2

# ---- crate
parts = [B.box('core', (S - 0.1, S - 0.1, S - 0.1), loc=(0, 0, h), material=OLIVE, bevel=0.02, seg=1)]
AX = {'x': 0, 'y': 1}
for axis, sgn in (('x', 1), ('x', -1), ('y', 1), ('y', -1)):
    def place(u, z, su, sz, depth, material, name, bevel=0.012):
        size = (depth, su, sz) if axis == 'x' else (su, depth, sz)
        loc = (sgn * (h - 0.05 + depth / 2), u, z) if axis == 'x' else (u, sgn * (h - 0.05 + depth / 2), z)
        return B.box(f'{name}_{axis}{sgn}', size, loc=loc, material=material, bevel=bevel, seg=1)
    parts.append(place(0, h - 0.06, 0.62, 0.6, 0.03, OLIVE_L, 'panel', 0.03))
    parts.append(place(0, S - 0.2, 0.5, 0.035, 0.012, BLUE, 'strip_top', 0.0))
parts.append(B.box('lid_plate', (0.7, 0.7, 0.03), loc=(0, 0, S - 0.04), material=OLIVE_L, bevel=0.02, seg=1))
parts.append(B.box('handle', (0.28, 0.04, 0.05), loc=(0.1, -(h - 0.02), h - 0.05), material=IRON, bevel=0.01, seg=1))
crate = B.join('supply_crate', parts)

frame = []
strips = []
for a in (-1, 1):
    for b in (-1, 1):
        x, y = a * (h - 0.11), b * (h - 0.11)
        frame.append(B.box(f'pillar{a}{b}', (0.2, 0.2, S - 0.3), loc=(x, y, h), material=IRON, bevel=0.03, seg=1))
        for c in (-1, 1):
            z = h + c * (h - 0.15)
            frame.append(B.box(f'corner{a}{b}{c}', (0.3, 0.3, 0.3), loc=(a * (h - 0.15), b * (h - 0.15), z), material=IRON, bevel=0.055, seg=1))
            frame.append(B.cyl(f'rv_x{a}{b}{c}', 0.04, 0.03, loc=(a * (h + 0.005), b * (h - 0.15), z), material=RIVET, rot=(0, math.radians(90), 0), verts=8))
            frame.append(B.cyl(f'rv_y{a}{b}{c}', 0.04, 0.03, loc=(a * (h - 0.15), b * (h + 0.005), z), material=RIVET, rot=(math.radians(90), 0, 0), verts=8))
        strips.append(B.box(f'gx{a}{b}', (0.012, 0.03, 0.42), loc=(a * (h - 0.006), b * (h - 0.17), h), material=BLUE))
        strips.append(B.box(f'gy{a}{b}', (0.03, 0.012, 0.42), loc=(a * (h - 0.17), b * (h - 0.006), h), material=BLUE))
        # lifting ring on each top corner
        frame.append(B.torus(f'ring{a}{b}', 0.055, 0.016, loc=(a * (h - 0.15), b * (h - 0.15), S + 0.05), material=IRON,
                             rot=(math.radians(90), 0, math.radians(45 * a * b)), major=10, minor=6))
frame = B.join('supply_frame', frame + strips)
crate = B.join('supply_crate', [crate, frame])

# ---- parachute: 12 puffed gores, alternating colours; rim 3.5 m above the crate top, top 5 m above it
GORES, SUB, RINGS = 12, 4, 7
RC, HC = 2.0, 1.5
ZR = S + 3.5
bm = bmesh.new()
grid = []
for j in range(RINGS + 1):
    t = j / RINGS                                 # 0 at the rim, 1 at the crown
    ring = []
    for i in range(GORES * SUB):
        u = (i % SUB) / SUB
        puff = 1 + 0.07 * math.sin(math.pi * u) * (1 - t) ** 0.5
        a = 2 * math.pi * i / (GORES * SUB)
        r = RC * math.cos(t * math.pi / 2) * puff
        z = ZR + HC * math.sin(t * math.pi / 2) + (0.16 * math.sin(math.pi * u) if j == 0 else 0)
        ring.append(bm.verts.new((r * math.cos(a), r * math.sin(a), z)) if j < RINGS else None)
    grid.append(ring)
crown = bm.verts.new((0, 0, ZR + HC))
n = GORES * SUB
for j in range(RINGS):
    for i in range(n):
        k = (i + 1) % n
        if j < RINGS - 1:
            f = bm.faces.new((grid[j][i], grid[j][k], grid[j + 1][k], grid[j + 1][i]))
        else:
            f = bm.faces.new((grid[j][i], grid[j][k], crown))
        f.material_index = (i // SUB) % 2
canopy = B.obj_from_bm('canopy', bm, ORANGE)
canopy.data.materials.append(CREAM)
canopy['keep_normals'] = True
ropes = []
for g in range(GORES):
    a = 2 * math.pi * g / GORES
    top = Vector((RC * math.cos(a), RC * math.sin(a), ZR))
    cx = (h - 0.15) * (1 if math.cos(a) >= 0 else -1)
    cy = (h - 0.15) * (1 if math.sin(a) >= 0 else -1)
    ropes.append(B.tube(f'rope{g}', [top, Vector((cx, cy, S + 0.09))], 0.018, ROPE, verts=4))
chute = B.join('supply_parachute', [canopy] + ropes)
chute['keep_normals'] = True
chute['smooth_angle'] = 50
B.set_pivot(chute, (0, 0, S))
B.set_pivot(crate, (0, 0, 0))
B.finish('supply_drop', HERE, budget=15000, aspect=0.75, res=760)
