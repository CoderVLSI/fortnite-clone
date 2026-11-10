"""Pickaxe: black grip, grey socket with a yellow band, curved steel pick and short adze.
Handle along Z, the long pick points to -Y, origin at the grip."""
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'common'))
import bpy, bmesh
from mathutils import Vector
import brlib as B

B.reset()
GRIP = B.mat('mat_grip', '#26272b', rough=0.8)
GRIP_L = B.mat('mat_grip_ring', '#3c3e44', rough=0.7)
SOCKET = B.mat('mat_socket', '#6d7076', rough=0.5, metal=0.5)
STEEL = B.mat('mat_steel', '#9a9ea6', rough=0.35, metal=0.6)
EDGE = B.mat('mat_steel_edge', '#c9d2e0', rough=0.25, metal=0.6)
YELLOW = B.mat('mat_band_yellow', '#c9c21e', rough=0.6)

Z0 = -0.22                                  # bottom of the handle; the hand holds it at the origin
H = 1.0
def z(t):                                   # height along the tool, 0..1
    return Z0 + H * t

handle = [B.cyl('pommel', 0.04, 0.07, loc=(0, 0, z(0.035)), material=GRIP_L, verts=8, bevel=0.01, seg=1),
          B.cyl('grip', 0.026, 0.42, loc=(0, 0, z(0.28)), material=GRIP, verts=10),
          B.cyl('grip_ring0', 0.031, 0.025, loc=(0, 0, z(0.09)), material=GRIP_L, verts=10),
          B.cyl('grip_ring1', 0.031, 0.02, loc=(0, 0, z(0.49)), material=GRIP_L, verts=10),
          B.cyl('shaft', 0.022, 0.12, loc=(0, 0, z(0.55)), material=SOCKET, verts=10),
          B.cyl('shaft_ribbed', 0.03, 0.07, loc=(0, 0, z(0.63)), material=GRIP, verts=10)]
handle = B.join('pickaxe_handle', handle)

head = [B.cyl('socket', 0.05, 0.19, loc=(0, 0, z(0.76)), material=SOCKET, verts=8, r2=0.062, bevel=0.008, seg=1),
        B.cyl('band', 0.065, 0.014, loc=(0, 0, z(0.862)), material=YELLOW, verts=8),
        B.box('eye', (0.11, 0.12, 0.1), loc=(0, 0, z(0.92)), material=SOCKET, bevel=0.018, seg=1),
        B.cyl('cap', 0.04, 0.035, loc=(0, 0, z(0.985)), material=SOCKET, verts=8, r2=0.028)]
for s in (-1, 1):
    head.append(B.cyl(f'pin{s}', 0.024, 0.03, loc=(s * 0.06, 0, z(0.92)), material=STEEL, rot=(0, math.radians(90), 0), verts=8))
    for k, zz in enumerate((0.73, 0.79)):
        head.append(B.cyl(f'screw{s}{k}', 0.015, 0.012, loc=(s * 0.054, 0, z(zz)), material=STEEL, rot=(0, math.radians(90), 0), verts=6))
# long curved pick toward -Y, sweeping down to a point
zt = z(0.92)
top, bot = [], []
for i in range(9):
    t = i / 8
    y = -0.05 - 0.36 * t
    drop = 0.26 * t ** 2.2
    th = 0.09 * (1 - t) ** 0.9 + 0.004
    top.append((y, zt + 0.045 - drop))
    bot.append((y, zt + 0.045 - drop - th))
pick = B.prism('pick', top + list(reversed(bot)), 0.03, material=STEEL, axis='X', bevel=0.006, seg=1)
edge = B.prism('pick_edge', [(p[0], p[1] + 0.004) for p in bot[2:]] + [(p[0], p[1] - 0.006) for p in reversed(bot[2:])], 0.012, material=EDGE, axis='X')
# short adze blade toward +Y, flaring slightly upward
adze = B.prism('adze', [(0.05, zt - 0.045), (0.05, zt + 0.045), (0.16, zt + 0.06), (0.235, zt + 0.085), (0.19, zt + 0.02), (0.17, zt - 0.025)], 0.03, material=STEEL, axis='X', bevel=0.006, seg=1)
head = B.join('pickaxe_head', head + [pick, edge, adze])
for o in (handle, head):
    B.set_pivot(o, (0, 0, 0))
B.finish('pickaxe', HERE, budget=4000)
