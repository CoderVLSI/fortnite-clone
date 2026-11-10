"""Pistol: tan frame, dark slide. Barrel points to -Y, origin at the grip."""
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'common'))
import bpy, bmesh
from mathutils import Vector
import brlib as B

B.reset()
TAN = B.mat('mat_tan', '#c49a5c', rough=0.7)
TAN_D = B.mat('mat_tan_dark', '#a47c44', rough=0.75)
DARK = B.mat('mat_gunmetal', '#3a3c40', rough=0.5, metal=0.5)
DARK2 = B.mat('mat_gunmetal_light', '#55585d', rough=0.5, metal=0.5)
BORE = B.mat('mat_bore', '#15161a', rough=0.9)

# Layout in the YZ plane (front is -Y). Origin = middle of the grip.
YF, YR = -0.168, 0.072                       # muzzle and rear of slide
ZS0, ZS1 = 0.030, 0.070                      # slide bottom / top

parts = []
# slide: chamfered bar
slide_prof = [(YF, ZS0), (YR, ZS0), (YR, ZS1 - 0.008), (YR - 0.012, ZS1), (YF + 0.012, ZS1), (YF, ZS1 - 0.01)]
parts.append(B.prism('slide', slide_prof, 0.034, material=DARK, axis='X', bevel=0.004, seg=1))
parts.append(B.box('slide_serr', (0.036, 0.03, 0.026), loc=(0, YR - 0.03, ZS0 + 0.02), material=DARK2, bevel=0.003, seg=1))
parts.append(B.cyl('muzzle', 0.013, 0.014, loc=(0, YF - 0.005, ZS0 + 0.021), material=DARK2, rot=(math.radians(90), 0, 0), verts=12, bevel=0.002, seg=1))
parts.append(B.cyl('bore', 0.0075, 0.004, loc=(0, YF - 0.0105, ZS0 + 0.021), material=BORE, rot=(math.radians(90), 0, 0), verts=10))
parts.append(B.prism('sight_front', [(YF + 0.014, ZS1), (YF + 0.03, ZS1), (YF + 0.026, ZS1 + 0.012), (YF + 0.018, ZS1 + 0.012)], 0.008, material=DARK, axis='X'))
for s in (-1, 1):
    parts.append(B.box(f'sight_rear{s}', (0.008, 0.014, 0.012), loc=(s * 0.009, YR - 0.02, ZS1 + 0.006), material=DARK, bevel=0.002, seg=1))
slide = B.join('pistol_slide', parts)

parts = []
# frame: dust cover under the slide
parts.append(B.prism('frame_top', [(YF + 0.012, ZS0), (YR, ZS0), (YR + 0.006, ZS0 - 0.012), (YR - 0.005, ZS0 - 0.03), (YF + 0.075, ZS0 - 0.03), (YF + 0.068, ZS0 - 0.024), (YF + 0.016, ZS0 - 0.024)],
                     0.03, material=TAN, axis='X', bevel=0.004, seg=1))
for i in range(3):                            # rail notches
    parts.append(B.box(f'rail{i}', (0.032, 0.008, 0.006), loc=(0, YF + 0.03 + i * 0.014, ZS0 - 0.026), material=TAN_D))
# grip: raked back, with a chamfered heel
grip = [(-0.024, 0.006), (0.034, 0.012), (0.066, -0.076), (0.06, -0.086), (0.004, -0.086), (-0.002, -0.078)]
parts.append(B.prism('grip', grip, 0.032, material=TAN, axis='X', bevel=0.006, seg=2))
parts.append(B.prism('grip_panel', [(-0.008, -0.004), (0.03, -0.002), (0.054, -0.068), (0.012, -0.068)], 0.036, material=TAN_D, axis='X', bevel=0.003, seg=1))
# trigger guard: a bent strip
parts.append(B.prism('guard', [(-0.084, 0.002), (-0.068, 0.002), (-0.062, -0.03), (-0.004, -0.03), (-0.004, -0.044), (-0.07, -0.044), (-0.082, -0.036)], 0.024, material=TAN, axis='X', bevel=0.004, seg=1))
parts.append(B.prism('mag_plate', [(0.0, -0.086), (0.064, -0.086), (0.068, -0.096), (0.004, -0.096)], 0.034, material=DARK, axis='X', bevel=0.003, seg=1))
parts.append(B.box('slide_stop', (0.038, 0.034, 0.007), loc=(0, -0.022, ZS0 - 0.006), material=DARK2, bevel=0.002, seg=1))
parts.append(B.box('mag_release', (0.038, 0.012, 0.012), loc=(0, -0.012, -0.018), material=DARK2, bevel=0.003, seg=1))
frame = B.join('pistol_frame', parts)

trigger = B.prism('pistol_trigger', [(-0.04, 0.0), (-0.03, 0.0), (-0.034, -0.014), (-0.042, -0.028), (-0.047, -0.026), (-0.041, -0.012)], 0.008, material=DARK, axis='X')
B.set_pivot(trigger, (0, -0.035, 0.0))
B.set_pivot(slide, (0, 0, 0))
B.set_pivot(frame, (0, 0, 0))
B.finish('pistol', HERE, budget=3000)
