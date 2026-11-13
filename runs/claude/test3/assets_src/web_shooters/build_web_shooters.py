"""Weaver's Web Shooters (mythic): a pair of wrist launchers, white-and-red bracers with twin web nozzles and a glowing
cartridge. Barrel to -Y, origin at the grip, up +Z. Object names are prefixed mythic_web_."""
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', '..', 'common'))
import bpy
import brlib as B
import gunlib as G

B.reset()
RED = B.mat('mat_web_red', '#b3202b', rough=0.55)
BLUE = B.mat('mat_web_blue', '#23356b', rough=0.6)
WHITE = B.mat('mat_web_white', '#e8ecf2', rough=0.45)
DARK = B.mat('mat_web_dark', '#2a2d34', rough=0.45, metal=0.5)
GLOW = B.mat('mat_web_glow', '#f4f7ff', rough=0.3, emit=1.4)


def bracer(tag, x):
    parts = [G.P(f'mythic_web_cuff{tag}', [(-0.02, 0.0), (0.14, 0.0), (0.16, 0.05), (0.14, 0.085), (-0.02, 0.085), (-0.04, 0.06)], 0.07, RED, bevel=0.008, seg=2, x=x),
             G.P(f'mythic_web_plate{tag}', [(-0.12, 0.08), (0.06, 0.08), (0.06, 0.125), (-0.1, 0.125), (-0.13, 0.105)], 0.056, BLUE, bevel=0.006, seg=2, x=x),
             G.ycyl(f'mythic_web_nozzle{tag}', 0.016, -0.2, -0.1, 0.1, DARK, 10, r2=0.011, x=x, bevel=0.002),
             G.ycyl(f'mythic_web_bore{tag}', 0.007, -0.203, -0.195, 0.1, WHITE, 8, x=x)]
    for i in range(3):
        parts.append(B.box(f'mythic_web_band{tag}{i}', (0.074, 0.012, 0.09), loc=(x, 0.0 + i * 0.045, 0.043), material=WHITE, bevel=0.002, seg=1))
    return B.join(f'mythic_web_body{tag}', parts)


left = bracer('L', -0.055)
right = bracer('R', 0.055)
# a spider emblem on each plate: a glowing body and legs
emb = [B.ico('mythic_web_emb_body', 0.014, loc=(-0.055, -0.03, 0.134), material=GLOW, sub=1),
       B.ico('mythic_web_emb_body2', 0.014, loc=(0.055, -0.03, 0.134), material=GLOW, sub=1)]
for x in (-0.055, 0.055):
    for s in (-1, 1):
        for k in range(3):
            emb.append(B.beam(f'mythic_web_leg{x}{s}{k}', (x, -0.03, 0.134), (x + s * 0.026, -0.03 + (k - 1) * 0.022, 0.133), 0.004, material=GLOW))
emb = B.join('mythic_web_emblem', emb)
cart = B.join('mythic_web_cartridge', [B.cyl('c1', 0.012, 0.07, loc=(-0.055, 0.05, 0.145), rot=(math.radians(90), 0, 0), material=GLOW, verts=8),
                                        B.cyl('c2', 0.012, 0.07, loc=(0.055, 0.05, 0.145), rot=(math.radians(90), 0, 0), material=GLOW, verts=8)])
strap = B.join('mythic_web_strap', [B.box('s1', (0.15, 0.03, 0.012), loc=(0, 0.1, 0.0), material=DARK, bevel=0.003, seg=1)])
for o in (left, right, emb, cart, strap):
    B.set_pivot(o, (0, 0, 0))
B.finish('web_shooters', HERE, budget=6000)
