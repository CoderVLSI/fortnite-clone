"""Trees: oak (6 m), pine (9 m) and palm (6 m). One object each, origin at the base of the trunk."""
import sys, os, math, random
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'common'))
import bpy, bmesh
from mathutils import Vector
import brlib as B

B.reset()
BARK = B.mat('mat_bark', '#9a5b2e', rough=0.85)
BARK_D = B.mat('mat_bark_dark', '#74421f', rough=0.85)
LEAF = B.mat('mat_leaf', '#58a83c', rough=0.75)
LEAF_L = B.mat('mat_leaf_light', '#93cf4a', rough=0.75)
CORE = B.mat('mat_leaf_core', '#2f7a3c', rough=0.8)
PINE = B.mat('mat_pine', '#2f8c4a', rough=0.8)
PINE_L = B.mat('mat_pine_light', '#5fb548', rough=0.8)
PINE_D = B.mat('mat_pine_dark', '#1f6a3c', rough=0.85)
PALM_T = B.mat('mat_palm_trunk', '#b88a4e', rough=0.85)
FROND = B.mat('mat_frond', '#7cc23a', rough=0.75)
FROND_D = B.mat('mat_frond_dark', '#4f9a30', rough=0.75)
NUT = B.mat('mat_coconut', '#6e4a2a', rough=0.8)
for m in (LEAF, LEAF_L, PINE, PINE_L, PINE_D, FROND, FROND_D):
    m.use_backface_culling = False


def roots(name, n, r0, length, rng, material):
    out = []
    for i in range(n):
        a = 2 * math.pi * (i + rng.uniform(-0.2, 0.2)) / n
        d = Vector((math.cos(a), math.sin(a), 0))
        out.append(B.tube(f'{name}_root{i}', [d * r0 * 0.5 + Vector((0, 0, 0.5)), d * (r0 + length * 0.5) + Vector((0, 0, 0.16)), d * (r0 + length) + Vector((0, 0, 0.05))],
                          0.1, material, verts=6, radii=[0.2, 0.13, 0.05]))
    return out

# ------------------------------------------------------------------ oak
def oak():
    rng = random.Random(5)
    parts = [B.lathe('oak_trunk', [(0.62, 0.0), (0.46, 0.25), (0.37, 0.7), (0.33, 1.3), (0.34, 1.9), (0.4, 2.3)], BARK, seg=10, cap_top=True, cap_bottom=True)]
    parts += roots('oak', 5, 0.45, 0.45, rng, BARK)
    parts.append(B.cyl('oak_knot', 0.11, 0.08, loc=(0.2, -0.3, 1.2), material=BARK_D, rot=(math.radians(90), 0, math.radians(35)), verts=8, r2=0.07))
    clumps = [((0.0, 0.1, 4.75), 1.25), ((-1.45, -0.2, 4.0), 1.15), ((1.4, 0.2, 4.1), 1.1), ((0.2, -1.15, 3.7), 1.1),
              ((-0.3, 1.2, 3.9), 1.1), ((-1.7, 0.5, 3.0), 0.85), ((1.75, -0.4, 3.0), 0.85)]
    bm = bmesh.new()
    for i, (c, r) in enumerate(clumps):
        parts.append(B.tube(f'oak_branch{i}', [(0, 0, 2.0), (c[0] * 0.45, c[1] * 0.45, 2.3 + (c[2] - 2.3) * 0.45), (c[0] * 0.85, c[1] * 0.85, c[2] - r * 0.5)],
                            0.1, BARK, verts=6, radii=[0.27, 0.17, 0.09]))
        parts.append(B.ico(f'oak_core{i}', r * 0.9, loc=c, material=CORE, sub=1, scale=(1, 1, 0.88)))
        B.leaf_clump(bm, rng, c, r, 62 if r > 1 else 44, 0.3, size=(0.42, 0.55))
    lv = B.obj_from_bm('oak_leaves', bm, LEAF)
    lv.data.materials.append(LEAF_L)
    o = B.join('tree_oak', [lv] + parts)
    o['keep_normals'] = True
    o['smooth_angle'] = 55
    o['grad_lo'] = 0.7
    return o

