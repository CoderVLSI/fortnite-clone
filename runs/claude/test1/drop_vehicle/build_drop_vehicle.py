"""Drop vehicle: a cargo blimp. Teal-and-cream gondola (10 x 2.6 x 3.2 m) hanging under a striped
envelope (8 m wide, 6 m tall, 3 m above the roof), with a burner and two rear propeller pods.
Nose points to -Y, origin at the bottom centre of the gondola."""
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'common'))
import bpy, bmesh
from mathutils import Vector
import brlib as B

B.reset()
TEAL = B.mat('mat_teal', '#2f8590', rough=0.6)
CREAM = B.mat('mat_cream', '#ead9b4', rough=0.65)
RED = B.mat('mat_red', '#c8473a', rough=0.65)
GLASS = B.mat('mat_glass', '#2c3f5c', rough=0.2, metal=0.3)
IRON = B.mat('mat_iron', '#484a50', rough=0.5, metal=0.6)
LAMP = B.mat('mat_lamp', '#ffc45a', rough=0.4, emit=2.5)
FLAME = B.mat('mat_flame', '#49b6ff', rough=0.4, emit=4.0)
ORANGE = B.mat('mat_envelope_orange', '#e2702c', rough=0.85)
ENV_C = B.mat('mat_envelope_cream', '#ecdcb6', rough=0.85)
PROP = B.mat('mat_prop', '#3a3c42', rough=0.5, metal=0.4)
TIP = B.mat('mat_prop_tip', '#f0a020', rough=0.6)
WOOD = B.mat('mat_wood', '#b9782f', rough=0.75)

L, W = 10.0, 2.6
Z0, ZM, ZR = 0.45, 1.75, 3.2                 # floor, waistline, roof
hw = W / 2

# ---- gondola
body = [B.box('hull_low', (W, L - 1.2, ZM - Z0), loc=(0, 0.6, (Z0 + ZM) / 2), material=TEAL, bevel=0.16, seg=2),
        B.box('hull_high', (W - 0.12, L - 1.5, ZR - ZM), loc=(0, 0.7, (ZM + ZR) / 2), material=CREAM, bevel=0.22, seg=2),
        # tapered nose
        B.prism('nose_low', [(-L / 2, Z0 + 0.25), (-L / 2 + 1.5, Z0), (-L / 2 + 1.5, ZM), (-L / 2 + 0.1, ZM - 0.15)], W - 0.3, material=TEAL, axis='X', bevel=0.14, seg=2),
        B.prism('nose_high', [(-L / 2 + 0.5, ZM - 0.1), (-L / 2 + 1.7, ZM - 0.1), (-L / 2 + 1.7, ZR - 0.1), (-L / 2 + 1.3, ZR - 0.1)], W - 0.5, material=CREAM, axis='X', bevel=0.12, seg=2),
        B.box('belt', (W + 0.06, L - 1.6, 0.14), loc=(0, 0.7, ZM), material=RED, bevel=0.03, seg=1),
        B.box('roof_rack', (W - 0.7, 5.0, 0.1), loc=(0, 0.6, ZR + 0.12), material=IRON, bevel=0.02, seg=1),
        B.box('door_step', (0.5, 1.5, 0.12), loc=(hw + 0.2, 2.6, Z0 + 0.1), material=IRON, bevel=0.02, seg=1)]
for s in (-1, 1):                              # landing skids
    body.append(B.box(f'skid{s}', (0.22, L - 2.4, 0.16), loc=(s * (hw - 0.45), 0.4, 0.08), material=IRON, bevel=0.05, seg=1))
    for y in (-2.6, 3.4):
        body.append(B.box(f'skid_leg{s}{y}', (0.14, 0.2, Z0), loc=(s * (hw - 0.45), y, Z0 / 2), material=IRON))
    body.append(B.cyl(f'headlight_rim{s}', 0.24, 0.1, loc=(s * 0.75, -L / 2 + 0.2, Z0 + 0.72), material=IRON, rot=(math.radians(74), 0, 0), verts=12))
body = B.join('blimp_gondola', body)
body['smooth_angle'] = 35

