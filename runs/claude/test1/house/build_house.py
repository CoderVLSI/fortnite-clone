"""House: two-storey timber house, 8 x 7 m, gable to the front (-Y), ridge at 9 m.
Hollow with a walkable ground floor, staircase, upper floor, hinged front door, porch and stone chimney."""
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'common'))
import bpy, bmesh
from mathutils import Vector, Matrix
import brlib as B

B.reset()
WOOD = B.mat('mat_wood', '#c98630', rough=0.75)
WOOD_B = B.mat('mat_wood_board', '#bb7a2a', rough=0.75)
TRIM = B.mat('mat_wood_trim', '#dda040', rough=0.75)
DARKW = B.mat('mat_wood_dark', '#9a6222', rough=0.8)
ROOF = B.mat('mat_roof', '#d94a38', rough=0.8)
ROOF_D = B.mat('mat_roof_dark', '#b93a2c', rough=0.8)
GLASS = B.mat('mat_glass', '#3a5a8c', rough=0.2, metal=0.2)
STONE = B.mat('mat_stone', '#9c9a98', rough=0.85)
STONE_D = B.mat('mat_stone_dark', '#84827f', rough=0.85)
IRON = B.mat('mat_iron', '#4a4c52', rough=0.5, metal=0.6)
CLOTH = B.mat('mat_bedding', '#e6dcc0', rough=0.9)

LX, LY, T = 8.0, 7.0, 0.22
hx, hy = LX / 2, LY / 2
F2, HW, HR = 3.0, 6.0, 9.0                  # upper floor level, wall height, ridge
WIN = 1.0                                   # window size
DOOR = (-0.6, 0.6, 0.15, 2.3)


def win(u, z):
    return (u - WIN / 2, u + WIN / 2, z, z + 1.15)

front_open = [DOOR, win(-2.5, 1.05), win(2.5, 1.05), win(-1.7, 4.0), win(1.7, 4.0)]
side_open = [win(0.0, 1.05), win(0.0, 4.0)]
back_open = [win(1.8, 4.0), win(1.8, 1.05)]

shell = [B.place(B.wall('wall_front', LX, HW, T, (WOOD, WOOD_B), front_open, stripe='h'), (0, -hy + T / 2, 0)),
         B.place(B.wall('wall_back', LX, HW, T, (WOOD, WOOD_B), back_open, stripe='h'), (0, hy - T / 2, 0), 180),
         B.place(B.wall('wall_east', LY - 2 * T, HW, T, (WOOD, WOOD_B), side_open, stripe='h'), (hx - T / 2, 0, 0), 90),
         B.place(B.wall('wall_west', LY - 2 * T, HW, T, (WOOD, WOOD_B), side_open, stripe='h'), (-hx + T / 2, 0, 0), -90)]
for s in (-1, 1):                            # gables over the front and back walls
    shell.append(B.prism(f'gable{s}', [(-hx, HW), (hx, HW), (0, HR - 0.15)], T, loc=(0, s * (hy - T / 2), 0), material=WOOD, axis='Y'))
# ground slab and upper floor (with a stair opening along the east wall)
shell.append(B.box('ground', (LX + 0.3, LY + 0.3, 0.2), loc=(0, 0, 0.05), material=DARKW))
SX0, SX1, SY0, SY1 = 2.5, hx - T, -2.4, 2.2  # stair well
shell.append(B.box('floor2_a', (SX0 + hx - T, LY - 2 * T, 0.2), loc=((SX0 - hx + T) / 2, 0, F2 + 0.05), material=WOOD_B))
shell.append(B.box('floor2_b', (SX1 - SX0, hy - T - SY1, 0.2), loc=((SX0 + SX1) / 2, (SY1 + hy - T) / 2, F2 + 0.05), material=WOOD_B))
shell.append(B.box('floor2_c', (SX1 - SX0, SY0 + hy - T, 0.2), loc=((SX0 + SX1) / 2, (SY0 - hy + T) / 2, F2 + 0.05), material=WOOD_B))
shell = B.join('house_shell', shell)
shell['keep_normals'] = True
shell['smooth_angle'] = 10