# ------------------------------------------------------------------ pine
def pine():
    rng = random.Random(9)
    parts = [B.lathe('pine_trunk', [(0.5, 0.0), (0.36, 0.3), (0.3, 1.0), (0.2, 4.5), (0.06, 8.6)], BARK, seg=10)]
    parts += roots('pine', 5, 0.36, 0.38, rng, BARK)
    for k, (a, z) in enumerate(((0.6, 1.25), (2.6, 1.6), (4.4, 1.05))):         # branch stubs
        d = Vector((math.cos(a), math.sin(a), 0.25))
        parts.append(B.tube(f'pine_stub{k}', [d * 0.25 + Vector((0, 0, z)), d * 0.55 + Vector((0, 0, z))], 0.08, BARK_D, verts=6))
    tiers = [(1.75, 2.15, 3.9), (3.1, 1.95, 5.0), (4.3, 1.65, 6.0), (5.4, 1.35, 6.95), (6.4, 1.05, 7.8), (7.3, 0.75, 8.5), (8.05, 0.45, 9.0)]
    bm = bmesh.new()
    SEG = 18
    for ti, (z0, r, z1) in enumerate(tiers):
        top = bm.verts.new((0, 0, z1))
        mid, rim, under = [], [], []
        for i in range(SEG):
            a = 2 * math.pi * i / SEG + ti * 0.4
            tip = i % 2 == 0                         # every other point droops into a tip
            rr = r * (1.0 if tip else 0.78) * rng.uniform(0.94, 1.04)
            zz = z0 - (0.22 if tip else 0.0)
            mid.append(bm.verts.new((rr * 0.55 * math.cos(a), rr * 0.55 * math.sin(a), z0 + (z1 - z0) * 0.5)))
            rim.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), zz)))
            under.append(bm.verts.new((r * 0.3 * math.cos(a), r * 0.3 * math.sin(a), z0 + 0.25)))
        for i in range(SEG):
            k = (i + 1) % SEG
            f = bm.faces.new((top, mid[i], mid[k])); f.material_index = 1
            f = bm.faces.new((mid[i], rim[i], rim[k], mid[k])); f.material_index = 0
            f = bm.faces.new((rim[k], rim[i], under[i], under[k])); f.material_index = 2
    fol = B.obj_from_bm('pine_foliage', bm, PINE)
    fol.data.materials.append(PINE_L)
    fol.data.materials.append(PINE_D)
    o = B.join('tree_pine', [fol] + parts)
    o['keep_normals'] = True
    o['smooth_angle'] = 35
    o['grad_lo'] = 0.72
    return o

# ------------------------------------------------------------------ palm
def palm():
    rng = random.Random(3)
    def spine(t):                                      # leaning, curved trunk
        return Vector((0.9 * t * t, 0.0, 5.0 * t))
    parts = []
    N = 9
    for i in range(N):
        t0, t1 = i / N, (i + 1) / N
        p0, p1 = spine(t0), spine(t1 + 0.012)
        r = 0.34 - 0.14 * t0
        parts.append(B.tube(f'palm_seg{i}', [p0, p1], r, PALM_T, verts=10, radii=[r * 0.86, r]))
    crown = spine(1.0)
    for k in range(3):
        a = 2.1 * k + 0.4
        parts.append(B.sphere(f'palm_nut{k}', 0.17, loc=crown + Vector((0.2 * math.cos(a), 0.2 * math.sin(a), -0.12)), material=NUT, seg=8, rings=6))
    bm = bmesh.new()
    NF, SEGS = 9, 8
    for f in range(NF):
        a = 2 * math.pi * f / NF + 0.2
        d = Vector((math.cos(a), math.sin(a), 0))
        side = Vector((-math.sin(a), math.cos(a), 0))
        L = rng.uniform(2.3, 2.7)
        rows = []
        for s in range(SEGS + 1):
            u = s / SEGS
            p = crown + d * (L * u) + Vector((0, 0, 0.95 * math.sin(u * math.pi * 0.62) - 1.9 * u * u + 0.2))
            w = 0.82 * math.sin(math.pi * min(u * 1.15 + 0.08, 1.0)) ** 0.7 * (1.0 if s % 2 == 0 else 0.84)
            droop = Vector((0, 0, -0.32 * w))
            rows.append((bm.verts.new(p - side * w + droop), bm.verts.new(p + Vector((0, 0, 0.07))), bm.verts.new(p + side * w + droop)))
        for s in range(SEGS):
            l0, m0, r0 = rows[s]; l1, m1, r1 = rows[s + 1]
            f1 = bm.faces.new((l0, m0, m1, l1)); f1.material_index = 1
            f2 = bm.faces.new((m0, r0, r1, m1)); f2.material_index = 0
            for ff in (f1, f2):
                ff.normal_update()
                if ff.normal.z < 0:
                    ff.normal_flip()
    fr = B.obj_from_bm('palm_fronds', bm, FROND)
    fr.data.materials.append(FROND_D)
    o = B.join('tree_palm', [fr] + parts)
    o['keep_normals'] = True
    o['smooth_angle'] = 40
    o['grad_lo'] = 0.78
    return o

for o, x in ((oak(), -5.6), (pine(), 0.0), (palm(), 4.6)):
    B.set_pivot(o, (0, 0, 0))
    o.location.x = x
B.finish('trees', HERE, budget=18000, views=('front', '3/4', 'back', 'top'), aspect=1.5, res=560)
