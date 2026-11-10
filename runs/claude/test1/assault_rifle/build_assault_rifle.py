"""Assault rifle: tan body and stock, olive magazine and grip, dark sight and muzzle. Barrel to -Y, origin at the grip."""
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'common'))
import bpy
import brlib as B
import gunlib as G

B.reset()
TAN = B.mat('mat_tan', '#c9a05a', rough=0.7)
TAN_D = B.mat('mat_tan_dark', '#a88244', rough=0.75)
OLIVE = B.mat('mat_olive', '#5d5f45', rough=0.75)
OLIVE_D = B.mat('mat_olive_dark', '#484a35', rough=0.8)
DARK = B.mat('mat_gunmetal', '#3a3c41', rough=0.5, metal=0.5)
BORE = B.mat('mat_bore', '#141518', rough=0.9)
LENS = B.mat('mat_lens', '#e2493a', rough=0.2, emit=0.6)

YM = -0.52                                    # muzzle; butt at +0.33 -> 0.85 m long
ZA = 0.068                                    # bore axis

metal = [G.ycyl('flash_hider', 0.024, YM, YM + 0.075, ZA, DARK, 10, bevel=0.004),
         G.ycyl('bore', 0.011, YM - 0.001, YM + 0.004, ZA, BORE, 8),
         G.ycyl('barrel', 0.014, YM + 0.07, -0.36, ZA, DARK, 10),
         G.ycyl('handguard_cap', 0.034, -0.405, -0.385, ZA, DARK, 8, bevel=0.004),
         G.P('front_sight', [(-0.385, 0.108), (-0.345, 0.108), (-0.352, 0.138), (-0.378, 0.138)], 0.026, DARK, bevel=0.003),
         G.ycyl('buffer_tube', 0.022, 0.12, 0.175, ZA + 0.006, DARK, 10),
         G.P('butt_pad', [(0.31, -0.07), (0.33, -0.064), (0.33, 0.1), (0.31, 0.106)], 0.046, DARK, bevel=0.005),
         B.box('charging', (0.058, 0.012, 0.03), loc=(0, -0.045, 0.062), material=DARK, bevel=0.003, seg=1),
         B.box('bolt_catch', (0.058, 0.04, 0.01), loc=(0, -0.06, 0.046), material=DARK, bevel=0.003, seg=1),
         B.box('selector', (0.058, 0.03, 0.008), loc=(0, 0.03, 0.036), material=DARK, bevel=0.002, seg=1)]
for i, (y, z) in enumerate([(-0.175, 0.09), (-0.175, 0.05), (0.095, 0.085), (0.21, 0.035), (0.285, -0.045)]):
    metal.append(G.bolt(f'bolt{i}', y, z, 0.027 if i < 3 else 0.022, DARK))
for i in range(3):                             # flash hider slots
    metal.append(B.box(f'slot{i}', (0.052, 0.03, 0.008), loc=(0, YM + 0.035, ZA - 0.011 + i * 0.011), material=BORE))
# red-dot sight on the top rail
metal.append(B.box('sight_base', (0.034, 0.1, 0.014), loc=(0, -0.01, 0.119), material=DARK, bevel=0.003, seg=1))
metal.append(G.P('sight_hood', [(-0.058, 0.126), (0.0, 0.126), (0.0, 0.16), (-0.04, 0.16), (-0.058, 0.148)], 0.04, DARK, bevel=0.004))
metal.append(B.box('sight_rear', (0.036, 0.04, 0.02), loc=(0, 0.022, 0.135), material=DARK, bevel=0.004, seg=1))
metal = B.join('rifle_metal', metal)
lens = B.box('rifle_lens', (0.028, 0.004, 0.022), loc=(0, -0.058, 0.142), material=LENS)

body = [G.ycyl('handguard', 0.047, -0.39, -0.15, ZA, TAN, 8, bevel=0.005),
        G.P('receiver', [(-0.16, 0.02), (0.12, 0.02), (0.12, 0.1), (0.105, 0.112), (-0.14, 0.112), (-0.16, 0.098)], 0.05, TAN, bevel=0.006, seg=2),
        G.P('mag_well', [(-0.17, 0.045), (-0.065, 0.045), (-0.065, -0.012), (-0.16, -0.012), (-0.17, 0.0)], 0.054, TAN, bevel=0.005),
        G.guard('guard', TAN_D, -0.065, -0.015, 0.022, drop=0.044),
        # skeleton stock: top bar, diagonal strut, butt
        G.P('stock_top', [(0.165, 0.045), (0.31, 0.045), (0.31, 0.104), (0.18, 0.104), (0.165, 0.092)], 0.042, TAN, bevel=0.006),
        G.P('stock_butt', [(0.27, -0.068), (0.31, -0.068), (0.31, 0.05), (0.27, 0.05)], 0.04, TAN, bevel=0.006),
        G.P('stock_strut', [(0.185, 0.05), (0.215, 0.05), (0.285, -0.045), (0.27, -0.066), (0.255, -0.05)], 0.036, TAN, bevel=0.005)]
body = B.join('rifle_body', body)

mag = [G.P('mag', [(-0.158, -0.005), (-0.075, -0.005), (-0.065, -0.118), (-0.07, -0.126), (-0.142, -0.126), (-0.15, -0.118)], 0.04, OLIVE, bevel=0.006, seg=2)]
for i in range(2):
    mag.append(B.box(f'mag_rib{i}', (0.045, 0.07, 0.008), loc=(0, -0.11 + 0.002 * i, -0.045 - i * 0.04), material=OLIVE_D, bevel=0.002, seg=1))
mag = B.join('rifle_magazine', mag)            # separate so it can drop on reload
grip = G.grip('rifle_grip', OLIVE, y=0.012, top=0.022, length=0.112, rake=0.038, depth=0.05, width=0.04)
body = B.join('rifle_body', [body, grip])

trig = G.trigger('rifle_trigger', DARK, -0.035, 0.022)
B.set_pivot(trig, (0, -0.035, 0.02))
B.set_pivot(mag, (0, -0.11, 0.0))
for o in (metal, body, lens):
    B.set_pivot(o, (0, 0, 0))
B.finish('assault_rifle', HERE, budget=8000)