trim = []
for a in (-1, 1):
    for b in (-1, 1):
        trim.append(B.box(f'corner{a}{b}', (0.36, 0.36, HW), loc=(a * hx, b * hy, HW / 2), material=TRIM, bevel=0.04, seg=1))
        trim.append(B.box(f'corner_base{a}{b}', (0.5, 0.5, 0.45), loc=(a * hx, b * hy, 0.22), material=TRIM, bevel=0.05, seg=1))
    for z, h in ((0.2, 0.36), (F2 + 0.05, 0.32), (HW - 0.1, 0.3)):
        trim.append(B.box(f'belt_x{a}{z}', (LX, 0.3, h), loc=(0, a * hy, z), material=TRIM, bevel=0.035, seg=1))
        trim.append(B.box(f'belt_y{a}{z}', (0.3, LY, h), loc=(a * hx, 0, z), material=TRIM, bevel=0.035, seg=1))
    trim.append(B.box(f'king_post{a}', (0.26, 0.26, HR - HW - 0.3), loc=(0, a * (hy + 0.02), (HW + HR) / 2 - 0.1), material=TRIM, bevel=0.03, seg=1))
trim = B.join('house_trim', trim)

# windows: frame, cross bars, glass and shutters, generated on each wall
wins = []
def window(tag, u, z, loc, rot_z):
    p = []
    zc = z + 0.575
    p.append(B.box(tag + '_glass', (WIN, 0.05, 1.15), loc=(u, 0, zc), material=GLASS))
    for s in (-1, 1):
        p.append(B.box(f'{tag}_fv{s}', (0.12, 0.3, 1.39), loc=(u + s * (WIN / 2 + 0.06), 0, zc), material=TRIM, bevel=0.02, seg=1))
        p.append(B.box(f'{tag}_fh{s}', (WIN + 0.34, 0.34, 0.14), loc=(u, 0, zc + s * 0.645), material=TRIM, bevel=0.02, seg=1))
        p.append(B.box(f'{tag}_shutter{s}', (0.42, 0.07, 1.25), loc=(u + s * (WIN / 2 + 0.36), -T / 2 - 0.04, zc), material=DARKW, bevel=0.015, seg=1))
        for k in (-1, 1):
            p.append(B.box(f'{tag}_batten{s}{k}', (0.42, 0.1, 0.1), loc=(u + s * (WIN / 2 + 0.36), -T / 2 - 0.05, zc + k * 0.4), material=TRIM))
    p.append(B.box(tag + '_bar_v', (0.07, 0.09, 1.15), loc=(u, 0, zc), material=TRIM))
    p.append(B.box(tag + '_bar_h', (WIN, 0.09, 0.07), loc=(u, 0, zc), material=TRIM))
    return B.place(B.join(tag, p), loc, rot_z)
for i, o in enumerate(front_open[1:]):
    wins.append(window(f'win_f{i}', (o[0] + o[1]) / 2, o[2], (0, -hy + T / 2, 0), 0))
for i, o in enumerate(back_open):
    wins.append(window(f'win_b{i}', (o[0] + o[1]) / 2, o[2], (0, hy - T / 2, 0), 180))
for i, o in enumerate(side_open):
    wins.append(window(f'win_e{i}', 0.0, o[2], (hx - T / 2, 0, 0), 90))
    wins.append(window(f'win_w{i}', 0.0, o[2], (-hx + T / 2, 0, 0), -90))
wins = B.join('house_windows', wins)

# roof: two slabs with tile courses, overhanging the gables
roof = []
OV = 0.55
slope = math.atan2(HR - HW, hx)
run = (hx + OV) / math.cos(slope)
for s in (-1, 1):
    mx = s * (hx + OV) / 2
    mz = HW + (HR - HW) * (1 - (hx + OV) / 2 / hx) + 0.14
    roof.append(B.box(f'roof{s}', (run, LY + 1.1, 0.18), loc=(mx, 0, mz), material=ROOF, rot=(0, s * slope, 0)))
    nrm = Vector((s * math.sin(slope), 0, math.cos(slope)))
    for i in range(5):                        # tile courses: thin overlapping slabs
        t = (i + 0.5) / 5
        cx = s * (hx + OV) * (1 - t)
        cz = HW + (HR - HW) * (1 - (hx + OV) * (1 - t) / hx) + 0.14
        roof.append(B.box(f'course{s}{i}', (run / 5 + 0.08, LY + 1.16, 0.09), loc=Vector((cx, 0, cz)) + nrm * (0.11 + 0.0), material=ROOF if i % 2 else ROOF_D,
                          rot=(0, s * (slope - 0.07), 0), bevel=0.02, seg=1))
    for e in (-1, 1):                         # barge boards on the gable edges
        roof.append(B.beam(f'barge{s}{e}', (s * (hx + OV), e * (hy + 0.5), HW - OV * math.tan(slope) + 0.02), (0, e * (hy + 0.5), HR + 0.02), 0.1, 0.3, material=TRIM, bevel=0.02))
