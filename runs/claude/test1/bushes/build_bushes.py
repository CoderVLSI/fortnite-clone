"""Bushes: a plain bush and a berry bush, each a cluster of leafy clumps.
Each bush is one object with the origin at its bottom centre."""
import sys, os, math, random
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'common'))
import bpy, bmesh
from mathutils import Vector
import brlib as B

B.reset()
LEAF = B.mat('mat_leaf', '#5fae45', rough=0.75)
LEAF_L = B.mat('mat_leaf_light', '#8fd05a', rough=0.75)
CORE = B.mat('mat_leaf_core', '#2f7a3c', rough=0.8)
BERRY = B.mat('mat_berry', '#d2262b', rough=0.45)
for m in (LEAF, LEAF_L):
    m.use_backface_culling = False

# clump centre (x, y, z) and radius, for a bush about 1.4 m wide and 1.1 m tall
CLUMPS = [((0.02, 0.12, 0.72), 0.36), ((-0.36, -0.05, 0.52), 0.33), ((0.38, 0.02, 0.50), 0.31),
          ((0.05, -0.28, 0.42), 0.34), ((-0.40, -0.12, 0.24), 0.28), ((0.42, -0.14, 0.24), 0.27),
          ((0.0, 0.34, 0.36), 0.33), ((-0.05, -0.38, 0.2), 0.24)]


def leaves(rng, bm, centre, radius, count, mat_light_from):
    c = Vector(centre)
    for i in range(count):
        # fibonacci points over the upper ~80 % of the clump
        zz = 1 - (i + 0.5) / count * 1.6
        ang = i * 2.39996 + rng.uniform(-0.2, 0.2)
        rr = math.sqrt(max(0.0, 1 - zz * zz))
        n = Vector((rr * math.cos(ang), rr * math.sin(ang), zz))
        down = Vector((0, 0, -1)) - n * n.dot(Vector((0, 0, -1)))
        if down.length < 0.25:
            down = Vector((math.cos(ang), math.sin(ang), 0)) - n * n.dot(Vector((math.cos(ang), math.sin(ang), 0)))
        t = down.normalized()
        side = n.cross(t).normalized()
        tw = rng.uniform(-0.5, 0.5)
        t, side = (t * math.cos(tw) + side * math.sin(tw)), (side * math.cos(tw) - t * math.sin(tw))
        L = radius * rng.uniform(0.55, 0.7)
        W = L * 0.34
        lift = math.radians(rng.uniform(8, 20))
        d = t * math.cos(lift) + n * math.sin(lift)
        base = c + n * radius * 0.86 - t * L * 0.3
        P = lambda u, w, h=0.0: base + d * L * u + side * W * w + n * L * h
        vb, vl1, vr1, vm, vl2, vr2, vt = (bm.verts.new(p) for p in (
            P(0, 0), P(0.3, -1), P(0.3, 1), P(0.45, 0, 0.08), P(0.72, -0.85), P(0.72, 0.85), P(1, 0, -0.03)))
        mi = 1 if n.z > mat_light_from else 0
        for tri in ((vb, vm, vl1), (vb, vr1, vm), (vl1, vm, vl2), (vm, vr1, vr2), (vl2, vm, vt), (vm, vr2, vt)):
            f = bm.faces.new(tri)
            f.normal_update()
            if f.normal.dot(n) < 0:
                f.normal_flip()
            f.material_index = mi


def bush(name, x, seed, berries):
    rng = random.Random(seed)
    parts = []
    bm = bmesh.new()
    for ci, (c, r) in enumerate(CLUMPS):
        c = (c[0] + rng.uniform(-0.04, 0.04), c[1] + rng.uniform(-0.04, 0.04), c[2])
        core = B.ico(f'{name}_core{ci}', r * 0.9, loc=c, material=CORE, sub=1, scale=(1, 1, 0.9))
        parts.append(core)
        leaves(rng, bm, c, r, 50 if r > 0.3 else 38, 0.3)
    lv = B.obj_from_bm(name + '_leaves', bm, LEAF)
    lv.data.materials.append(LEAF_L)
    parts.insert(0, lv)
    if berries:
        for k in range(9):
            c, r = CLUMPS[rng.randrange(len(CLUMPS) - 1)]
            a = rng.uniform(-2.6, -0.5); el = rng.uniform(-0.3, 0.6)     # mostly on the front (-Y)
            n = Vector((math.cos(a) * math.cos(el), math.sin(a) * math.cos(el), math.sin(el)))
            p = Vector(c) + n * (r * 1.02)
            for j in range(rng.choice((2, 2, 3))):
                q = p + Vector((rng.uniform(-0.05, 0.05), rng.uniform(-0.02, 0.02), rng.uniform(-0.05, 0.05)))
                parts.append(B.sphere(f'{name}_berry{k}_{j}', 0.038, loc=q, material=BERRY, seg=6, rings=4))
    o = B.join(name, parts)
    o['keep_normals'] = True
    o['smooth_angle'] = 60
    o['grad_lo'] = 0.62
    o['grad_hi'] = 1.12
    B.set_pivot(o, (0, 0, 0))
    o.location.x = x
    return o

bush('bush_plain', -0.95, 11, False)
bush('bush_berry', 0.95, 23, True)
B.finish('bushes', HERE, budget=8000, views=('front', '3/4', 'back', 'top'), aspect=1.6, res=520, ground=True)
