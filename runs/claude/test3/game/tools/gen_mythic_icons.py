"""Icons for the four mythic weapons (textures/icons/<id>.png, 128x128 RGBA): each is a transparent-background render of
the Blender model (see runs/claude/test3/assets_src/) with a dark outline, like the other weapon icons. No external APIs.
Run:  python runs/claude/test3/game/tools/gen_mythic_icons.py   (needs bpy and PIL)"""
import os, sys, math, itertools
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, os.path.join(ROOT, '..', 'common'))
import bpy
from mathutils import Vector
from PIL import Image, ImageFilter, ImageChops
import brlib as B

VIEWS = {'web_shooters': Vector((0.85, -0.7, 0.55)), 'ravage_grasp': Vector((0.45, -1.0, 0.5)),
         'charge_shotgun': Vector((1, 0.0, 0.12)), 'shockwave_launcher': Vector((1, -0.05, 0.12))}
OUT = os.path.join(HERE, '..', 'textures', 'icons')
TMP = os.path.join(os.environ.get('TMPDIR', '/tmp'), '_icon_render.png')


def render(asset):
    bpy.ops.wm.open_mainfile(filepath=os.path.join(ROOT, 'assets_src', asset, asset + '.blend'))
    B._MATS.clear()
    cam, extra = B._setup_render(512)
    s = bpy.context.scene
    s.render.film_transparent = True
    s.cycles.samples = 24
    objs = B.mesh_objects()
    lo, hi = B.bounds(objs)
    c = (lo + hi) / 2
    rad = (hi - lo).length / 2
    d = VIEWS[asset].normalized()
    q = (-d).to_track_quat('-Z', 'Y')
    right = q @ Vector((1, 0, 0))
    up = q @ Vector((0, 1, 0))
    corners = [Vector((x, y, z)) for x, y, z in itertools.product((lo.x, hi.x), (lo.y, hi.y), (lo.z, hi.z))]
    w = max(abs((p - c).dot(right)) for p in corners) * 2
    h = max(abs((p - c).dot(up)) for p in corners) * 2
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = max(w, h) * 1.08
    cam.location = c + d * (rad * 6 + 1)
    cam.data.clip_start = 0.001
    cam.data.clip_end = rad * 14 + 10
    cam.rotation_euler = q.to_euler()
    yaw = math.atan2(d.y, d.x) + math.pi / 2
    extra[0].rotation_euler = (math.radians(50), 0, yaw + math.radians(35))
    extra[1].rotation_euler = (math.radians(65), 0, yaw - math.radians(120))
    s.render.filepath = TMP
    bpy.ops.render.render(write_still=True)
    return Image.open(TMP).convert('RGBA')


def icon(im):
    bb = im.getchannel('A').point(lambda v: 255 if v > 8 else 0).getbbox()
    im = im.crop(bb)
    k = 108.0 / max(im.size)
    im = im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)
    canvas = Image.new('RGBA', (128, 128), (0, 0, 0, 0))
    x, y = (128 - im.width) // 2, (128 - im.height) // 2
    a = Image.new('L', (128, 128), 0)
    a.paste(im.getchannel('A'), (x, y))
    outline = a.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(0.6))
    shadow = ImageChops.offset(a.filter(ImageFilter.MaxFilter(5)), 2, 3).filter(ImageFilter.GaussianBlur(2.5)).point(lambda v: v * 0.35)
    canvas.paste(Image.new('RGBA', (128, 128), (10, 10, 18, 255)), (0, 0), shadow)
    canvas.paste(Image.new('RGBA', (128, 128), (28, 26, 36, 255)), (0, 0), outline)
    canvas.alpha_composite(Image.new('RGBA', (128, 128), (0, 0, 0, 0)))
    layer = Image.new('RGBA', (128, 128), (0, 0, 0, 0))
    layer.paste(im, (x, y))
    canvas.alpha_composite(layer)
    return canvas


for asset in VIEWS:
    icon(render(asset)).save(os.path.join(OUT, asset + '.png'))
    print('icon', asset)
