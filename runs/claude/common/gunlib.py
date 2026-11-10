"""Small helpers for weapon builds. Weapons lie in the YZ plane: barrel to -Y, up +Z, origin at the grip."""
import math
import brlib as B


def P(name, prof, width, material, bevel=0.004, seg=1, x=0.0):
    """Side profile [(y, z), ...] extruded to `width` across X."""
    return B.prism(name, prof, width, loc=(x, 0, 0), material=material, axis='X', bevel=bevel, seg=seg)


def ycyl(name, r, y0, y1, z, material, verts=12, r2=None, x=0.0, bevel=0.0):
    """Cylinder along Y from y0 (front) to y1 (rear). r is the radius at the rear, r2 at the front."""
    o = B.cyl(name, r, abs(y1 - y0), loc=(x, (y0 + y1) / 2, z), material=material, rot=(math.radians(90), 0, 0),
              verts=verts, r2=r2, bevel=bevel, seg=1)
    return o


def bolt(name, y, z, half_width, material, r=0.009):
    """A stud through the body, visible on both sides."""
    return B.cyl(name, r, half_width * 2 + 0.008, loc=(0, y, z), material=material, rot=(0, math.radians(90), 0), verts=6)


def grip(name, material, y=0.0, top=0.02, length=0.11, rake=0.035, depth=0.045, width=0.036):
    """Raked pistol grip hanging below `top`; the origin (0, 0, 0) sits inside it."""
    prof = [(y - depth / 2, top), (y + depth / 2, top), (y + depth / 2 + rake, top - length + 0.008), (y + depth / 2 + rake - 0.008, top - length),
            (y - depth / 2 + rake + 0.004, top - length), (y - depth / 2 + rake - 0.004, top - length + 0.01)]
    return P(name, prof, width, material, bevel=0.007, seg=2)


def guard(name, material, y0, y1, top, drop=0.045, th=0.007, width=0.018):
    """Trigger guard loop from y0 (front) to y1 (rear) hanging below `top`."""
    prof = [(y0, top), (y0 + th, top), (y0 + th, top - drop + th), (y1, top - drop + th), (y1, top - drop), (y0 + 0.006, top - drop), (y0, top - drop + 0.008)]
    return P(name, prof, width, material, bevel=0.002)


def trigger(name, material, y, top):
    return P(name, [(y - 0.004, top), (y + 0.006, top), (y + 0.002, top - 0.014), (y - 0.006, top - 0.03), (y - 0.011, top - 0.028), (y - 0.005, top - 0.012)], 0.008, material, bevel=0.0)
