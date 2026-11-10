"""Medkit: tan case with a hinged lid, red cross, latches and handle, plus a bandage roll."""
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'common'))
import bpy, bmesh
from mathutils import Vector
import brlib as B

B.reset()
TAN = B.mat('mat_tan', '#d9c3a0', rough=0.7)
TAN_L = B.mat('mat_tan_light', '#e6d4b6', rough=0.7)
TAN_D = B.mat('mat_tan_dark', '#b09a78', rough=0.75)
RED = B.mat('mat_red', '#d8382c', rough=0.6)
DARK = B.mat('mat_dark_plastic', '#3d4045', rough=0.6)
BAND = B.mat('mat_bandage', '#e3cfae', rough=0.85)
BAND_D = B.mat('mat_bandage_dark', '#c2ab86', rough=0.85)

W, D, HB, HL = 0.45, 0.30, 0.085, 0.065

# ---- base
parts = [B.tub('base_shell', (W - 0.016, D - 0.016, HB), 0.016, HB - 0.02, material=TAN, inner=TAN_D, bevel=0.012, seg=2)]
for s in (-1, 1):
    parts.append(B.box(f'rim_x{s}', (W, 0.026, 0.018), loc=(0, s * (D / 2 - 0.013), HB - 0.012), material=TAN_L, bevel=0.005, seg=1))
    parts.append(B.box(f'rim_y{s}', (0.026, D - 0.052, 0.018), loc=(s * (W / 2 - 0.013), 0, HB - 0.012), material=TAN_L, bevel=0.005, seg=1))
    for t in (-1, 1):
        parts.append(B.box(f'foot{s}{t}', (0.09, 0.07, 0.022), loc=(s * (W / 2 - 0.06), t * (D / 2 - 0.05), 0.011), material=TAN_D, bevel=0.007, seg=1))
    parts.append(B.box(f'latch_base{s}', (0.06, 0.014, 0.035), loc=(s * 0.145, -(D / 2 + 0.001), HB - 0.035), material=DARK, bevel=0.004, seg=1))
    parts.append(B.box(f'hinge_low{s}', (0.06, 0.012, 0.03), loc=(s * 0.145, D / 2 + 0.001, HB - 0.028), material=DARK, bevel=0.004, seg=1))
# carry handle on the front
hz = HB - 0.045
parts.append(B.tube('handle', [(-0.085, -D / 2, hz + 0.02), (-0.085, -D / 2 - 0.03, hz + 0.014), (-0.07, -D / 2 - 0.035, hz - 0.012),
                               (0.07, -D / 2 - 0.035, hz - 0.012), (0.085, -D / 2 - 0.03, hz + 0.014), (0.085, -D / 2, hz + 0.02)], 0.011, DARK, verts=8))
base = B.join('medkit_base', parts)
base['keep_normals'] = True

# ---- lid
lid = [B.tub('lid_shell', (W - 0.016, D - 0.016, HL), 0.016, HL - 0.02, material=TAN, inner=TAN_D)]
lid[0].rotation_euler = (math.radians(180), 0, 0)
lid[0].location = (0, 0, HB + HL)
B.add_bevel(lid[0], 0.012, 2)
for s in (-1, 1):
    lid.append(B.box(f'lrim_x{s}', (W, 0.026, 0.018), loc=(0, s * (D / 2 - 0.013), HB + 0.012), material=TAN_L, bevel=0.005, seg=1))
    lid.append(B.box(f'lrim_y{s}', (0.026, D - 0.052, 0.018), loc=(s * (W / 2 - 0.013), 0, HB + 0.012), material=TAN_L, bevel=0.005, seg=1))
    lid.append(B.box(f'strap{s}', (0.055, D - 0.03, 0.014), loc=(s * 0.165, 0, HB + HL + 0.001), material=TAN_L, bevel=0.005, seg=1))
    lid.append(B.box(f'latch{s}', (0.052, 0.018, 0.06), loc=(s * 0.145, -(D / 2 + 0.006), HB + 0.012), material=DARK, bevel=0.005, seg=1))
    lid.append(B.box(f'hinge_up{s}', (0.06, 0.012, 0.03), loc=(s * 0.145, D / 2 + 0.001, HB + 0.022), material=DARK, bevel=0.004, seg=1))
a, b = 0.021, 0.065                      # one 12-sided cross, so the bars cannot fight each other
cross = [(-a, -b), (a, -b), (a, -a), (b, -a), (b, a), (a, a), (a, b), (-a, b), (-a, a), (-b, a), (-b, -a), (-a, -a)]
lid.append(B.prism('cross', cross, 0.008, loc=(0, 0, HB + HL + 0.002), material=RED, axis='Z'))
lid = B.join('medkit_lid', lid)
lid['keep_normals'] = True
B.set_pivot(lid, (0, D / 2 + 0.006, HB))

# ---- bandage roll: 0.08 m diameter, 0.10 m tall, standing next to the case
R, H = 0.04, 0.10
prof = [(R - 0.004, 0), (R, 0.006), (R, H - 0.006), (R - 0.004, H)]
rr = R - 0.004
while rr > 0.008:                          # spiral rings on the end
    prof += [(rr - 0.003, H - 0.004), (rr - 0.007, H)]
    rr -= 0.007
prof.append((0.001, H - 0.003))
roll = [B.lathe('roll_body', prof, BAND, seg=14, cap_top=False, cap_bottom=True)]
roll.append(B.box('roll_flap', (0.004, 0.03, H * 0.9), loc=(0, -R - 0.001, H / 2), material=BAND_D))
roll.append(B.box('roll_clip', (0.03, 0.006, 0.012), loc=(0.008, -R - 0.003, H * 0.5), material=DARK, bevel=0.002, seg=1))
roll = B.join('medkit_bandage', roll)
roll['smooth_angle'] = 50
B.set_pivot(roll, (0, 0, 0))
roll.location = (W / 2 + 0.07, -0.06, 0)

B.finish('medkit', HERE, budget=4000)
