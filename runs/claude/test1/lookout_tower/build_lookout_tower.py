"""Lookout tower: four splayed legs with cross braces, railed platform at 7 m, ladder, tiled pyramid roof. 10 m tall."""
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'common'))
import bpy, bmesh
from mathutils import Vector
import brlib as B

B.reset()
WOOD = B.mat('mat_wood', '#c88a2e', rough=0.75)
WOOD_L = B.mat('mat_wood_light', '#dba23c', rough=0.75)
WOOD_D = B.mat('mat_wood_dark', '#a56d22', rough=0.8)
ROOF = B.mat('mat_roof', '#d2502a', rough=0.8)
ROOF_D = B.mat('mat_roof_dark', '#b03f20', rough=0.8)
IRON = B.mat('mat_iron', '#4d4f55', rough=0.5, metal=0.6)

HB, HP = 2.0, 1.5                          # half-spread at the base and at the platform
ZP = 7.0                                   # platform height


def leg_at(z):                              # half-spread of the legs at height z
    return HB + (HP - HB) * min(z / ZP, 1.0)

parts = []
for a in (-1, 1):
    for b in (-1, 1):
        parts.append(B.beam(f'leg{a}{b}', (a * HB, b * HB, 0.25), (a * HP, b * HP, ZP), 0.34, material=WOOD, bevel=0.035))
        parts.append(B.box(f'foot{a}{b}', (0.55, 0.55, 0.42), loc=(a * HB, b * HB, 0.21), material=WOOD_L, bevel=0.06, seg=1))
        parts.append(B.box(f'post{a}{b}', (0.3, 0.3, 1.55), loc=(a * HP, b * HP, ZP + 0.775), material=WOOD, bevel=0.03, seg=1))
        for z in (3.3, 6.75):
            s = leg_at(z)
            parts.append(B.box(f'collar{a}{b}{z}', (0.46, 0.46, 0.4), loc=(a * s, b * s, z), material=WOOD_L, bevel=0.05, seg=1))
            parts.append(B.cyl(f'bolt_y{a}{b}{z}', 0.06, 0.04, loc=(a * s, b * (s + 0.24), z), material=IRON, rot=(math.radians(-90 * b), 0, 0), verts=8, r2=0.035))
            parts.append(B.cyl(f'bolt_x{a}{b}{z}', 0.06, 0.04, loc=(a * (s + 0.24), b * s, z), material=IRON, rot=(0, math.radians(90 * a), 0), verts=8, r2=0.035))
# ring beams and cross braces on all four sides, two levels
for side in range(4):
    def P(u, z, off=0.0):                   # point on this side: u in [-1, 1] across, at height z
        s = leg_at(z) + off
        return [(u * s, -s, z), (s, u * s, z), (-u * s, s, z), (-s, -u * s, z)][side]
    for z in (3.3, 6.75):
        parts.append(B.beam(f'ring{side}{z}', P(-1, z), P(1, z), 0.24, 0.2, material=WOOD_L, bevel=0.025))
    for z0, z1 in ((0.5, 3.2), (3.4, 6.65)):
        parts.append(B.beam(f'brace_a{side}{z0}', P(-0.93, z0, -0.06), P(0.93, z1, -0.06), 0.2, 0.12, material=WOOD_D, bevel=0.02))
        parts.append(B.beam(f'brace_b{side}{z0}', P(0.93, z0, -0.14), P(-0.93, z1, -0.14), 0.2, 0.12, material=WOOD_D, bevel=0.02))
    # railing: top rail, mid rail and balusters (the front side keeps a gap for the ladder)
    zr = ZP + 0.95
    if side == 0:
        spans = [(-1, -0.32), (0.32, 1)]
    else:
        spans = [(-1, 1)]
    for k, (u0, u1) in enumerate(spans):
        parts.append(B.beam(f'rail_top{side}{k}', P(u0, zr, 0.02), P(u1, zr, 0.02), 0.2, 0.14, material=WOOD_L, bevel=0.02))
        parts.append(B.beam(f'rail_mid{side}{k}', P(u0, zr - 0.45, 0.02), P(u1, zr - 0.45, 0.02), 0.14, 0.1, material=WOOD, bevel=0.015))
        n = max(2, round((u1 - u0) * 2.5))
        for i in range(1, n):
            u = u0 + (u1 - u0) * i / n
            parts.append(B.beam(f'bal{side}{k}{i}', P(u, ZP + 0.1, 0.02), P(u, zr, 0.02), 0.1, 0.08, material=WOOD))
