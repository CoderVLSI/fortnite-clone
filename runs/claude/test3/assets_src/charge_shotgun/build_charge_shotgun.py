"""Tinker's Charge Shotgun (mythic): chunky scrap-metal double barrel with riveted plates, a coil and a glowing core.
Barrel to -Y, origin at the grip, up +Z. Object names are prefixed mythic_charge_."""
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', '..', 'common'))
import bpy
import brlib as B
import gunlib as G

B.reset()
RUST = B.mat('mat_charge_rust', '#8a5632', rough=0.8, metal=0.2)
STEEL = B.mat('mat_charge_steel', '#6c7178', rough=0.5, metal=0.6)
DARK = B.mat('mat_charge_dark', '#2a2c31', rough=0.5, metal=0.5)
YELLOW = B.mat('mat_charge_yellow', '#d9a21b', rough=0.6)
CORE = B.mat('mat_charge_core', '#35e6ff', rough=0.25, emit=1.8)
WOOD = B.mat('mat_charge_wood', '#5a3b24', rough=0.8)

barrels = []
for x in (-0.026, 0.026):
    barrels.append(G.ycyl(f'b{x}', 0.03, -0.46, -0.1, 0.085, STEEL, 10, x=x, bevel=0.003))
    barrels.append(G.ycyl(f'm{x}', 0.036, -0.47, -0.43, 0.085, DARK, 10, x=x))
barrels.append(B.box('rib', (0.03, 0.34, 0.016), loc=(0, -0.28, 0.12), material=DARK, bevel=0.003, seg=1))
barrels = B.join('mythic_charge_barrels', barrels)

body = [G.P('rec', [(-0.12, 0.02), (0.1, 0.02), (0.1, 0.13), (-0.12, 0.13), (-0.14, 0.11)], 0.1, RUST, bevel=0.008, seg=2),
        G.P('plate1', [(-0.1, 0.13), (0.08, 0.13), (0.08, 0.15), (-0.1, 0.15)], 0.11, YELLOW, bevel=0.004),
        G.P('stock', [(0.1, 0.05), (0.3, 0.02), (0.3, 0.11), (0.1, 0.12)], 0.06, WOOD, bevel=0.008, seg=2),
        G.P('pump', [(-0.3, 0.035), (-0.17, 0.035), (-0.17, 0.095), (-0.3, 0.095)], 0.1, RUST, bevel=0.01, seg=2),
        G.guard('guard', DARK, -0.03, 0.03, 0.02, drop=0.045)]
for i in range(6):
    body.append(B.cyl(f'rivet{i}', 0.008, 0.112, loc=(0, -0.09 + (i % 3) * 0.07, 0.115 if i < 3 else 0.04), rot=(0, math.radians(90), 0), material=STEEL, verts=6))
body = B.join('mythic_charge_body', body)
grip = G.grip('mythic_charge_grip', WOOD, y=0.035, top=0.02, length=0.11, rake=0.04, depth=0.05, width=0.042)
body = B.join('mythic_charge_body', [body, grip])

# energy coil wrapped on the barrels around a glowing core
coil = []
for i in range(5):
    coil.append(B.torus(f'turn{i}', 0.05, 0.007, loc=(0, -0.32 + i * 0.03, 0.085), material=YELLOW, rot=(math.radians(90), 0, 0), major=12, minor=5))
coil = B.join('mythic_charge_coil', coil)
core = B.cyl('mythic_charge_core', 0.022, 0.1, loc=(0, -0.2, 0.17), rot=(math.radians(90), 0, 0), material=CORE, verts=8)
cage = [B.cyl('tank', 0.04, 0.12, loc=(0, -0.2, 0.17), rot=(math.radians(90), 0, 0), material=DARK, verts=8)]
for i in range(4):
    a = i * math.pi / 2 + 0.78
    cage.append(B.box(f'bar{i}', (0.006, 0.13, 0.006), loc=(0.042 * math.cos(a), -0.2, 0.17 + 0.042 * math.sin(a)), material=STEEL))
cage = B.join('mythic_charge_cage', cage)
trig = G.trigger('mythic_charge_trigger', DARK, 0.0, 0.02)
B.set_pivot(trig, (0, 0.0, 0.018))
for o in (barrels, body, coil, core, cage):
    B.set_pivot(o, (0, 0, 0))
B.finish('charge_shotgun', HERE, budget=7000)
