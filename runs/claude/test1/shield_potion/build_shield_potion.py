"""Shield potion: round glass flask of glowing blue liquid, cork, and a dark belt with a buckle."""
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'common'))
import bpy, bmesh
from mathutils import Vector
import brlib as B

B.reset()
GLASS = B.mat('mat_glass', '#bfe3ff', rough=0.15, alpha=0.28)
LIQUID = B.mat('mat_liquid', '#1f7dff', rough=0.3, emit=0.9)
LIQUID_T = B.mat('mat_liquid_top', '#5fb0ff', rough=0.3, emit=0.9)
CORK = B.mat('mat_cork', '#b98350', rough=0.9)
BELT = B.mat('mat_belt', '#46484c', rough=0.6, metal=0.3)
STUD = B.mat('mat_stud', '#63666b', rough=0.45, metal=0.6)

R, CZ = 0.105, 0.102                      # body radius and centre height

# ---- glass: sphere with a flat base, neck and lip, as one lathed profile
prof = [(0.045, 0.0)]
for i in range(1, 12):
    a = math.radians(-64 + i * (64 + 68) / 11)
    prof.append((R * math.cos(a), CZ + R * math.sin(a)))
prof += [(0.040, 0.205), (0.046, 0.211), (0.046, 0.222), (0.036, 0.222)]
glass = B.lathe('potion_glass', prof, GLASS, seg=20, cap_top=False, cap_bottom=True)
glass['smooth_angle'] = 50
glass['grad_lo'] = 0.95

# ---- liquid: inner sphere cut flat at the fill line
bm = bmesh.new()
bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=10, radius=R - 0.007)
for v in bm.verts:
    v.co.z = max(v.co.z, -(CZ - 0.006))
geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, 0.035), plane_no=(0, 0, 1), clear_outer=True)
bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if len(e.link_faces) == 1])
for f in bm.faces:
    if f.normal.z > 0.9 and f.calc_center_median().z > 0.03:
        f.material_index = 1
liquid = B.obj_from_bm('potion_liquid', bm, LIQUID, loc=(0, 0, CZ))
liquid.data.materials.append(LIQUID_T)
liquid['grad_lo'] = 0.75
bub = [B.sphere(f'bubble{i}', r, loc=p, material=LIQUID_T, seg=6, rings=4) for i, (p, r) in enumerate(
    [((0.03, -0.07, 0.07), 0.009), ((-0.035, -0.075, 0.11), 0.011), ((0.01, 0.07, 0.06), 0.008), ((-0.05, 0.05, 0.10), 0.007)])]
liquid = B.join('potion_liquid', [liquid] + bub)

# ---- cork
cork = B.cyl('potion_cork', 0.036, 0.055, loc=(0, 0, 0.2225), material=CORK, verts=12, r2=0.042, bevel=0.005, seg=1)

# ---- belt with buckle, side lugs and a back clasp
bz, bh = CZ - 0.004, 0.019
rb = math.sqrt(R * R - 0.004 ** 2) + 0.004
parts = [B.lathe('belt_band', [(rb - 0.006, bz - bh), (rb + 0.005, bz - bh), (rb + 0.005, bz + bh), (rb - 0.006, bz + bh)], BELT, seg=20, cap_top=False, cap_bottom=False)]
parts.append(B.box('belt_buckle', (0.058, 0.016, 0.058), loc=(0, -(rb + 0.006), bz), material=BELT, bevel=0.008, seg=1))
parts.append(B.cyl('belt_stud', 0.014, 0.012, loc=(0, -(rb + 0.017), bz), material=STUD, rot=(math.radians(90), 0, 0), verts=10, r2=0.009))
parts.append(B.box('belt_clasp', (0.022, 0.014, 0.05), loc=(0, rb + 0.005, bz), material=BELT, bevel=0.005, seg=1))
for s in (-1, 1):
    parts.append(B.box(f'belt_lug{s}', (0.016, 0.04, 0.052), loc=(s * (rb + 0.006), 0, bz), material=BELT, bevel=0.006, seg=1))
belt = B.join('potion_belt', parts)

B.finish('shield_potion', HERE, budget=4000)
