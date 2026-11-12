"""Tactical (semi-auto) shotgun: slate receiver, vented heat shield over the barrel, red shell holders. Barrel to -Y, origin at the grip."""
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', '..', 'common'))
import bpy
import brlib as B
import gunlib as G

B.reset()
SLATE = B.mat('mat_slate', '#56606c', rough=0.65)
SLATE_D = B.mat('mat_slate_dark', '#434b55', rough=0.7)
BLACK = B.mat('mat_black', '#2a2c30', rough=0.8)
DARK = B.mat('mat_gunmetal', '#3a3c41', rough=0.5, metal=0.5)
BORE = B.mat('mat_bore', '#141518', rough=0.9)
SHELL = B.mat('mat_shell', '#c23a2c', rough=0.6)
BRASS = B.mat('mat_brass', '#c9a040', rough=0.4, metal=0.6)

YM = -0.55                                    # muzzle; stock to +0.33 -> 0.88 m
ZB, ZT = 0.085, 0.045

metal = [G.ycyl('barrel', 0.02, YM, -0.14, ZB, DARK, 12, bevel=0.003),
         G.ycyl('bore', 0.014, YM - 0.001, YM + 0.004, ZB, BORE, 10),
         G.ycyl('mag_tube', 0.017, YM + 0.06, -0.14, ZT, DARK, 12, bevel=0.003),
         G.ycyl('tube_cap', 0.019, YM + 0.05, YM + 0.07, ZT, BLACK, 10, bevel=0.003),
         B.box('ghost_ring', (0.03, 0.012, 0.03), loc=(0, 0.04, 0.13), material=DARK, bevel=0.003, seg=1),
         B.box('front_post', (0.01, 0.012, 0.022), loc=(0, YM + 0.03, ZB + 0.03), material=DARK)]
# vented heat shield: a half shell with slots
shield = [G.P('heat_shield', [(YM + 0.08, ZB + 0.012), (-0.16, ZB + 0.012), (-0.16, ZB + 0.032), (YM + 0.08, ZB + 0.032)], 0.05, SLATE_D, bevel=0.004)]
for i in range(7):
    shield.append(B.box(f'vent{i}', (0.052, 0.026, 0.012), loc=(0, YM + 0.11 + i * 0.044, ZB + 0.028), material=BORE))
metal = B.join('tactical_metal', metal + shield)

body = [G.P('receiver', [(-0.15, 0.02), (0.11, 0.02), (0.11, 0.105), (-0.135, 0.112), (-0.15, 0.098)], 0.058, SLATE, bevel=0.007, seg=2),
        B.box('forend', (0.066, 0.2, 0.06), loc=(0, -0.3, ZT + 0.002), material=BLACK, bevel=0.012, seg=2),
        G.P('stock', [(0.11, 0.02), (0.11, 0.1), (0.2, 0.09), (0.33, 0.085), (0.33, -0.06), (0.24, -0.05), (0.17, -0.005)], 0.046, BLACK, bevel=0.008, seg=2),
        G.P('butt_pad', [(0.315, -0.065), (0.34, -0.06), (0.34, 0.09), (0.315, 0.094)], 0.05, SLATE_D, bevel=0.006),
        G.guard('guard', SLATE_D, -0.075, -0.015, 0.022, drop=0.046)]
for i in range(4):                             # forend grip ribs
    body.append(B.box(f'rib{i}', (0.072, 0.012, 0.036), loc=(0, -0.37 + i * 0.045, ZT), material=SLATE_D, bevel=0.002, seg=1))
body = B.join('tactical_body', body)
grip = G.grip('tactical_grip', BLACK, y=0.01, top=0.022, length=0.118, rake=0.04, depth=0.05, width=0.04)
body = B.join('tactical_body', [body, grip])

# side saddle with four red shells
shells = [B.box('saddle', (0.012, 0.12, 0.05), loc=(-0.036, -0.03, 0.068), material=BLACK, bevel=0.003, seg=1)]
for i in range(4):                             # upright in the saddle, brass ends down
    y = -0.075 + i * 0.03
    shells.append(B.cyl(f'shell{i}', 0.0105, 0.042, loc=(-0.046, y, 0.078), material=SHELL, verts=8))
    shells.append(B.cyl(f'shell_base{i}', 0.0115, 0.012, loc=(-0.046, y, 0.052), material=BRASS, verts=8))
shells = B.join('tactical_shells', shells)

trig = G.trigger('tactical_trigger', DARK, -0.035, 0.022)
B.set_pivot(trig, (0, -0.035, 0.02))
for o in (metal, body, shells):
    B.set_pivot(o, (0, 0, 0))
B.finish('tactical_shotgun', HERE, budget=7000)