glass = []
for i in range(6):                             # side windows (the last bay on the right is the door)
    y = -2.3 + i * 1.12
    for s in (-1, 1):
        if s == 1 and i >= 4:
            continue
        glass.append(B.box(f'win{s}{i}', (0.08, 0.9, 0.78), loc=(s * (hw - 0.05), y, ZM + 0.72), material=GLASS, bevel=0.02, seg=1))
glass.append(B.box('door_dark', (0.08, 1.5, ZR - Z0 - 0.45), loc=(hw - 0.05, 2.6, (Z0 + ZR) / 2), material=GLASS))
for s in (-1, 1):
    glass.append(B.box(f'windshield{s}', (1.0, 0.08, 0.95), loc=(s * 0.55, -L / 2 + 0.98, ZM + 0.62), material=GLASS, rot=(math.radians(-18), 0, 0), bevel=0.02, seg=1))
    glass.append(B.box(f'rear_win{s}', (0.85, 0.08, 0.7), loc=(s * 0.55, L / 2 - 0.02 + 0.08, ZM + 0.72), material=GLASS, bevel=0.02, seg=1))
glass = B.join('blimp_glass', glass)

lamps = [B.cyl(f'headlight{s}', 0.19, 0.06, loc=(s * 0.75, -L / 2 + 0.16, Z0 + 0.73), material=LAMP, rot=(math.radians(74), 0, 0), verts=12) for s in (-1, 1)]
lamps.append(B.cyl('lantern', 0.16, 0.3, loc=(-0.6, -1.6, ZR + 0.42), material=LAMP, verts=8))
lamps.append(B.cyl('lantern_cap', 0.2, 0.12, loc=(-0.6, -1.6, ZR + 0.63), material=IRON, verts=8, r2=0.06))
lamps = B.join('blimp_lamps', lamps)

cargo = [B.cyl('tank', 0.33, 1.6, loc=(0.45, 1.6, ZR + 0.5), material=TEAL, rot=(math.radians(90), 0, 0), verts=12, bevel=0.05, seg=1),
         B.box('crate', (0.8, 0.8, 0.6), loc=(-0.45, 1.2, ZR + 0.47), material=WOOD, bevel=0.04, seg=1)]
for y in (1.1, 2.1):
    cargo.append(B.cyl(f'tank_band{y}', 0.35, 0.08, loc=(0.45, y, ZR + 0.5), material=IRON, rot=(math.radians(90), 0, 0), verts=12))
cargo = B.join('blimp_cargo', cargo)

# ---- envelope: 12 gores, alternating colours, flattened sphere 8 m wide and 6 m tall
RX, RZ = 4.0, 3.0
CZ = ZR + 3.0 + RZ
GORES, SUB, RINGS = 12, 3, 12
bm = bmesh.new()
rows = []
for j in range(1, RINGS):
    ph = math.pi * j / RINGS - math.pi / 2
    ring = []
    for i in range(GORES * SUB):
        u = (i % SUB) / SUB
        puff = 1 + 0.035 * math.sin(math.pi * u)
        a = 2 * math.pi * i / (GORES * SUB)
        r = RX * math.cos(ph) * puff
        ring.append(bm.verts.new((r * math.cos(a), r * math.sin(a) * 1.08, CZ + RZ * math.sin(ph))))
    rows.append(ring)
