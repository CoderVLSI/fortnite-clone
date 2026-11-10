"""Rocks: five chunky faceted boulders (two with moss), in a row along X.
Each rock is its own object with the origin at its bottom centre."""
import sys, os, math, random
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'common'))
import bpy, bmesh
from mathutils import Vector
import brlib as B

B.reset()
STONE = B.mat('mat_stone', '#a39a8b', rough=0.8)
MOSS = B.mat('mat_moss', '#8fb62c', rough=0.8)
MOSS_D = B.mat('mat_moss_dark', '#5f8f22', rough=0.8)


def chunk(rng, name, centre, size, n=13):
    """One faceted lump: convex hull of points on a squashed ellipsoid, cut flat at Z=0."""
    pts = []
    for _ in range(n):
        v = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).normalized()
        k = rng.uniform(0.9, 1.0)
        v.z = abs(v.z) * 0.9 + 0.1 if rng.random() < 0.6 else v.z   # bias mass upward
        v.normalize()
        p = Vector((centre[0] + v.x * size[0] / 2 * k, centre[1] + v.y * size[1] / 2 * k, centre[2] + v.z * size[2] / 2 * k))
        pts.append(p)
    top = centre[2] + size[2] / 2            # a small crown guarantees the target height
    for i in range(3):
        a = 2 * math.pi * i / 3 + rng.uniform(0, 2)
        pts.append(Vector((centre[0] + math.cos(a) * size[0] * 0.2, centre[1] + math.sin(a) * size[1] * 0.2, top - rng.uniform(0, 0.06) * size[2])))
    for i in range(6):                      # a footprint so the base is flat
        a = 2 * math.pi * (i + rng.uniform(-0.2, 0.2)) / 6
        pts.append(Vector((centre[0] + math.cos(a) * size[0] * 0.43, centre[1] + math.sin(a) * size[1] * 0.43, 0)))
    pts = [Vector((p.x, p.y, max(p.z, 0.0))) for p in pts]
    o = B.hull(name, pts, STONE)
    B.add_bevel(o, min(size) * 0.045, 2, angle=12)
    return o


def moss_patch(rng, name, centre, radius, n=9):
    parts = []
    for i in range(n):
        a = rng.uniform(0, 2 * math.pi); d = rng.uniform(0, radius)
        r = rng.uniform(0.28, 0.45) * radius
        o = B.ico(f'{name}_{i}', r, loc=(centre[0] + math.cos(a) * d, centre[1] + math.sin(a) * d * 0.8, centre[2] - d * 0.45 + rng.uniform(-0.01, 0.02)),
                  material=MOSS if i % 3 else MOSS_D, sub=1, scale=(1, 1, 0.5))
        parts.append(o)
    return parts

# id, x position, [(centre, size)], moss (centre, radius) or None
ROCKS = [
    ('rock_small_flat', -4.6, [((0, 0, 0.17), (1.35, 1.0, 0.46)), ((0.32, -0.25, 0.10), (0.75, 0.6, 0.30)), ((-0.35, 0.1, 0.14), (0.7, 0.75, 0.36))], None),
    ('rock_medium_moss', -2.5, [((0, 0, 0.48), (1.3, 1.15, 1.06)), ((-0.42, -0.2, 0.3), (0.62, 0.7, 0.72)), ((0.35, -0.3, 0.28), (0.8, 0.6, 0.62))], ((0.22, -0.05, 0.99), 0.42)),
    ('rock_tall', 0.0, [((0, 0.1, 1.08), (1.55, 1.35, 2.3)), ((0.12, -0.38, 0.7), (1.2, 0.8, 1.5)), ((-0.55, -0.1, 0.5), (0.7, 0.9, 1.05)), ((0.6, 0.0, 0.42), (0.6, 0.8, 0.9))], None),
    ('rock_wide_moss', 2.9, [((0, 0, 0.47), (2.1, 1.5, 1.04)), ((0.45, -0.4, 0.3), (1.15, 0.8, 0.66)), ((-0.65, -0.2, 0.36), (0.9, 1.0, 0.8))], ((-0.1, -0.05, 0.98), 0.6)),
    ('rock_small', 5.3, [((0, 0, 0.33), (0.85, 0.75, 0.74)), ((0.2, -0.2, 0.2), (0.6, 0.5, 0.46)), ((-0.2, 0.05, 0.22), (0.5, 0.55, 0.5))], None),
]
rng = random.Random(7)
for rid, x, chunks, moss in ROCKS:
    parts = [chunk(rng, f'{rid}_c{i}', c, s) for i, (c, s) in enumerate(chunks)]
    if moss:                                # seat the moss on the real top of the main chunk
        tv = max(parts[0].data.vertices, key=lambda v: v.co.z)
        parts += moss_patch(rng, rid + '_moss', (tv.co.x * 0.5, tv.co.y * 0.5 - 0.05, tv.co.z - 0.03), moss[1])
    o = B.join(rid, parts)
    o['smooth_angle'] = 20
    o['grad_lo'] = 0.78
    B.set_pivot(o, (0, 0, 0))
    o.location.x = x

B.finish('rocks', HERE, budget=1500 * 5, views=('front', '3/4', 'back', 'top'), aspect=2.6, res=420)
