"""Pump shotgun: tan receiver and stock, olive pump and grip, dark barrels. Barrel to -Y, origin at the grip."""
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

YM = -0.60                                    # muzzle; butt ends at +0.35 -> 0.95 m long
ZB, ZT = 0.085, 0.042                         # barrel and magazine tube heights

metal = [G.ycyl('barrel', 0.021, YM, -0.14, ZB, DARK, 12, bevel=0.003),
         G.ycyl('mag_tube', 0.018, YM + 0.045, -0.14, ZT, DARK, 12, bevel=0.003),
         G.ycyl('bore', 0.014, YM - 0.001, YM + 0.004, ZB, BORE, 10),
         G.ycyl('tube_cap', 0.012, YM + 0.044, YM + 0.049, ZT, BORE, 10),
         B.box('port', (0.064, 0.13, 0.03), loc=(0, -0.04, 0.078), material=DARK, bevel=0.005, seg=1),
         G.P('stock_band', [(0.118, 0.012), (0.138, 0.012), (0.146, 0.11), (0.126, 0.112)], 0.062, DARK, bevel=0.004),
         G.P('butt_pad', [(0.325, -0.075), (0.35, -0.07), (0.35, 0.062), (0.325, 0.07)], 0.05, DARK, bevel=0.006),
         B.box('bead', (0.008, 0.012, 0.01), loc=(0, YM + 0.02, ZB + 0.024), material=DARK)]
metal = B.join('shotgun_barrels', metal)

body = [G.P('receiver', [(-0.145, 0.02), (0.125, 0.02), (0.125, 0.095), (0.1, 0.112), (-0.13, 0.112), (-0.145, 0.1)], 0.056, TAN, bevel=0.007, seg=2),
        B.box('barrel_band', (0.062, 0.055, 0.098), loc=(0, YM + 0.11, 0.063), material=TAN, bevel=0.009, seg=1),
        G.P('stock', [(0.135, 0.015), (0.135, 0.105), (0.19, 0.088), (0.23, 0.07), (0.325, 0.072), (0.325, -0.078), (0.26, -0.06), (0.19, -0.02)], 0.048, TAN, bevel=0.009, seg=2),
        G.guard('guard', TAN_D, -0.085, -0.02, 0.022, drop=0.046),
        G.grip('grip', OLIVE, y=0.005, top=0.022, length=0.12, rake=0.04, depth=0.05, width=0.04)]
body = B.join('shotgun_body', body)

pump = [B.box('pump_body', (0.07, 0.21, 0.066), loc=(0, -0.36, ZT + 0.004), material=OLIVE, bevel=0.012, seg=2)]
for i in range(5):
    pump.append(B.box(f'pump_rib{i}', (0.076, 0.012, 0.04), loc=(0, -0.43 + i * 0.035, ZT + 0.002), material=OLIVE_D, bevel=0.003, seg=1))
pump = B.join('shotgun_pump', pump)            # slides along Y

trig = G.trigger('shotgun_trigger', DARK, -0.04, 0.022)
B.set_pivot(trig, (0, -0.04, 0.02))
for o in (metal, body, pump, trig):          # chunkier cross-section, same length
    B.apply_mods(o)
    o.scale = (1.2, 1.0, 1.2)
    o.location = (o.location.x * 1.2, o.location.y, o.location.z * 1.2)
for o in (metal, body, pump):
    B.set_pivot(o, (0, 0, 0))
B.set_pivot(trig, (0, -0.04, 0.024))
B.finish('shotgun', HERE, budget=6000, aspect=1.0)