top = bm.verts.new((0, 0, CZ + RZ))
bot = bm.verts.new((0, 0, CZ - RZ))
n = GORES * SUB
for j in range(len(rows) - 1):
    for i in range(n):
        k = (i + 1) % n
        f = bm.faces.new((rows[j][i], rows[j][k], rows[j + 1][k], rows[j + 1][i]))
        f.material_index = (i // SUB) % 2
for i in range(n):
    k = (i + 1) % n
    f = bm.faces.new((rows[-1][i], rows[-1][k], top)); f.material_index = (i // SUB) % 2
    f = bm.faces.new((rows[0][k], rows[0][i], bot)); f.material_index = (i // SUB) % 2
env = B.obj_from_bm('envelope', bm, ORANGE)
env.data.materials.append(ENV_C)
env['smooth_angle'] = 50
env['grad_lo'] = 0.78
envelope = B.join('blimp_envelope', [env, B.cyl('valve', 0.55, 0.22, loc=(0, 0, CZ + RZ + 0.05), material=IRON, verts=12, bevel=0.05, seg=1),
                                     B.cyl('mouth', 0.95, 0.5, loc=(0, 0, CZ - RZ + 0.1), material=IRON, verts=12, r2=1.35)])

# ---- rigging: burner under the envelope, struts from the roof corners to the envelope
rig = [B.cyl('burner', 0.35, 0.5, loc=(0, 0, ZR + 0.4), material=IRON, verts=10, bevel=0.04, seg=1),
       B.cyl('burner_ring', 0.6, 0.14, loc=(0, 0, CZ - RZ - 0.5), material=IRON, verts=12)]
for a in (-1, 1):
    for b in (-1, 1):
        base = Vector((a * (hw - 0.25), 0.6 + b * 3.3, ZR))
        hold = Vector((a * 2.75, b * 3.0 * 1.0, CZ - RZ * 0.55))
        rig.append(B.tube(f'strut{a}{b}', [base, base + Vector((a * 0.5, b * 0.2, 1.2)), hold], 0.07, IRON, verts=6))
        rig.append(B.box(f'strut_foot{a}{b}', (0.4, 0.5, 0.3), loc=base + Vector((0, 0, 0.1)), material=IRON, bevel=0.05, seg=1))
        rig.append(B.tube(f'stay{a}{b}', [Vector((a * 0.5, b * 0.5, CZ - RZ - 0.5)), Vector((a * 0.5, b * 0.5 + 0.6 * b, ZR + 0.15))], 0.04, IRON, verts=5))
rig = B.join('blimp_rigging', rig)
flame = B.cyl('blimp_flame', 0.22, 2.0, loc=(0, 0, ZR + 1.6), material=FLAME, verts=8, r2=0.05)

# ---- propeller pods at the rear, with separate spinning propellers
pods = []
props = []
for s in (-1, 1):
    px, py, pz = s * (hw + 0.75), L / 2 - 1.3, ZM + 0.35
    pods.append(B.cyl(f'pod{s}', 0.48, 1.5, loc=(px, py, pz), material=CREAM, rot=(math.radians(-90), 0, 0), verts=12, r2=0.3, bevel=0.06, seg=1))
    pods.append(B.cyl(f'pod_band{s}', 0.5, 0.2, loc=(px, py + 0.2, pz), material=RED, rot=(math.radians(90), 0, 0), verts=12))
    pods.append(B.box(f'pod_arm{s}', (0.8, 0.5, 0.2), loc=(s * (hw + 0.3), py, pz), material=IRON, bevel=0.05, seg=1))
    blades = [B.cyl(f'hub{s}', 0.2, 0.35, loc=(px, py + 0.9, pz), material=IRON, rot=(math.radians(-90), 0, 0), verts=10, r2=0.06)]
    for k in range(3):
        ang = math.radians(120 * k + 20)
        d = Vector((math.cos(ang), 0, math.sin(ang)))
        c = Vector((px, py + 0.85, pz))
        blades.append(B.beam(f'blade{s}{k}', c + d * 0.15, c + d * 1.05, 0.3, 0.05, material=PROP, bevel=0.02))
        blades.append(B.beam(f'blade_tip{s}{k}', c + d * 1.0, c + d * 1.25, 0.28, 0.05, material=TIP, bevel=0.02))
    p = B.join(f'blimp_prop_{"l" if s < 0 else "r"}', blades)
    B.set_pivot(p, (px, py + 0.85, pz))        # spins about Y
    props.append(p)
pods = B.join('blimp_pods', pods)

for o in (body, glass, lamps, cargo, envelope, rig, flame, pods):
    B.set_pivot(o, (0, 0, 0))
B.finish('drop_vehicle', HERE, budget=30000, views=('side', '3/4', 'front', 'back'), aspect=0.95, res=720)
