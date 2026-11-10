"""Modular building kit: wall, floor, ramp and pyramid roof in wood, brick and metal (12 pieces).
Every piece fits a 4 x 4 m cell and has its origin at the bottom centre of that cell
(walls: bottom centre of the wall itself)."""
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'common'))
import bpy, bmesh
from mathutils import Vector, Matrix
import brlib as B

B.reset()
M = {
    'wood': dict(frame=B.mat('mat_wood_frame', '#c98a35', rough=0.75), fill=B.mat('mat_wood_plank', '#b87a2c', rough=0.75),
                 fill2=B.mat('mat_wood_plank_light', '#d29a44', rough=0.75)),
    'brick': dict(frame=B.mat('mat_stone_frame', '#b3a696', rough=0.8), fill=B.mat('mat_mortar', '#c9bba6', rough=0.85),
                  fill2=B.mat('mat_brick', '#c4543c', rough=0.8)),
    'metal': dict(frame=B.mat('mat_steel_frame', '#55585e', rough=0.5, metal=0.6), fill=B.mat('mat_steel_sheet', '#8a909a', rough=0.45, metal=0.6),
                  fill2=B.mat('mat_steel_sheet_dark', '#6f7580', rough=0.45, metal=0.6)),
}
RIVET = B.mat('mat_rivet', '#4a4d52', rough=0.45, metal=0.6)
T, FW = 0.25, 0.36                        # piece thickness, frame beam width


def panel(kind, U, V, tag):
    """Framed panel in the XZ plane: x in [-U/2, U/2], z in [0, V], thickness T along Y."""
    m = M[kind]
    parts = []
    iu, iv = U - 2 * FW, V - 2 * FW
    if kind == 'wood':
        n = max(3, round(iv / 0.66))
        for i in range(n):
            parts.append(B.box(f'{tag}_plank{i}', (iu + 0.04, T * 0.62, iv / n - 0.03), loc=(0, 0, FW + iv / n * (i + 0.5)),
                               material=m['fill'] if i % 2 else m['fill2'], bevel=0.02, seg=1))
    elif kind == 'brick':
        parts.append(B.box(f'{tag}_mortar', (iu + 0.04, T * 0.5, iv + 0.04), loc=(0, 0, V / 2), material=m['fill']))
        rows = max(4, round(iv / 0.55))
        bh = iv / rows
        for r in range(rows):
            cols = 3 if r % 2 == 0 else 4
            edges = [(-iu / 2 + iu * c / 3) for c in range(4)] if r % 2 == 0 else [-iu / 2, -iu / 3, 0, iu / 3, iu / 2]
            for c in range(len(edges) - 1):
                x0, x1 = edges[c], edges[c + 1]
                parts.append(B.box(f'{tag}_brick{r}_{c}', (x1 - x0 - 0.06, T * 0.68, bh - 0.06), loc=((x0 + x1) / 2, 0, FW + bh * (r + 0.5)),
                                   material=m['fill2'], bevel=0.02, seg=1))
    else:                                   # corrugated sheet
        n = 9
        w = iu / n
        prof = []
        for i in range(n):
            x0 = -iu / 2 + i * w
            prof += [(x0, 0.03), (x0 + w * 0.5, 0.075)]
        prof.append((iu / 2, 0.03))
        back = [(x, -y) for x, y in reversed(prof)]
        parts.append(B.prism(f'{tag}_sheet', prof + back, iv + 0.04, loc=(0, 0, V / 2), material=m['fill'], axis='Z'))
    # frame beams and corner blocks with rivets on both faces
    for s in (-1, 1):
        parts.append(B.box(f'{tag}_fr_v{s}', (FW, T, V - 2 * FW), loc=(s * (U / 2 - FW / 2), 0, V / 2), material=m['frame'], bevel=0.03, seg=1))
        parts.append(B.box(f'{tag}_fr_h{s}', (U - 2 * FW, T, FW), loc=(0, 0, V / 2 + s * (V / 2 - FW / 2)), material=m['frame'], bevel=0.03, seg=1))
        for t in (-1, 1):
            cx, cz = s * (U / 2 - FW / 2), V / 2 + t * (V / 2 - FW / 2)
            parts.append(B.box(f'{tag}_corner{s}{t}', (FW, T + 0.03, FW), loc=(cx, 0, cz), material=m['frame'], bevel=0.035, seg=1))
            for f in (-1, 1):
                parts.append(B.cyl(f'{tag}_rv{s}{t}{f}', 0.07, 0.04, loc=(cx, f * (T / 2 + 0.02), cz), material=RIVET,
                                   rot=(math.radians(90 * f), 0, 0), verts=8, r2=0.04))
    return B.join(tag, parts)