roof.append(B.box('ridge', (0.4, LY + 1.2, 0.16), loc=(0, 0, HR + 0.27), material=ROOF_D, bevel=0.04, seg=1))
roof = B.join('house_roof', roof)
roof['smooth_angle'] = 25

# porch: deck, steps, posts and a small tiled roof over the door
porch = [B.box('porch_deck', (3.4, 1.5, 0.3), loc=(0, -hy - 0.75, 0.15), material=WOOD_B, bevel=0.03, seg=1),
         B.box('porch_step1', (2.2, 0.4, 0.2), loc=(0, -hy - 1.7, 0.1), material=TRIM, bevel=0.03, seg=1),
         B.box('porch_step0', (2.6, 0.4, 0.1), loc=(0, -hy - 2.1, 0.05), material=TRIM, bevel=0.02, seg=1)]
for s in (-1, 1):
    porch.append(B.box(f'porch_post{s}', (0.26, 0.26, 2.5), loc=(s * 1.45, -hy - 1.3, 1.55), material=TRIM, bevel=0.03, seg=1))
    porch.append(B.box(f'porch_post_base{s}', (0.4, 0.4, 0.4), loc=(s * 1.45, -hy - 1.3, 0.5), material=TRIM, bevel=0.05, seg=1))
porch.append(B.box('porch_beam', (3.3, 0.24, 0.24), loc=(0, -hy - 1.3, 2.85), material=TRIM, bevel=0.03, seg=1))
porch.append(B.box('porch_roof', (3.9, 2.0, 0.16), loc=(0, -hy - 0.85, 3.2), material=ROOF, rot=(math.radians(18), 0, 0), bevel=0.03, seg=1))
for i in range(3):
    porch.append(B.box(f'porch_course{i}', (3.96, 0.7, 0.08), loc=(0, -hy - 0.22 - i * 0.62, 3.5 - i * 0.2), material=ROOF_D if i % 2 else ROOF, rot=(math.radians(15), 0, 0), bevel=0.02, seg=1))
porch = B.join('house_porch', porch)

# front door (separate, hinged on its left edge) and its frame
dw = DOOR[1] - DOOR[0]
dframe = [B.box('door_frame_top', (dw + 0.5, 0.34, 0.2), loc=(0, -hy + T / 2, DOOR[3] + 0.1), material=TRIM, bevel=0.03, seg=1)]
for s in (-1, 1):
    dframe.append(B.box(f'door_frame{s}', (0.2, 0.34, DOOR[3] - 0.15), loc=(s * (dw / 2 + 0.1), -hy + T / 2, (DOOR[3] + 0.15) / 2), material=TRIM, bevel=0.03, seg=1))
dframe = B.join('house_door_frame', dframe)
door = [B.box('door_leaf', (dw, 0.09, DOOR[3] - 0.15), loc=(0, -hy + T / 2, (DOOR[3] + 0.15) / 2), material=DARKW, bevel=0.02, seg=1)]
for z in (0.55, 1.9):
    door.append(B.box(f'door_batten{z}', (dw - 0.1, 0.13, 0.14), loc=(0, -hy + T / 2, z), material=WOOD_B))
door.append(B.torus('door_ring', 0.07, 0.018, loc=(0.36, -hy + T / 2 - 0.08, 1.2), material=IRON, rot=(math.radians(90), 0, 0), major=10, minor=5))
door = B.join('house_door', door)
B.set_pivot(door, (DOOR[0], -hy + T / 2, 0.15))

