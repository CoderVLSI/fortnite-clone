"""Ravage's Grasp (mythic): a dark red organic gauntlet, a bony armoured fist with writhing tendrils and an ember core.
Barrel (the tendril mouth) to -Y, origin at the grip, up +Z. Object names are prefixed mythic_grasp_."""
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', '..', 'common'))
import bpy
import brlib as B
import gunlib as G

B.reset()
FLESH = B.mat('mat_grasp_flesh', '#7a1620', rough=0.6)
FLESH_D = B.mat('mat_grasp_flesh_dark', '#3d0b12', rough=0.7)
BLACK = B.mat('mat_grasp_black', '#16101a', rough=0.5, metal=0.2)
BONE = B.mat('mat_grasp_bone', '#d6c9ab', rough=0.6)
EMBER = B.mat('mat_grasp_ember', '#ff4a1c', rough=0.3, emit=1.6)

core = [G.P('mythic_grasp_palm', [(-0.1, 0.0), (0.08, 0.0), (0.1, 0.07), (0.05, 0.12), (-0.1, 0.12), (-0.14, 0.07)], 0.09, BLACK, bevel=0.012, seg=2),
        G.P('mythic_grasp_knuckles', [(-0.2, 0.03), (-0.1, 0.02), (-0.1, 0.11), (-0.2, 0.1), (-0.23, 0.065)], 0.1, FLESH, bevel=0.015, seg=2),
        B.cyl('mythic_grasp_forearm', 0.055, 0.2, loc=(0, 0.17, 0.06), rot=(math.radians(90), 0, 0), material=FLESH_D, verts=10, r2=0.07, bevel=0.01)]
core = B.join('mythic_grasp_body', core)
# tendrils: curling tubes out of the gauntlet mouth and around the forearm
tend = []
for i, (dx, dz) in enumerate([(-0.04, 0.09), (0.04, 0.09), (0.0, 0.03), (-0.045, 0.03), (0.045, 0.04)]):
    sg = 1 if i % 2 else -1
    path = [(dx, -0.14, dz), (dx * 1.6, -0.22, dz + 0.01), (dx * 2.4 + 0.02 * sg, -0.31, dz + 0.04 * sg), (dx * 1.8, -0.38 - 0.02 * (i % 3), dz + 0.05 * sg)]
    tend.append(B.tube(f'mythic_grasp_tend{i}', path, 0.014, material=FLESH, verts=6, radii=[0.022, 0.018, 0.012, 0.004]))
for s in (-1, 1):
    tend.append(B.tube(f'mythic_grasp_wrap{s}', [(s * 0.05, 0.28, 0.04), (s * 0.075, 0.2, 0.09), (s * 0.06, 0.1, 0.13), (s * 0.03, 0.02, 0.135)], 0.012, material=FLESH, verts=6, radii=[0.012, 0.016, 0.014, 0.008]))
tend = B.join('mythic_grasp_tendrils', tend)
spikes = []
for i in range(5):
    spikes.append(B.cyl(f'sp{i}', 0.014, 0.05, loc=(-0.045 + i * 0.022, -0.14 + 0.02 * (i % 2), 0.135), material=BONE, verts=5, r2=0.002))
for i in range(3):
    spikes.append(B.cyl(f'sq{i}', 0.012, 0.045, loc=(-0.05 if i != 1 else 0.05, 0.05 + i * 0.07, 0.17), material=BONE, verts=5, r2=0.002))
spikes = B.join('mythic_grasp_spikes', spikes)
ember = B.ico('mythic_grasp_core', 0.032, loc=(0, -0.01, 0.125), material=EMBER, sub=1)
grip = G.grip('mythic_grasp_grip', FLESH_D, y=0.0, top=0.0, length=0.1, rake=0.02, depth=0.04, width=0.04)
for o in (core, tend, spikes, ember, grip):
    B.set_pivot(o, (0, 0, 0))
B.finish('ravage_grasp', HERE, budget=6000)
