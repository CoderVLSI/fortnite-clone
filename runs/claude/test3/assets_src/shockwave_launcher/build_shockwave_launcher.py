"""Tinker's Shockwave Launcher (mythic): boxy shoulder-fired emitter, dark casing with yellow hazard trim, a flared
reflector bell and a blue-white emitter at the muzzle. Barrel to -Y, origin at the grip. Names prefixed mythic_shock_."""
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', '..', 'common'))
import bpy
import brlib as B
import gunlib as G

B.reset()
SLATE = B.mat('mat_shock_slate', '#4a5260', rough=0.55, metal=0.3)
DARK = B.mat('mat_shock_dark', '#23262d', rough=0.5, metal=0.5)
YELLOW = B.mat('mat_shock_yellow', '#e0b01c', rough=0.6)
STEEL = B.mat('mat_shock_steel', '#8d949e', rough=0.45, metal=0.6)
EMIT = B.mat('mat_shock_emitter', '#9fe4ff', rough=0.2, emit=2.0)

body = [B.box('main', (0.13, 0.5, 0.15), loc=(0, -0.12, 0.09), material=SLATE, bevel=0.012, seg=2),
        B.box('top', (0.1, 0.34, 0.04), loc=(0, -0.1, 0.18), material=DARK, bevel=0.006, seg=1),
        B.box('rear', (0.15, 0.1, 0.18), loc=(0, 0.17, 0.09), material=DARK, bevel=0.01, seg=2),
        G.guard('guard', DARK, -0.03, 0.03, 0.02, drop=0.045)]
for i in range(4):
    body.append(B.box(f'haz{i}', (0.134, 0.03, 0.152), loc=(0, -0.28 + i * 0.07, 0.09), material=YELLOW if i % 2 == 0 else DARK, bevel=0.002, seg=1))
body = B.join('mythic_shock_body', body)
grip = G.grip('mythic_shock_grip', DARK, y=0.0, top=0.02, length=0.11, rake=0.04, depth=0.05, width=0.045)
fg = G.P('mythic_shock_foregrip', [(-0.24, 0.02), (-0.2, 0.02), (-0.195, -0.07), (-0.235, -0.075)], 0.04, DARK, bevel=0.006)
body = B.join('mythic_shock_body', [body, grip, fg])
# emitter: a flared bell with stacked rings and a glowing lens
bell = [B.cyl('bell', 0.09, 0.12, loc=(0, -0.43, 0.09), rot=(math.radians(90), 0, 0), material=STEEL, verts=12, r2=0.045, bevel=0.003)]
for i in range(3):
    bell.append(B.cyl(f'ring{i}', 0.092 - i * 0.012, 0.012, loc=(0, -0.43 - i * 0.016, 0.09), rot=(math.radians(90), 0, 0), material=SLATE if i % 2 else YELLOW, verts=12))
bell = B.join('mythic_shock_bell', bell)
lens = B.cyl('mythic_shock_emitter', 0.05, 0.03, loc=(0, -0.495, 0.09), rot=(math.radians(90), 0, 0), material=EMIT, verts=12)
cells = [B.cyl(f'cell{i}', 0.022, 0.12, loc=(0, -0.05 + i * 0.075, 0.215), rot=(0, math.radians(90), 0), material=EMIT, verts=8) for i in range(3)]
cells = B.join('mythic_shock_cells', cells)
trig = G.trigger('mythic_shock_trigger', DARK, 0.0, 0.02)
B.set_pivot(trig, (0, 0.0, 0.018))
for o in (body, bell, lens, cells):
    B.set_pivot(o, (0, 0, 0))
B.finish('shockwave_launcher', HERE, budget=7000)
