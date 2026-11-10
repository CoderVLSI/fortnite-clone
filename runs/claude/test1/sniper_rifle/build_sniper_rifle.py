"""Bolt-action sniper rifle with scope and folded bipod. Barrel to -Y, origin at the grip."""
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
LENS = B.mat('mat_lens', '#1b2a3d', rough=0.1, metal=0.3)

YM, YB = -0.86, 0.39                           # 1.25 m long
ZA = 0.07

metal = [G.ycyl('brake', 0.028, YM, YM + 0.1, ZA, DARK, 10, bevel=0.005),
         G.ycyl('bore', 0.012, YM - 0.001, YM + 0.004, ZA, BORE, 8),
         G.ycyl('barrel', 0.017, YM + 0.095, -0.5, ZA, DARK, 10),
         G.P('action', [(-0.2, 0.09), (0.1, 0.09), (0.1, 0.108), (-0.2, 0.108)], 0.044, DARK, bevel=0.004),
         G.P('butt_pad', [(YB - 0.025, -0.07), (YB, -0.064), (YB, 0.096), (YB - 0.025, 0.102)], 0.05, DARK, bevel=0.006),
         G.guard('guard', TAN_D, -0.07, -0.015, 0.022, drop=0.044)]
for i in range(2):
    metal.append(B.box(f'brake_port{i}', (0.06, 0.022, 0.022), loc=(0, YM + 0.03 + i * 0.036, ZA), material=BORE))
# bolt handle on the right side
metal.append(B.tube('bolt_arm', [(0.02, 0.0, 0.095), (0.045, 0.0, 0.075), (0.058, 0.004, 0.04)], 0.007, DARK, verts=6))
metal.append(B.sphere('bolt_knob', 0.017, loc=(0.06, 0.004, 0.03), material=DARK, seg=10, rings=6))
# folded bipod under the fore-end
metal.append(B.box('bipod_mount', (0.06, 0.05, 0.036), loc=(0, -0.47, 0.012), material=DARK, bevel=0.006, seg=1))
for s in (-1, 1):
    metal.append(G.ycyl(f'bipod_leg{s}', 0.012, -0.68, -0.47, 0.01, DARK, 8, x=s * 0.022))
    metal.append(G.ycyl(f'bipod_foot{s}', 0.016, -0.72, -0.68, 0.01, DARK, 8, x=s * 0.022, bevel=0.003))
metal = B.join('sniper_metal', metal)

body = [G.P('forend', [(-0.5, 0.03), (-0.2, 0.03), (-0.17, 0.012), (-0.17, 0.092), (-0.5, 0.092), (-0.515, 0.08), (-0.515, 0.045)], 0.056, TAN, bevel=0.008, seg=2),
        G.P('receiver', [(-0.2, 0.012), (0.1, 0.012), (0.115, 0.03), (0.115, 0.092), (-0.2, 0.092)], 0.052, TAN, bevel=0.006, seg=2),
        G.P('wrist', [(0.1, 0.028), (0.19, 0.028), (0.19, 0.078), (0.1, 0.09)], 0.04, TAN, bevel=0.006),
        G.P('stock', [(0.18, 0.02), (0.22, 0.02), (0.26, -0.03), (0.32, -0.072), (YB - 0.025, -0.072), (YB - 0.025, 0.1), (0.25, 0.1), (0.18, 0.082)], 0.05, TAN, bevel=0.009, seg=2),
        G.P('cheek_rest', [(0.215, 0.1), (0.345, 0.1), (0.335, 0.125), (0.23, 0.125)], 0.046, OLIVE, bevel=0.007, seg=2),
        G.grip('grip', OLIVE, y=0.012, top=0.022, length=0.115, rake=0.04, depth=0.05, width=0.04)]
body = B.join('sniper_body', body)

mag = G.P('sniper_magazine', [(-0.18, 0.015), (-0.085, 0.015), (-0.085, -0.055), (-0.092, -0.064), (-0.172, -0.064), (-0.18, -0.055)], 0.04, OLIVE, bevel=0.006, seg=2)

# scope: olive tube with flared bells, on two dark rings
ZS = 0.158
scope = [G.ycyl('scope_tube', 0.02, -0.19, 0.06, ZS, OLIVE, 12),
         G.ycyl('scope_front_cone', 0.02, -0.26, -0.19, ZS, OLIVE, 12, r2=0.034),
         G.ycyl('scope_front', 0.034, -0.33, -0.26, ZS, OLIVE, 12),
         G.ycyl('scope_front_rim', 0.038, -0.35, -0.325, ZS, DARK, 12, bevel=0.003),
         G.ycyl('scope_rear_cone', 0.028, 0.06, 0.1, ZS, OLIVE, 12, r2=0.02),
         G.ycyl('scope_rear', 0.028, 0.1, 0.14, ZS, OLIVE, 12),
         G.ycyl('scope_rear_rim', 0.032, 0.135, 0.16, ZS, DARK, 12, bevel=0.003),
         G.ycyl('lens_front', 0.031, -0.352, -0.348, ZS, LENS, 12),
         G.ycyl('lens_rear', 0.025, 0.158, 0.162, ZS, LENS, 12),
         B.cyl('turret_top', 0.012, 0.02, loc=(0, -0.06, ZS + 0.028), material=DARK, verts=8),
         B.cyl('turret_side', 0.012, 0.02, loc=(0.028, -0.06, ZS), material=DARK, rot=(0, math.radians(90), 0), verts=8)]
for i, y in enumerate((-0.14, 0.02)):
    scope.append(B.box(f'ring{i}', (0.054, 0.034, 0.058), loc=(0, y, ZS - 0.002), material=DARK, bevel=0.008, seg=1))
    scope.append(B.box(f'ring_base{i}', (0.036, 0.04, 0.03), loc=(0, y, ZS - 0.04), material=DARK, bevel=0.004, seg=1))
scope = B.join('sniper_scope', scope)

trig = G.trigger('sniper_trigger', DARK, -0.04, 0.022)
B.set_pivot(trig, (0, -0.04, 0.02))
B.set_pivot(mag, (0, -0.13, 0.0))
for o in (metal, body, scope):
    B.set_pivot(o, (0, 0, 0))
B.finish('sniper_rifle', HERE, budget=9000)
