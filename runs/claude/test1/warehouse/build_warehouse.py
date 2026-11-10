"""Warehouse: blue corrugated shell with orange frame, roller door on the +X gable, side door on the front (-Y),
gabled roof with two vents, crates outside. 14 x 10 m, 5 m walls, 7 m ridge. Hollow, with a walkable interior."""
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'common'))
import bpy, bmesh
from mathutils import Vector, Matrix
import brlib as B

B.reset()
BLUE = B.mat('mat_sheet_blue', '#4f7fb4', rough=0.6, metal=0.2)
BLUE_D = B.mat('mat_sheet_blue_dark', '#416c9c', rough=0.6, metal=0.2)
ORANGE = B.mat('mat_frame_orange', '#e2682a', rough=0.65)
GREY = B.mat('mat_roller_grey', '#8c9097', rough=0.5, metal=0.5)
GREY_D = B.mat('mat_roller_grey_dark', '#6f737a', rough=0.5, metal=0.5)
CONC = B.mat('mat_concrete', '#9a9a96', rough=0.9)
VENT = B.mat('mat_vent', '#55595f', rough=0.5, metal=0.5)
WOOD = B.mat('mat_wood', '#b9782f', rough=0.75)
WOOD_L = B.mat('mat_wood_light', '#cf8f3c', rough=0.75)

LX, LY, HW, HR, T = 14.0, 10.0, 5.0, 7.0, 0.2
hx, hy = LX / 2, LY / 2
DOOR = (3.6, 4.7, 0.0, 2.3)                 # side door on the front wall (u0, u1, z0, z1)
ROLL = (-2.6, 2.6, 0.0, 3.8)                # roller door on the +X gable (along Y)

shell = []
shell.append(B.place(B.wall('wall_front', LX, HW, T, (BLUE, BLUE_D), [DOOR], stripe='v'), (0, -hy + T / 2, 0)))
shell.append(B.place(B.wall('wall_back', LX, HW, T, (BLUE, BLUE_D), [], stripe='v'), (0, hy - T / 2, 0), 180))
shell.append(B.place(B.wall('wall_east', LY - 2 * T, HW, T, (BLUE, BLUE_D), [ROLL], stripe='v'), (hx - T / 2, 0, 0), 90))
shell.append(B.place(B.wall('wall_west', LY - 2 * T, HW, T, (BLUE, BLUE_D), [], stripe='v'), (-hx + T / 2, 0, 0), -90))
for s in (-1, 1):                            # gable triangles
    shell.append(B.prism(f'gable{s}', [(-hy, HW), (hy, HW), (0, HR)], T, loc=(s * (hx - T / 2), 0, 0), material=BLUE, axis='X'))
shell.append(B.box('floor', (LX + 0.3, LY + 0.3, 0.12), loc=(0, 0, -0.02), material=CONC))
shell = B.join('warehouse_shell', shell)
shell['keep_normals'] = True
shell['smooth_angle'] = 10

frame = []
for a in (-1, 1):
    for b in (-1, 1):
        frame.append(B.box(f'post{a}{b}', (0.5, 0.5, HW), loc=(a * hx, b * hy, HW / 2), material=ORANGE, bevel=0.05, seg=1))
        frame.append(B.box(f'footing{a}{b}', (0.75, 0.75, 0.5), loc=(a * hx, b * hy, 0.25), material=CONC, bevel=0.06, seg=1))
        # gable rake trim
        frame.append(B.beam(f'rake{a}{b}', (a * (hx + 0.05), b * (hy + 0.55), HW - 0.22), (a * (hx + 0.05), 0, HR + 0.08), 0.5, 0.4, material=ORANGE, bevel=0.05))
    frame.append(B.box(f'eave{a}', (LX, 0.35, 0.4), loc=(0, a * (hy + 0.02), HW - 0.05), material=ORANGE, bevel=0.05, seg=1))
    frame.append(B.box(f'ridge_plate{a}', (0.5, 0.9, 0.7), loc=(a * (hx + 0.1), 0, HR - 0.25), material=ORANGE, bevel=0.06, seg=1))
# roller-door frame on the +X gable
r0, r1, rz = ROLL[0], ROLL[1], ROLL[3]
frame.append(B.box('roll_frame_top', (0.4, r1 - r0 + 0.9, 0.45), loc=(hx + 0.02, 0, rz + 0.22), material=ORANGE, bevel=0.05, seg=1))
for s in (-1, 1):
    frame.append(B.box(f'roll_frame{s}', (0.4, 0.45, rz), loc=(hx + 0.02, s * (r1 + 0.22), rz / 2), material=ORANGE, bevel=0.05, seg=1))
# side-door frame on the front wall
d0, d1, dz = DOOR[0], DOOR[1], DOOR[3]
frame.append(B.box('door_frame_top', (d1 - d0 + 0.5, 0.3, 0.25), loc=((d0 + d1) / 2, -hy, dz + 0.12), material=ORANGE, bevel=0.03, seg=1))
for u in (d0 - 0.12, d1 + 0.12):
    frame.append(B.box(f'door_frame{u}', (0.25, 0.3, dz), loc=(u, -hy, dz / 2), material=ORANGE, bevel=0.03, seg=1))
frame.append(B.box('door_step', (1.6, 0.7, 0.12), loc=((d0 + d1) / 2, -hy - 0.4, 0.06), material=CONC, bevel=0.02, seg=1))
frame = B.join('warehouse_frame', frame)

