"""SMG: compact slate receiver, long straight magazine, short suppressor, folding wire stock. Barrel to -Y, origin at the grip."""
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', '..', 'common'))
import bpy
import brlib as B
import gunlib as G

B.reset()
SLATE = B.mat('mat_slate', '#56606c', rough=0.65)
SLATE_D = B.mat('mat_slate_dark', '#434b55', rough=0.7)
OLIVE = B.mat('mat_olive', '#5d5f45', rough=0.75)
DARK = B.mat('mat_gunmetal', '#3a3c41', rough=0.5, metal=0.5)
BORE = B.mat('mat_bore', '#141518', rough=0.9)
LENS = B.mat('mat_lens', '#3ad1e2', rough=0.2, emit=0.6)

YM = -0.36                                    # suppressor tip; wire stock to +0.2 -> 0.56 m
ZA = 0.07

metal = [G.ycyl('suppressor', 0.026, YM, YM + 0.13, ZA, DARK, 12, bevel=0.004),
         G.ycyl('bore', 0.01, YM - 0.001, YM + 0.004, ZA, BORE, 8),
         G.ycyl('barrel', 0.013, YM + 0.125, -0.16, ZA, DARK, 10),
         B.box('charging', (0.058, 0.03, 0.016), loc=(0, -0.03, 0.105), material=DARK, bevel=0.003, seg=1),
         B.box('rail', (0.026, 0.17, 0.01), loc=(0, -0.045, 0.118), material=DARK, bevel=0.002, seg=1)]
for i in range(4):                             # suppressor rings
    metal.append(G.ycyl(f'supp_ring{i}', 0.028, YM + 0.02 + i * 0.03, YM + 0.028 + i * 0.03, ZA, SLATE_D, 12))
# folding wire stock: two rails and a butt plate
for s in (-1, 1):
    metal.append(B.beam(f'stock_rail{s}', (s * 0.016, 0.07, 0.085), (s * 0.016, 0.2, 0.06), 0.012, material=DARK))
    metal.append(B.beam(f'stock_low{s}', (s * 0.016, 0.07, 0.035), (s * 0.016, 0.2, 0.0), 0.01, material=DARK))
metal.append(G.P('butt_plate', [(0.19, -0.03), (0.21, -0.03), (0.21, 0.085), (0.19, 0.085)], 0.05, DARK, bevel=0.005))
for i, (y, z) in enumerate([(-0.11, 0.075), (0.03, 0.08)]):
    metal.append(G.bolt(f'bolt{i}', y, z, 0.031, DARK))
metal = B.join('smg_metal', metal)

# small red-dot on the rail
sight = [B.box('dot_base', (0.03, 0.06, 0.012), loc=(0, -0.06, 0.128), material=DARK, bevel=0.003, seg=1),
         G.P('dot_hood', [(-0.088, 0.134), (-0.035, 0.134), (-0.035, 0.164), (-0.075, 0.164), (-0.088, 0.152)], 0.034, SLATE_D, bevel=0.004)]
sight = B.join('smg_sight', sight)
lens = B.box('smg_lens', (0.024, 0.004, 0.02), loc=(0, -0.09, 0.15), material=LENS)

body = [G.P('receiver', [(-0.17, 0.02), (0.075, 0.02), (0.075, 0.11), (-0.15, 0.11), (-0.17, 0.095)], 0.056, SLATE, bevel=0.006, seg=2),
        G.P('handguard', [(-0.23, 0.035), (-0.165, 0.035), (-0.165, 0.1), (-0.23, 0.1), (-0.24, 0.09), (-0.24, 0.045)], 0.05, SLATE_D, bevel=0.005),
        G.P('front_grip', [(-0.215, 0.035), (-0.185, 0.035), (-0.18, -0.045), (-0.205, -0.05), (-0.22, -0.045)], 0.03, OLIVE, bevel=0.005),
        G.P('mag_well', [(-0.115, 0.03), (-0.055, 0.03), (-0.055, -0.01), (-0.115, -0.01)], 0.048, SLATE, bevel=0.004),
        G.guard('guard', SLATE_D, -0.03, 0.025, 0.022, drop=0.042)]
body = B.join('smg_body', body)
grip = G.grip('smg_grip', OLIVE, y=0.045, top=0.022, length=0.105, rake=0.035, depth=0.046, width=0.038)
body = B.join('smg_body', [body, grip])

mag = [G.P('smg_magazine', [(-0.112, -0.005), (-0.058, -0.005), (-0.05, -0.19), (-0.104, -0.19)], 0.034, DARK, bevel=0.005, seg=2)]
mag.append(B.box('mag_base', (0.04, 0.066, 0.014), loc=(0, -0.078, -0.196), material=SLATE_D, bevel=0.003, seg=1))
mag = B.join('smg_magazine', mag)

trig = G.trigger('smg_trigger', DARK, 0.0, 0.022)
B.set_pivot(trig, (0, 0.0, 0.02))
B.set_pivot(mag, (0, -0.08, 0.0))
for o in (metal, body, lens, sight):
    B.set_pivot(o, (0, 0, 0))
B.finish('smg', HERE, budget=6000)
