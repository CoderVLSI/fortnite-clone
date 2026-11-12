"""Burst rifle: light grey modern body with olive furniture, carry-handle optic with a blue lens, curved magazine. Barrel to -Y, origin at the grip."""
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', '..', 'common'))
import bpy
import brlib as B
import gunlib as G

B.reset()
GREY = B.mat('mat_grey', '#c8c8c0', rough=0.6)
GREY_D = B.mat('mat_grey_dark', '#9c9c94', rough=0.65)
OLIVE = B.mat('mat_olive', '#5d5f45', rough=0.75)
OLIVE_D = B.mat('mat_olive_dark', '#484a35', rough=0.8)
DARK = B.mat('mat_gunmetal', '#3a3c41', rough=0.5, metal=0.5)
BORE = B.mat('mat_bore', '#141518', rough=0.9)
LENS = B.mat('mat_lens', '#2f7fe0', rough=0.15, emit=0.5)

YM = -0.5                                     # muzzle; butt at +0.32 -> 0.82 m
ZA = 0.07

metal = [G.ycyl('muzzle_brake', 0.022, YM, YM + 0.06, ZA, DARK, 8, bevel=0.004),
         G.ycyl('bore', 0.011, YM - 0.001, YM + 0.004, ZA, BORE, 8),
         G.ycyl('barrel', 0.014, YM + 0.055, -0.33, ZA, DARK, 10),
         B.box('selector', (0.06, 0.026, 0.01), loc=(0, 0.03, 0.04), material=DARK, bevel=0.002, seg=1),
         G.P('butt_pad', [(0.3, -0.06), (0.322, -0.055), (0.322, 0.1), (0.3, 0.104)], 0.048, DARK, bevel=0.005)]
for i in range(3):                             # three brake ports: one per round of the burst
    metal.append(B.box(f'port{i}', (0.046, 0.012, 0.03), loc=(0, YM + 0.012 + i * 0.016, ZA + 0.01), material=BORE))
for i, (y, z) in enumerate([(-0.15, 0.06), (0.08, 0.08)]):
    metal.append(G.bolt(f'bolt{i}', y, z, 0.029, DARK))
metal = B.join('burst_metal', metal)

body = [G.P('handguard', [(-0.36, 0.028), (-0.15, 0.028), (-0.15, 0.112), (-0.34, 0.112), (-0.36, 0.1)], 0.054, GREY, bevel=0.008, seg=2),
        G.P('receiver', [(-0.16, 0.018), (0.12, 0.018), (0.12, 0.112), (-0.16, 0.112)], 0.056, GREY, bevel=0.006, seg=2),
        G.P('mag_well', [(-0.15, 0.03), (-0.06, 0.03), (-0.06, -0.012), (-0.15, -0.012)], 0.05, GREY_D, bevel=0.004),
        G.P('stock', [(0.12, 0.03), (0.3, 0.04), (0.3, 0.104), (0.12, 0.11)], 0.05, GREY, bevel=0.008, seg=2),
        G.P('stock_low', [(0.2, 0.03), (0.3, -0.058), (0.3, 0.04)], 0.044, GREY_D, bevel=0.006),
        G.guard('guard', GREY_D, -0.06, -0.012, 0.02, drop=0.044)]
for i in range(4):                             # handguard vents
    body.append(B.box(f'vent{i}', (0.058, 0.03, 0.012), loc=(0, -0.33 + i * 0.045, 0.088), material=GREY_D, bevel=0.002, seg=1))
body = B.join('burst_body', body)
grip = G.grip('burst_grip', OLIVE, y=0.015, top=0.02, length=0.11, rake=0.038, depth=0.048, width=0.04)
fgrip = G.P('burst_foregrip', [(-0.29, 0.03), (-0.25, 0.03), (-0.245, -0.05), (-0.285, -0.055)], 0.032, OLIVE, bevel=0.006)
body = B.join('burst_body', [body, grip, fgrip])

# carry handle with a built-in optic
optic = [G.P('handle', [(-0.12, 0.112), (0.06, 0.112), (0.06, 0.15), (-0.12, 0.15)], 0.03, GREY_D, bevel=0.005),
         G.ycyl('optic_tube', 0.024, -0.11, 0.05, 0.168, DARK, 12),
         G.ycyl('optic_hood', 0.03, -0.14, -0.105, 0.168, DARK, 12, bevel=0.003)]
optic = B.join('burst_optic', optic)
lens = G.ycyl('burst_lens', 0.024, -0.143, -0.139, 0.168, LENS, 12)

mag = [G.P('burst_magazine', [(-0.148, -0.005), (-0.07, -0.005), (-0.05, -0.12), (-0.06, -0.135), (-0.13, -0.13), (-0.14, -0.12)], 0.038, OLIVE, bevel=0.006, seg=2)]
mag = B.join('burst_magazine', mag)

trig = G.trigger('burst_trigger', DARK, -0.03, 0.02)
B.set_pivot(trig, (0, -0.03, 0.018))
B.set_pivot(mag, (0, -0.105, 0.0))
for o in (metal, body, optic, lens):
    B.set_pivot(o, (0, 0, 0))
B.finish('burst_rifle', HERE, budget=7000)