# roof: two slabs with standing seams, plus two vents
roof = []
slope = math.atan2(HR - HW, hy)
run = math.hypot(hy + 0.6, (HR - HW) * (hy + 0.6) / hy)
for s in (-1, 1):
    mid = Vector((0, s * (hy + 0.6) / 2, HW + (HR - HW) * (1 - (hy + 0.6) / 2 / hy) + 0.12))
    slab = B.box(f'roof{s}', (LX + 0.7, run, 0.16), loc=mid, material=BLUE, rot=(-s * slope, 0, 0))
    roof.append(slab)
    for i in range(15):
        x = -hx + i * (LX / 14)
        rib = B.box(f'seam{s}{i}', (0.1, run, 0.08), loc=mid + Vector((x, 0, 0)) + Vector((0, s * math.sin(slope), math.cos(slope))) * 0.1, material=BLUE_D, rot=(-s * slope, 0, 0))
        roof.append(rib)
roof.append(B.box('ridge_cap', (LX + 0.7, 0.5, 0.14), loc=(0, 0, HR + 0.2), material=BLUE_D, bevel=0.03, seg=1))
for x in (-3.6, 3.6):
    zb = HR - 0.5
    roof.append(B.cyl(f'vent_base{x}', 0.42, 0.9, loc=(x, 1.3, zb + 0.2), material=VENT, verts=12))
    roof.append(B.cyl(f'vent_head{x}', 0.62, 0.5, loc=(x, 1.3, zb + 0.85), material=VENT, verts=12, bevel=0.08, seg=1))
    roof.append(B.cyl(f'vent_cap{x}', 0.4, 0.14, loc=(x, 1.3, zb + 1.16), material=VENT, verts=12, r2=0.2))
roof = B.join('warehouse_roof', roof)
roof['smooth_angle'] = 25

# roller door (separate: slides up) and side door (separate: hinged)
slats = []
n = 12
for i in range(n):
    slats.append(B.box(f'slat{i}', (0.1, r1 - r0, rz / n - 0.03), loc=(hx - T / 2, 0, rz / n * (i + 0.5)), material=GREY if i % 2 else GREY_D, bevel=0.02, seg=1))
roller = B.join('warehouse_roller_door', slats)
B.set_pivot(roller, (hx - T / 2, 0, 0))
door = [B.box('door_leaf', (d1 - d0, 0.08, dz), loc=((d0 + d1) / 2, -hy + T / 2, dz / 2), material=BLUE_D, bevel=0.015, seg=1),
        B.box('door_panel', (d1 - d0 - 0.3, 0.1, dz - 0.4), loc=((d0 + d1) / 2, -hy + T / 2, dz / 2), material=BLUE),
        B.cyl('door_knob', 0.06, 0.2, loc=(d0 + 0.14, -hy + T / 2, 1.05), material=VENT, rot=(math.radians(90), 0, 0), verts=8)]
door = B.join('warehouse_door', door)
B.set_pivot(door, (d1, -hy + T / 2, 0))      # hinge on the right edge

# crates stacked beside the roller door
def crate(name, loc, rz):
    c = [B.box(name + '_core', (0.92, 0.92, 0.92), loc=(0, 0, 0.5), material=WOOD)]
    for a in (-1, 1):
        for b in (-1, 1):
            c.append(B.box(f'{name}_v{a}{b}', (0.12, 0.12, 1.0), loc=(a * 0.44, b * 0.44, 0.5), material=WOOD_L, bevel=0.015, seg=1))
            c.append(B.box(f'{name}_hx{a}{b}', (0.88, 0.12, 0.12), loc=(0, a * 0.44, 0.5 + b * 0.44), material=WOOD_L, bevel=0.015, seg=1))
            c.append(B.box(f'{name}_hy{a}{b}', (0.12, 0.88, 0.12), loc=(a * 0.44, 0, 0.5 + b * 0.44), material=WOOD_L, bevel=0.015, seg=1))
        c.append(B.beam(f'{name}_x1{a}', (0.47 * a, -0.4, 0.1), (0.47 * a, 0.4, 0.9), 0.1, 0.04, material=WOOD_L))
        c.append(B.beam(f'{name}_x2{a}', (0.47 * a, 0.4, 0.1), (0.47 * a, -0.4, 0.9), 0.1, 0.04, material=WOOD_L))
        c.append(B.beam(f'{name}_y1{a}', (-0.4, 0.47 * a, 0.1), (0.4, 0.47 * a, 0.9), 0.04, 0.1, material=WOOD_L))
        c.append(B.beam(f'{name}_y2{a}', (0.4, 0.47 * a, 0.1), (-0.4, 0.47 * a, 0.9), 0.04, 0.1, material=WOOD_L))
    o = B.join(name, c)
    return B.place(o, loc, rz)
crates = B.join('warehouse_crates', [crate('crate_a', (hx + 1.0, -3.9, 0), 8), crate('crate_b', (hx + 1.15, -2.75, 0), -12), crate('crate_c', (hx + 1.05, -3.35, 1.0), 20)])

for o in (shell, frame, roof, crates):
    B.set_pivot(o, (0, 0, 0))
B.finish('warehouse', HERE, budget=20000, views=('front', 'side', '3/4', 'back'), aspect=1.5, res=560)
