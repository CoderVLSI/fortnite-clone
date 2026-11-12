"""Hunting rifle: walnut stock, long dark barrel, iron sights (no scope), bolt action. Barrel to -Y, origin at the grip."""
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', '..', 'common'))
import bpy
import brlib as B
import gunlib as G

B.reset()
WOOD = B.mat('mat_walnut', '#8a5a32', rough=0.6)
WOOD_D = B.mat('mat_walnut_dark', '#6a4224', rough=0.65)
DARK = B.mat('mat_gunmetal', '#3a3c41', rough=0.45, metal=0.6)
BORE = B.mat('mat_bore', '#141518', rough=0.9)
BRASS = B.mat('mat_brass', '#c9a040', rough=0.4, metal=0.6)

YM, YB = -0.78, 0.36                           # 1.14 m long
ZA = 0.07

metal = [G.ycyl('barrel', 0.015, YM, -0.2, ZA, DARK, 10, r2=None),
         G.ycyl('crown', 0.017, YM, YM + 0.02, ZA, DARK, 10, bevel=0.002),
         G.ycyl('bore', 0.009, YM - 0.001, YM + 0.004, ZA, BORE, 8),
         G.P('action', [(-0.2, 0.06), (0.1, 0.06), (0.1, 0.1), (-0.2, 0.1)], 0.04, DARK, bevel=0.004),
         G.P('front_sight', [(YM + 0.03, ZA + 0.012), (YM + 0.06, ZA + 0.012), (YM + 0.055, ZA + 0.045), (YM + 0.04, ZA + 0.045)], 0.012, DARK, bevel=0.002),
         G.P('rear_sight', [(-0.27, ZA + 0.012), (-0.23, ZA + 0.012), (-0.235, ZA + 0.04), (-0.265, ZA + 0.04)], 0.03, DARK, bevel=0.002),
         G.P('butt_plate', [(YB - 0.016, -0.075), (YB, -0.07), (YB, 0.092), (YB - 0.016, 0.098)], 0.046, DARK, bevel=0.005),
         G.guard('guard', DARK, -0.06, -0.01, 0.022, drop=0.042)]
metal.append(B.tube('bolt_arm', [(0.02, 0.02, 0.09), (0.045, 0.02, 0.07), (0.055, 0.024, 0.035)], 0.007, DARK, verts=6))
metal.append(B.sphere('bolt_knob', 0.016, loc=(0.057, 0.024, 0.026), material=DARK, seg=10, rings=6))
for i in range(2):                             # sling swivels
    metal.append(B.torus(f'swivel{i}', 0.014, 0.004, loc=(0, -0.52 if i == 0 else 0.26, 0.0 if i == 0 else -0.06), material=DARK, rot=(0, math.radians(90), 0), major=10, minor=5))
metal = B.join('hunting_metal', metal)

body = [G.P('forend', [(-0.56, 0.035), (-0.2, 0.02), (-0.2, 0.072), (-0.56, 0.072), (-0.575, 0.06)], 0.05, WOOD, bevel=0.009, seg=2),
        G.P('stock', [(-0.2, 0.02), (0.08, 0.02), (0.13, 0.0), (0.22, -0.035), (YB - 0.016, -0.075), (YB - 0.016, 0.098), (0.2, 0.085), (0.1, 0.07), (-0.2, 0.072)], 0.048, WOOD, bevel=0.01, seg=2),
        G.P('forend_tip', [(-0.6, 0.04), (-0.56, 0.035), (-0.56, 0.072), (-0.6, 0.068)], 0.046, WOOD_D, bevel=0.006)]
for i in range(3):                             # checkering on the wrist
    body.append(B.box(f'check{i}', (0.05, 0.012, 0.03), loc=(0, 0.06 + i * 0.022, 0.03), material=WOOD_D, bevel=0.002, seg=1))
body = B.join('hunting_body', body)

# a row of spare cartridges on the stock
ammo = []
for i in range(4):
    ammo.append(B.cyl(f'round{i}', 0.006, 0.05, loc=(0.03, 0.2 + i * 0.022, 0.02), material=BRASS, verts=8))
ammo.append(B.box('ammo_band', (0.012, 0.1, 0.03), loc=(0.028, 0.233, 0.02), material=WOOD_D, bevel=0.003, seg=1))
ammo = B.join('hunting_ammo', ammo)

trig = G.trigger('hunting_trigger', DARK, -0.035, 0.022)
B.set_pivot(trig, (0, -0.035, 0.02))
for o in (metal, body, ammo):
    B.set_pivot(o, (0, 0, 0))
B.finish('hunting_rifle', HERE, budget=7000)