def wall(kind):
    return panel(kind, 4.0, 4.0, f'kit_wall_{kind}')


def floor(kind):
    o = panel(kind, 4.0, 4.0, f'kit_floor_{kind}')
    # lay flat: z -> y, thickness -> z, resting on z = 0
    return B.xform(o, Matrix.Translation((0, -2.0, T / 2)) @ Matrix.Rotation(math.radians(-90), 4, 'X'))


def ramp(kind):
    L = math.sqrt(32)
    o = panel(kind, 4.0, L, f'kit_ramp_{kind}')
    # tilt 45 degrees: low edge at the front (-Y), high edge at the back, rising 4 m over 4 m
    B.xform(o, Matrix.Translation((0, -2.0, 0.13)) @ Matrix.Rotation(math.radians(-45), 4, 'X'))
    m = M[kind]
    extra = []
    for s in (-1, 1):
        x = s * (2.0 - FW / 2)
        extra.append(B.box(f'kit_ramp_{kind}_post{s}', (FW, T, 4.0 - 0.3), loc=(x, 2.0 - T / 2, (4.0 - 0.3) / 2), material=m['frame'], bevel=0.03, seg=1))
        extra.append(B.box(f'kit_ramp_{kind}_base{s}', (FW, 4.0 - 0.3, T), loc=(x, 0.1, T / 2), material=m['frame'], bevel=0.03, seg=1))
    return B.join(f'kit_ramp_{kind}', [o] + extra)


def cone(kind):
    m = M[kind]
    tag = f'kit_cone_{kind}'
    H, hb = 2.0, 0.22
    parts = []
    for s in (-1, 1):
        parts.append(B.box(f'{tag}_bx{s}', (4.0 - 2 * FW, FW, hb), loc=(0, s * (2 - FW / 2), hb / 2), material=m['frame'], bevel=0.03, seg=1))
        parts.append(B.box(f'{tag}_by{s}', (FW, 4.0 - 2 * FW, hb), loc=(s * (2 - FW / 2), 0, hb / 2), material=m['frame'], bevel=0.03, seg=1))
        for t in (-1, 1):
            parts.append(B.box(f'{tag}_corner{s}{t}', (FW + 0.03, FW + 0.03, hb + 0.04), loc=(s * (2 - FW / 2), t * (2 - FW / 2), hb / 2 + 0.02), material=m['frame'], bevel=0.035, seg=1))
            parts.append(B.cyl(f'{tag}_rv{s}{t}', 0.07, 0.04, loc=(s * (2 - FW / 2), t * (2 - FW / 2), hb + 0.05), material=RIVET, verts=8, r2=0.04))
            # hip beams from each corner to the apex
            parts.append(B.beam(f'{tag}_hip{s}{t}', (s * 1.75, t * 1.75, hb), (s * 0.12, t * 0.12, H - 0.08), 0.2, 0.16, material=m['frame'], bevel=0.02))
    # pyramid skin
    bm = bmesh.new()
    r = 1.82
    base = [bm.verts.new((x * r, y * r, hb - 0.02)) for x, y in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    apex = bm.verts.new((0, 0, H - 0.1))
    for i in range(4):
        bm.faces.new((base[i], base[(i + 1) % 4], apex))
    bm.faces.new(list(reversed(base)))
    parts.append(B.obj_from_bm(f'{tag}_skin', bm, m['fill2'] if kind == 'brick' else m['fill']))
    # course lines on each face
    for k in range(1, 4):
        f = k / 4
        z = hb + (H - 0.1 - hb) * f
        half = r * (1 - f) + 0.015
        for s in (-1, 1):
            parts.append(B.box(f'{tag}_cx{k}{s}', (2 * half, 0.05, 0.05), loc=(0, s * half, z), material=m['fill'] if kind == 'brick' else m['fill2']))
            parts.append(B.box(f'{tag}_cy{k}{s}', (0.05, 2 * half, 0.05), loc=(s * half, 0, z), material=m['fill'] if kind == 'brick' else m['fill2']))
    parts.append(B.box(f'{tag}_cap', (0.36, 0.36, 0.22), loc=(0, 0, H - 0.11), material=m['frame'], bevel=0.04, seg=1))
    return B.join(tag, parts)

for row, kind in enumerate(('wood', 'brick', 'metal')):
    for col, fn in enumerate((wall, floor, ramp, cone)):
        o = fn(kind)
        o['smooth_angle'] = 30
        o['grad_lo'] = 0.86
        B.set_pivot(o, (0, 0, 0))
        o.location = (col * 5.6 - 8.4, -row * 6.5 + 6.5, 0)
B.finish('modular_kit', HERE, budget=2500 * 12, views=('3/4', 'front', 'top', '3/4 back'), aspect=1.5, res=620)