# platform deck: planks on a frame
for i in range(7):
    y = -HP - 0.15 + (2 * HP + 0.3) * (i + 0.5) / 7
    parts.append(B.box(f'deck{i}', (2 * HP + 0.5, (2 * HP + 0.3) / 7 - 0.03, 0.14), loc=(0, y, ZP + 0.02), material=WOOD_L if i % 2 else WOOD, bevel=0.02, seg=1))
# roof beams under the eaves
for s in (-1, 1):
    parts.append(B.box(f'eave_x{s}', (2 * HP + 0.5, 0.22, 0.22), loc=(0, s * HP, ZP + 1.58), material=WOOD_L, bevel=0.025, seg=1))
    parts.append(B.box(f'eave_y{s}', (0.22, 2 * HP + 0.5, 0.22), loc=(s * HP, 0, ZP + 1.58), material=WOOD_L, bevel=0.025, seg=1))
frame = B.join('tower_frame', parts)
frame['smooth_angle'] = 30

# ladder on the front, leaning from the ground to the platform edge
lad = []
y0, y1 = -HB - 0.55, -HP - 0.22
for s in (-1, 1):
    lad.append(B.beam(f'ladder_rail{s}', (s * 0.36, y0, 0.0), (s * 0.36, y1, ZP + 1.0), 0.14, 0.1, material=WOOD, bevel=0.015))
for i in range(14):
    t = (i + 0.7) / 14.6
    z = t * ZP
    y = y0 + (y1 - y0) * (z / (ZP + 1.0))
    lad.append(B.box(f'rung{i}', (0.72, 0.09, 0.09), loc=(0, y, z), material=WOOD_L, bevel=0.012, seg=1))
ladder = B.join('tower_ladder', lad)

# roof: three stepped tile courses and a cap, tip at 10 m
roof = []
levels = [(2.25, ZP + 2.0, 1.72, ZP + 2.55), (1.78, ZP + 2.5, 1.02, ZP + 2.9), (1.08, ZP + 2.85, 0.14, ZP + 2.86 + 0.0)]
levels[2] = (1.08, ZP + 2.85, 0.16, ZP + 2.84)
zt = [ZP + 1.62, ZP + 2.15, ZP + 2.55, ZP + 2.8]
half = [2.25, 1.62, 0.92, 0.16]
for i in range(3):
    bm = bmesh.new()
    lo = [bm.verts.new((x * half[i], y * half[i], zt[i])) for x, y in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    hi = [bm.verts.new((x * (half[i + 1] - 0.08), y * (half[i + 1] - 0.08), zt[i + 1] + 0.06)) for x, y in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    lo2 = [bm.verts.new((x * half[i], y * half[i], zt[i] - 0.09)) for x, y in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    for k in range(4):
        j = (k + 1) % 4
        bm.faces.new((lo[k], lo[j], hi[j], hi[k]))
        bm.faces.new((lo2[k], lo2[j], lo[j], lo[k]))
    bm.faces.new(hi)
    bm.faces.new(list(reversed(lo2)))
    roof.append(B.obj_from_bm(f'roof_course{i}', bm, ROOF if i % 2 == 0 else ROOF_D))
for k in range(4):                           # hip ridges
    a, b = ((-1, -1), (1, -1), (1, 1), (-1, 1))[k]
    roof.append(B.beam(f'roof_hip{k}', (a * 2.2, b * 2.2, ZP + 1.64), (a * 0.14, b * 0.14, ZP + 2.84), 0.16, 0.1, material=ROOF_D))
roof.append(B.box('roof_cap', (0.3, 0.3, 0.22), loc=(0, 0, 9.89), material=WOOD_L, bevel=0.04, seg=1))
roof = B.join('tower_roof', roof)
roof['smooth_angle'] = 25

for o in (frame, ladder, roof):
    B.set_pivot(o, (0, 0, 0))
B.finish('lookout_tower', HERE, budget=12000, aspect=0.6, res=900)
