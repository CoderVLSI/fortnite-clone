"""Grenade: olive segmented body, grey fuse cap, safety lever, pull ring.
Run: python build_grenade.py   (or blender --background --python build_grenade.py)"""
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'common'))
import bpy, bmesh
from mathutils import Vector
import brlib as B

B.reset()
OLIVE = B.mat('mat_olive', '#6f7040', rough=0.75)
GROOVE = B.mat('mat_olive_dark', '#4b4d2b', rough=0.8)
STEEL = B.mat('mat_gunmetal', '#55585c', rough=0.55, metal=0.5)
STEEL_D = B.mat('mat_gunmetal_dark', '#3c3f43', rough=0.55, metal=0.5)

# --- body: sphere whose faces are inset and raised into chunky plates
R = 0.0372
bm = bmesh.new()
bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=6, radius=R)
for v in bm.verts:                       # slightly flattened so it reads chunky
    v.co.z = max(v.co.z * 0.97, -R * 0.90)   # flat base so it can stand
faces = list(bm.faces)
quads = [f for f in faces if len(f.verts) == 4]   # pole fans stay smooth caps
r1 = bmesh.ops.inset_individual(bm, faces=quads, thickness=0.0019, depth=0.0, use_even_offset=True)
groove = set(r1['faces'])
r2 = bmesh.ops.inset_individual(bm, faces=quads, thickness=0.0022, depth=0.0026, use_even_offset=True)
r3 = bmesh.ops.inset_individual(bm, faces=quads, thickness=0.0016, depth=0.0005, use_even_offset=True)
for f in bm.faces:
    f.material_index = 1 if f in groove else 0
body = B.obj_from_bm('grenade_body', bm, OLIVE, loc=(0, 0, R * 0.97 + 0.0031))
body.data.materials.append(GROOVE)
body['smooth_angle'] = 34
top = 2 * (R * 0.97 + 0.0031)            # ~0.0778

# --- fuse: collar + chamfered cap
collar = B.cyl('grenade_collar', 0.0185, 0.012, loc=(0, 0, top + 0.001), material=STEEL_D, verts=16, bevel=0.002, seg=2)
cap = B.box('grenade_cap', (0.027, 0.034, 0.02), loc=(0, -0.002, top + 0.0165), material=STEEL, bevel=0.004, seg=2)
ztop = top + 0.0265

# --- safety lever: a bent strap from the cap top down the back of the body
def strap(name, pts, widths, th, material):
    bm = bmesh.new()
    rows = []
    n = len(pts)
    for i, (y, z) in enumerate(pts):
        a = Vector((0, *pts[max(i - 1, 0)])); b = Vector((0, *pts[min(i + 1, n - 1)]))
        t = (b - a).normalized()
        nrm = Vector((0, -t.z, t.y))        # outward normal in the YZ plane
        w = widths[i] / 2
        p = Vector((0, y, z))
        rows.append([bm.verts.new(p + Vector((-w, 0, 0))), bm.verts.new(p + Vector((w, 0, 0))),
                     bm.verts.new(p + Vector((w, 0, 0)) + nrm * th), bm.verts.new(p + Vector((-w, 0, 0)) + nrm * th)])
    for i in range(n - 1):
        for k in range(4):
            bm.faces.new((rows[i][k], rows[i][(k + 1) % 4], rows[i + 1][(k + 1) % 4], rows[i + 1][k]))
    bm.faces.new(list(reversed(rows[0]))); bm.faces.new(rows[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return B.obj_from_bm(name, bm, material)

cz = R * 0.97 + 0.0031
pts = [(-0.012, ztop - 0.001), (0.012, ztop - 0.001), (0.027, ztop - 0.008)]
for deg in (38, 22, 6, -10, -24):          # follow the body at a small stand-off
    a = math.radians(deg)
    rr = R + 0.0052
    pts.append((rr * math.cos(a), cz + rr * math.sin(a)))
widths = [0.021, 0.021, 0.022, 0.023, 0.023, 0.023, 0.022, 0.019]
lever = strap('grenade_lever', pts, widths, 0.0042, STEEL)
B.add_bevel(lever, 0.0012, 1, angle=50)

# --- pull ring on the front, hanging from a small hinge pin
pin = B.cyl('grenade_pin', 0.0032, 0.036, loc=(0, -0.017, top + 0.014), material=STEEL_D, rot=(0, math.radians(90), 0), verts=10, bevel=0.0008, seg=1)
lug = B.box('grenade_lug', (0.009, 0.007, 0.009), loc=(0, -0.021, top + 0.012), material=STEEL, bevel=0.0015, seg=1)
ring = B.torus('grenade_ring', 0.0165, 0.0028, loc=(0, -0.0318, top - 0.0045), material=STEEL, rot=(math.radians(74), 0, 0), major=20, minor=6)

fuse = B.join('grenade_fuse', [collar, cap, pin, lug])
B.set_pivot(lever, (0, -0.012, ztop))        # lever hinges at the cap
B.set_pivot(ring, (0, -0.021, top + 0.012))  # ring swings on the lug
B.set_pivot(body, (0, 0, 0))
B.finish('grenade', HERE, budget=2500, ground=True)
