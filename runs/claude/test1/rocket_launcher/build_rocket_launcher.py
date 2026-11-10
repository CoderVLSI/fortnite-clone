"""Rocket launcher: olive tube, tan flared muzzle and collars, dark sight, fore-grip and shoulder pad.
Barrel to -Y, origin at the pistol grip."""
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'common'))
import bpy
import brlib as B
import gunlib as G

B.reset()
TAN = B.mat('mat_tan', '#c9a05a', rough=0.7)
OLIVE = B.mat('mat_olive', '#5f6b3c', rough=0.75)
OLIVE_D = B.mat('mat_olive_dark', '#4a542f', rough=0.8)
DARK = B.mat('mat_gunmetal', '#3a3c41', rough=0.5, metal=0.5)
BORE = B.mat('mat_bore', '#141518', rough=0.9)
LENS = B.mat('mat_lens', '#e2493a', rough=0.2, emit=0.6)

YM, YB = -0.73, 0.57                           # 1.30 m long
ZA, R = 0.115, 0.08                            # tube axis height and radius (0.16 m diameter)

tube = [G.ycyl('tube', R, YM + 0.2, YB - 0.1, ZA, OLIVE, 16),
        G.ycyl('tube_step', R + 0.006, -0.15, 0.3, ZA, OLIVE, 16, bevel=0.004),
        G.P('grip_block', [(-0.06, 0.04), (0.06, 0.04), (0.05, 0.015), (-0.05, 0.015)], 0.05, OLIVE_D, bevel=0.005),
        G.grip('grip', OLIVE, y=0.012, top=0.02, length=0.12, rake=0.04, depth=0.052, width=0.042)]
tube = B.join('launcher_tube', tube)

ROT = (math.radians(90), 0, 0)
tan = [B.cyl('flare', R + 0.012, 0.13, loc=(0, YM + 0.065, ZA), material=TAN, rot=ROT, verts=12, r2=0.13, caps=False),
       B.cyl('flare_lip', 0.134, 0.016, loc=(0, YM + 0.004, ZA), material=TAN, rot=ROT, verts=12, caps=False),
       G.ycyl('flare_neck', R + 0.012, YM + 0.12, YM + 0.25, ZA, TAN, 12, bevel=0.005),
       G.ycyl('rear_collar', R + 0.014, YB - 0.2, YB - 0.1, ZA, TAN, 12, bevel=0.006),
       G.P('side_plate', [(-0.2, 0.05), (-0.19, 0.11), (-0.12, 0.125), (0.12, 0.125), (0.14, 0.09), (0.14, 0.06), (0.04, 0.04), (-0.04, 0.04)], 2 * R + 0.036, TAN, bevel=0.006)]
tan = B.join('launcher_trim', tan)
tan['keep_normals'] = True

dark = [B.cyl('muzzle_lining', R + 0.004, 0.125, loc=(0, YM + 0.068, ZA), material=BORE, rot=ROT, verts=12, r2=0.122, caps=False),
        G.ycyl('muzzle_back', R + 0.004, YM + 0.128, YM + 0.134, ZA, BORE, 12),
        G.ycyl('front_band', R + 0.012, -0.47, -0.4, ZA, DARK, 12, bevel=0.005),
        G.ycyl('shoulder_stem', R * 0.8, YB - 0.1, YB - 0.04, ZA, DARK, 12),
        G.P('shoulder_pad', [(YB - 0.05, 0.0), (YB - 0.01, -0.02), (YB, 0.0), (YB, 0.19), (YB - 0.02, 0.22), (YB - 0.05, 0.215)], 2 * R + 0.02, DARK, bevel=0.012, seg=2),
        G.P('rear_brace', [(0.3, 0.035), (0.44, 0.035), (0.47, 0.06), (0.44, 0.06), (0.43, 0.05), (0.3, 0.05)], 0.03, DARK, bevel=0.003),
        G.guard('guard', DARK, -0.08, -0.016, 0.02, drop=0.05, th=0.008, width=0.02),
        # vertical fore-grip
        B.cyl('foregrip', 0.026, 0.13, loc=(0, -0.435, -0.03), material=DARK, verts=10, bevel=0.005, seg=1),
        B.cyl('foregrip_cap', 0.031, 0.025, loc=(0, -0.435, -0.095), material=DARK, verts=10, bevel=0.005, seg=1),
        # sight
        B.box('sight_base', (0.05, 0.16, 0.04), loc=(0, -0.02, ZA + R + 0.022), material=DARK, bevel=0.008, seg=1),
        G.P('sight_hood', [(-0.1, ZA + R + 0.03), (-0.045, ZA + R + 0.03), (-0.045, ZA + R + 0.085), (-0.085, ZA + R + 0.085), (-0.1, ZA + R + 0.07)], 0.05, DARK, bevel=0.005)]
for i, (y, z) in enumerate([(-0.435, ZA), (-0.16, 0.1), (0.1, 0.085), (YB - 0.15, ZA)]):
    dark.append(G.bolt(f'bolt{i}', y, z, R + 0.018, DARK, r=0.013))
dark = B.join('launcher_metal', dark)
dark['keep_normals'] = True
lens = B.box('launcher_lens', (0.036, 0.004, 0.03), loc=(0, -0.1, ZA + R + 0.058), material=LENS)

# the loaded rocket, visible in the muzzle; separate so it can be hidden after firing
rocket = [G.ycyl('rocket_body', 0.06, YM + 0.09, YM + 0.3, ZA, OLIVE_D, 12),
          G.ycyl('rocket_nose', 0.06, YM + 0.01, YM + 0.1, ZA, OLIVE, 12, r2=0.006)]
rocket = B.join('launcher_rocket', rocket)

trig = G.trigger('launcher_trigger', DARK, -0.045, 0.02)
B.set_pivot(trig, (0, -0.045, 0.018))
B.set_pivot(rocket, (0, YM + 0.2, ZA))
for o in (tube, tan, dark, lens):
    B.set_pivot(o, (0, 0, 0))
B.finish('rocket_launcher', HERE, budget=8000)