# staircase along the east wall, from the ground floor up to the upper floor
stairs = []
NS = 15
rise = (F2 + 0.15 - 0.15) / NS
tread = (SY1 - SY0) / NS
for i in range(NS):
    stairs.append(B.box(f'step{i}', (SX1 - SX0 - 0.05, tread + 0.03, rise * (i + 1)), loc=((SX0 + SX1) / 2, SY0 + tread * (i + 0.5), 0.15 + rise * (i + 1) / 2),
                        material=WOOD_B if i % 2 else TRIM))
stairs.append(B.beam('stair_rail', (SX0 + 0.05, SY0, 1.15), (SX0 + 0.05, SY1, F2 + 1.15), 0.1, 0.1, material=TRIM))
for i in range(0, NS + 1, 3):
    y = SY0 + tread * i
    z = 0.15 + rise * i
    stairs.append(B.box(f'stair_post{i}', (0.09, 0.09, 1.0), loc=(SX0 + 0.05, y, z + 0.5), material=TRIM))
# landing rail around the stair well upstairs
stairs.append(B.box('well_rail', (0.1, SY1 - SY0 - 1.2, 0.1), loc=(SX0 - 0.05, (SY0 + SY1) / 2 - 0.6, F2 + 1.1), material=TRIM))
for y in (SY0, (SY0 + SY1) / 2 - 0.6, SY1 - 1.2):
    stairs.append(B.box(f'well_post{y}', (0.1, 0.1, 1.0), loc=(SX0 - 0.05, y, F2 + 0.65), material=TRIM))
stairs = B.join('house_stairs', stairs)

# chimney on the back-right corner, and simple furniture
chim = [B.box('chimney', (1.0, 0.9, 9.3), loc=(2.6, hy + 0.3, 4.65), material=STONE, bevel=0.05, seg=1),
        B.box('chimney_cap', (1.25, 1.15, 0.35), loc=(2.6, hy + 0.3, 9.45), material=STONE_D, bevel=0.07, seg=1)]
for i in range(9):
    chim.append(B.box(f'chimney_course{i}', (1.06, 0.96, 0.08), loc=(2.6, hy + 0.3, 0.9 + i * 1.0), material=STONE_D))
chim = B.join('house_chimney', chim)
furn = [B.box('table_top', (1.5, 0.9, 0.1), loc=(-1.6, 0.6, 0.95), material=TRIM, bevel=0.02, seg=1),
        B.box('bed_frame', (1.3, 2.1, 0.35), loc=(-2.6, 2.0, F2 + 0.42), material=DARKW, bevel=0.03, seg=1),
        B.box('bed_mattress', (1.15, 1.9, 0.2), loc=(-2.6, 2.0, F2 + 0.68), material=CLOTH, bevel=0.05, seg=2),
        B.box('bed_pillow', (0.8, 0.4, 0.14), loc=(-2.6, 2.7, F2 + 0.84), material=CLOTH, bevel=0.05, seg=2),
        B.box('bed_head', (1.3, 0.1, 0.9), loc=(-2.6, 3.05, F2 + 0.7), material=DARKW, bevel=0.03, seg=1),
        B.box('stool', (0.4, 0.4, 0.45), loc=(-0.4, 0.6, 0.4), material=DARKW, bevel=0.03, seg=1)]
for a in (-1, 1):
    for b in (-1, 1):
        furn.append(B.box(f'table_leg{a}{b}', (0.1, 0.1, 0.78), loc=(-1.6 + a * 0.62, 0.6 + b * 0.33, 0.54), material=DARKW))
furn = B.join('house_furniture', furn)

for o in (shell, trim, wins, roof, porch, dframe, stairs, chim, furn):
    B.set_pivot(o, (0, 0, 0))
OUT = os.environ.get('BR_OUT', HERE)
if os.environ.get('BR_CUT'):                  # inspection only: hide the roof and front to look inside
    for o in (roof, porch, wins, trim):
        bpy.data.objects.remove(o)
    door.rotation_euler.z = math.radians(-100)
B.finish('house', OUT, budget=30000, views=('front', 'side', '3/4', 'back') if not os.environ.get('BR_CUT') else ('3/4', 'top'), aspect=1.25, res=600)
