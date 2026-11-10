"""Farm props: fence segment, barrel and crate. One object each, origin at bottom centre."""
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'common'))
import bpy, bmesh
from mathutils import Vector
import brlib as B

B.reset()
WOOD = B.mat('mat_wood', '#b87530', rough=0.75)
WOOD_L = B.mat('mat_wood_light', '#cc8a38', rough=0.75)
WOOD_D = B.mat('mat_wood_dark', '#8a5622', rough=0.8)
IRON = B.mat('mat_iron', '#4a4d52', rough=0.5, metal=0.6)
RIVET = B.mat('mat_rivet', '#6c7077', rough=0.45, metal=0.6)


def rivet(name, loc, axis, r=0.028):
    rot = {'x': (0, math.radians(90), 0), 'y': (math.radians(90), 0, 0), 'z': (0, 0, 0)}[axis]
    return B.cyl(name, r, 0.03, loc=loc, material=RIVET, rot=rot, verts=6, r2=r * 0.55)

# ------------------------------------------------------------ fence, 2.0 x 1.1 m
def fence():
    parts = []
    for sx in (-1, 1):
        x = sx * 0.91
        parts.append(B.box(f'post{sx}', (0.18, 0.18, 1.02), loc=(x, 0, 0.51), material=WOOD, bevel=0.025, seg=1))
        parts.append(B.cyl(f'post_top{sx}', 0.127, 0.08, loc=(x, 0, 1.06), material=WOOD_L, rot=(0, 0, math.radians(45)), verts=4, r2=0.085))
        for z in (0.36, 0.78):
            parts.append(rivet(f'bolt{sx}{z}', (x, -0.1, z), 'y', 0.032))
            parts.append(rivet(f'boltb{sx}{z}', (x, 0.1, z), 'y', 0.032))
    for z in (0.36, 0.78):
        parts.append(B.box(f'rail{z}', (1.72, 0.07, 0.2), loc=(0, 0, z), material=WOOD_L, bevel=0.018, seg=1))
    return B.join('farm_fence', parts)

# ------------------------------------------------------------ barrel, 0.9 x 0.65 m
def barrel():
    H, Rm, Re = 0.9, 0.325, 0.255
    prof = []
    for i in range(9):
        t = i / 8
        z = t * H
        r = Re + (Rm - Re) * math.sin(math.pi * t) ** 0.8
        prof.append((r - 0.012, z))
    body = B.lathe('barrel_staves', prof, WOOD, seg=14, cap_top=False, cap_bottom=True)
    body['smooth_angle'] = 18
    parts = [body]
    # recessed lid with a rim
    parts.append(B.lathe('barrel_rim', [(Re - 0.012, H), (Re - 0.045, H), (Re - 0.05, H - 0.035), (0.001, H - 0.035)], WOOD_D, seg=14, cap_top=False, cap_bottom=False))
    for k, x in enumerate((-0.07, 0.07)):
        parts.append(B.box(f'lid_gap{k}', (0.012, 0.38 - abs(x), 0.004), loc=(x, 0, H - 0.034), material=WOOD_D))
    def rad(z):
        t = z / H
        return Re + (Rm - Re) * math.sin(math.pi * t) ** 0.8
    for k, z in enumerate((0.13, 0.45, 0.77)):
        hh = 0.045
        parts.append(B.lathe(f'hoop{k}', [(rad(z - hh) - 0.008, z - hh), (rad(z - hh) + 0.008, z - hh), (rad(z + hh) + 0.008, z + hh), (rad(z + hh) - 0.008, z + hh)], IRON, seg=14, cap_top=False, cap_bottom=False))
        for j in range(7):
            a = 2 * math.pi * (j + 0.25) / 7
            rr = rad(z) + 0.012
            o = B.cyl(f'rivet{k}{j}', 0.022, 0.022, loc=(rr * math.cos(a), rr * math.sin(a), z), material=RIVET, rot=(0, math.radians(90), a), verts=6, r2=0.012)
            parts.append(o)
    return B.join('farm_barrel', parts)

# ------------------------------------------------------------ crate, 0.8 m cube
def crate():
    S, T = 0.8, 0.09               # size, frame beam width
    h = S / 2
    parts = [B.box('crate_core', (S - 0.06, S - 0.06, S - 0.06), loc=(0, 0, h), material=WOOD_D)]
    # plank panels on the six sides
    n = 4
    w = (S - 2 * T) / n
    for i in range(n):
        u = -h + T + w * (i + 0.5)
        for s in (-1, 1):
            parts.append(B.box(f'pl_y{s}{i}', (w - 0.012, 0.03, S - 2 * T + 0.02), loc=(u, s * (h - 0.035), h), material=WOOD))
            parts.append(B.box(f'pl_x{s}{i}', (0.03, w - 0.012, S - 2 * T + 0.02), loc=(s * (h - 0.035), u, h), material=WOOD))
        parts.append(B.box(f'pl_top{i}', (w - 0.012, S - 2 * T + 0.02, 0.03), loc=(u, 0, S - 0.035), material=WOOD_L))
    # frame beams along the 12 edges
    for a in (-1, 1):
        for b in (-1, 1):
            parts.append(B.box(f'fr_z{a}{b}', (T, T, S), loc=(a * (h - T / 2), b * (h - T / 2), h), material=WOOD_L, bevel=0.014, seg=1))
            parts.append(B.box(f'fr_x{a}{b}', (S - 2 * T, T, T), loc=(0, a * (h - T / 2), h + b * (h - T / 2)), material=WOOD_L, bevel=0.014, seg=1))
            parts.append(B.box(f'fr_y{a}{b}', (T, S - 2 * T, T), loc=(a * (h - T / 2), 0, h + b * (h - T / 2)), material=WOOD_L, bevel=0.014, seg=1))
    # rivets at the corners of the four walls
    k = 0
    for a in (-1, 1):
        for b in (-1, 1):
            for c in (-1, 1):
                z = h + c * (h - T / 2)
                parts.append(rivet(f'rv_y{k}', (a * (h - T / 2), b * (h + 0.008), z), 'y', 0.024))
                parts.append(rivet(f'rv_x{k}', (b * (h + 0.008), a * (h - T / 2), z), 'x', 0.024))
                k += 1
    return B.join('farm_crate', parts)

f = fence(); f.location.x = -1.75
b = barrel(); b.location.x = 0.0
c = crate(); c.location.x = 1.25
B.finish('farm_props', HERE, budget=6000, views=('front', '3/4', 'back', 'side'), aspect=2.0, res=460)
