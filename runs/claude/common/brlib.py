"""Shared helpers for the procedural asset build scripts (Blender 5.1, headless).

Every build_<id>.py imports this, builds its asset from an empty scene and calls
finish(), which cleans the meshes, paints gradient vertex colours, checks the
budget, saves the .blend, exports the .glb and renders the 4-view preview.
"""
import bpy, bmesh, math, os, json
from mathutils import Vector, Matrix, Euler

# ---------------------------------------------------------------- scene

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    s = bpy.context.scene
    s.unit_settings.system = 'METRIC'
    s.unit_settings.scale_length = 1.0
    return s


def srgb(hexstr):
    h = hexstr.lstrip('#')
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


_MATS = {}


def mat(name, hexcol, rough=0.7, metal=0.0, emit=0.0, alpha=1.0):
    """Principled material whose base colour is the 'Col' vertex colour.
    The flat colour + soft gradient is painted into the vertices by finish()."""
    if name in _MATS:
        return _MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes.get('Principled BSDF')
    b.inputs['Roughness'].default_value = rough
    b.inputs['Metallic'].default_value = metal
    att = nt.nodes.new('ShaderNodeVertexColor')
    att.layer_name = 'Col'
    nt.links.new(att.outputs['Color'], b.inputs['Base Color'])
    if emit > 0:
        nt.links.new(att.outputs['Color'], b.inputs['Emission Color'])
        b.inputs['Emission Strength'].default_value = emit
    if alpha < 1.0:
        b.inputs['Alpha'].default_value = alpha
        m.surface_render_method = 'BLENDED'
    m['hex'] = hexcol
    m.diffuse_color = (*srgb(hexcol), alpha)
    _MATS[name] = m
    return m

# ---------------------------------------------------------------- objects

def _link(o):
    bpy.context.scene.collection.objects.link(o)
    return o


def obj_from_bm(name, bm, material=None, loc=(0, 0, 0), rot=(0, 0, 0)):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    _link(o)
    o.location = loc
    o.rotation_euler = rot
    if material is not None:
        me.materials.append(material)
    return o


def box(name, size, loc=(0, 0, 0), material=None, rot=(0, 0, 0), bevel=0.0, seg=2):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    o = obj_from_bm(name, bm, material, loc, rot)
    if bevel > 0:
        add_bevel(o, bevel, seg)
    return o


def cyl(name, r, h, loc=(0, 0, 0), material=None, rot=(0, 0, 0), verts=16, r2=None, bevel=0.0, seg=2, caps=True):
    """Cylinder / cone along local Z, centred."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=verts,
                          radius1=r, radius2=r if r2 is None else r2, depth=h)
    o = obj_from_bm(name, bm, material, loc, rot)
    if bevel > 0:
        add_bevel(o, bevel, seg)
    return o


def sphere(name, r, loc=(0, 0, 0), material=None, seg=16, rings=8, scale=(1, 1, 1)):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=r)
    for v in bm.verts:
        v.co = Vector((v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2]))
    return obj_from_bm(name, bm, material, loc)


def ico(name, r, loc=(0, 0, 0), material=None, sub=2, scale=(1, 1, 1)):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=r)
    for v in bm.verts:
        v.co = Vector((v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2]))
    return obj_from_bm(name, bm, material, loc)


def torus(name, R, r, loc=(0, 0, 0), material=None, rot=(0, 0, 0), major=20, minor=8):
    bm = bmesh.new()
    rings = []
    for i in range(major):
        a = 2 * math.pi * i / major
        ring = []
        for j in range(minor):
            b = 2 * math.pi * j / minor
            rr = R + r * math.cos(b)
            ring.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), r * math.sin(b))))
        rings.append(ring)
    for i in range(major):
        for j in range(minor):
            a, b = rings[i], rings[(i + 1) % major]
            bm.faces.new((a[j], b[j], b[(j + 1) % minor], a[(j + 1) % minor]))
    return obj_from_bm(name, bm, material, loc, rot)


def prism(name, profile, depth, loc=(0, 0, 0), material=None, rot=(0, 0, 0), axis='X', bevel=0.0, seg=2):
    """Extrude a 2D polygon (list of (a, b), counter-clockwise) by `depth`, centred
    on the extrusion axis. axis='X': profile is (y, z); 'Y': (x, z); 'Z': (x, y)."""
    bm = bmesh.new()
    def P(a, b, d):
        return {'X': (d, a, b), 'Y': (a, d, b), 'Z': (a, b, d)}[axis]
    lo = [bm.verts.new(P(a, b, -depth / 2)) for a, b in profile]
    hi = [bm.verts.new(P(a, b, depth / 2)) for a, b in profile]
    n = len(profile)
    bm.faces.new(lo)
    bm.faces.new(list(reversed(hi)))
    for i in range(n):
        bm.faces.new((lo[i], hi[i], hi[(i + 1) % n], lo[(i + 1) % n]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, material, loc, rot)
    if bevel > 0:
        add_bevel(o, bevel, seg)
    return o


def tube(name, path, r, material=None, verts=8, caps=True, radii=None):
    """Round tube swept along a list of 3D points."""
    bm = bmesh.new()
    pts = [Vector(p) for p in path]
    rings = []
    prev_n = None
    for i, p in enumerate(pts):
        if i == 0:
            t = pts[1] - pts[0]
        elif i == len(pts) - 1:
            t = pts[-1] - pts[-2]
        else:
            t = (pts[i + 1] - pts[i]).normalized() + (pts[i] - pts[i - 1]).normalized()
        t.normalize()
        if prev_n is None:
            ref = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
            n = t.cross(ref).normalized()
        else:
            n = (prev_n - t * prev_n.dot(t)).normalized()
        prev_n = n
        b = t.cross(n)
        rr = radii[i] if radii else r
        rings.append([bm.verts.new(p + (n * math.cos(2 * math.pi * k / verts) + b * math.sin(2 * math.pi * k / verts)) * rr)
                      for k in range(verts)])
    for i in range(len(rings) - 1):
        for k in range(verts):
            bm.faces.new((rings[i][k], rings[i][(k + 1) % verts], rings[i + 1][(k + 1) % verts], rings[i + 1][k]))
    if caps:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm, material)


def lathe(name, profile, material=None, loc=(0, 0, 0), seg=16, cap_top=True, cap_bottom=True):
    """Revolve a list of (radius, z) around Z."""
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        rings.append([bm.verts.new((r * math.cos(2 * math.pi * k / seg), r * math.sin(2 * math.pi * k / seg), z)) for k in range(seg)])
    for i in range(len(rings) - 1):
        for k in range(seg):
            bm.faces.new((rings[i][k], rings[i][(k + 1) % seg], rings[i + 1][(k + 1) % seg], rings[i + 1][k]))
    if cap_bottom:
        bm.faces.new(list(reversed(rings[0])))
    if cap_top:
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm, material, loc)


def add_bevel(o, width, seg=2, angle=35):
    m = o.modifiers.new('bevel', 'BEVEL')
    m.width = width
    m.segments = seg
    m.limit_method = 'ANGLE'
    m.angle_limit = math.radians(angle)
    m.harden_normals = False
    return m


def select_only(objs):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def apply_mods(o):
    select_only([o])
    for m in list(o.modifiers):
        try:
            bpy.ops.object.modifier_apply(modifier=m.name)
        except RuntimeError:
            o.modifiers.remove(m)


def join(name, objs):
    """Apply modifiers and join several objects into one named object (origin at world origin)."""
    objs = [o for o in objs if o is not None]
    for o in objs:
        apply_mods(o)
    select_only(objs)
    if len(objs) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    o.data.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return o


def set_pivot(o, pivot):
    """Apply rotation/scale and move the origin to a world-space pivot point."""
    apply_mods(o)
    select_only([o])
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    p = Vector(pivot)
    o.data.transform(Matrix.Translation(-p))
    o.location = p
    return o


def move(o, d):
    o.location = Vector(o.location) + Vector(d)
    return o

# ---------------------------------------------------------------- finishing

def _clean(o, merge=1e-5):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=merge)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-6)
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context='VERTS')
    wire = [e for e in bm.edges if not e.link_faces]
    if wire:
        bmesh.ops.delete(bm, geom=wire, context='EDGES')
    zero = [f for f in bm.faces if f.calc_area() < 1e-10]
    if zero:
        bmesh.ops.delete(bm, geom=zero, context='FACES')
    if not o.get('keep_normals'):
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(o.data)
    bm.free()


def _paint(o, lo=0.80, hi=1.10):
    """Flat base colour per material, with a soft bottom-to-top gradient and a
    small lift on upward-facing surfaces (the hand-painted look)."""
    me = o.data
    if 'Col' in me.color_attributes:
        me.color_attributes.remove(me.color_attributes['Col'])
    ca = me.color_attributes.new('Col', 'FLOAT_COLOR', 'CORNER')
    me.color_attributes.active_color = ca
    me.color_attributes.render_color_index = me.color_attributes.find('Col')
    zs = [v.co.z for v in me.vertices]
    z0, z1 = min(zs), max(zs)
    span = max(z1 - z0, 1e-6)
    lo = o.get('grad_lo', lo)
    hi = o.get('grad_hi', hi)
    cols = [srgb(m['hex']) if m and 'hex' in m.keys() else (0.5, 0.5, 0.5) for m in me.materials] or [(0.5, 0.5, 0.5)]
    alphas = [m.diffuse_color[3] if m else 1.0 for m in me.materials] or [1.0]
    for poly in me.polygons:
        base = cols[min(poly.material_index, len(cols) - 1)]
        al = alphas[min(poly.material_index, len(alphas) - 1)]
        up = 0.06 * poly.normal.z
        for li in poly.loop_indices:
            v = me.vertices[me.loops[li].vertex_index]
            t = (v.co.z - z0) / span
            k = lo + (hi - lo) * t + up
            ca.data[li].color = (min(base[0] * k, 1), min(base[1] * k, 1), min(base[2] * k, 1), al)


def _shade(o):
    me = o.data
    ang = math.radians(o.get('smooth_angle', 40))
    for p in me.polygons:
        p.use_smooth = not o.get('flat', False)
    if not o.get('flat', False):
        me.set_sharp_from_angle(angle=ang)


def tri_count(objs):
    n = 0
    for o in objs:
        n += sum(len(p.vertices) - 2 for p in o.data.polygons)
    return n


def mesh_objects():
    return [o for o in bpy.context.scene.objects if o.type == 'MESH']


def bounds(objs=None):
    objs = objs or mesh_objects()
    lo = Vector((1e9,) * 3)
    hi = Vector((-1e9,) * 3)
    for o in objs:
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            for i in range(3):
                lo[i] = min(lo[i], w[i])
                hi[i] = max(hi[i], w[i])
    return lo, hi


def _setup_render(res):
    s = bpy.context.scene
    s.render.engine = 'CYCLES'
    s.cycles.device = 'CPU'
    s.cycles.samples = 40
    s.cycles.use_denoising = True
    s.cycles.max_bounces = 3
    s.render.resolution_x = res
    s.render.resolution_y = res
    s.render.image_settings.file_format = 'PNG'
    s.view_settings.view_transform = 'Standard'
    w = bpy.data.worlds.new('preview_world')
    w.use_nodes = True
    bg = w.node_tree.nodes['Background']
    bg.inputs[0].default_value = (0.52, 0.52, 0.54, 1)
    bg.inputs[1].default_value = 0.9
    s.world = w
    extra = []
    for name, rot, power in (('key', (math.radians(50), 0, math.radians(35)), 3.2),
                             ('fill', (math.radians(65), 0, math.radians(-120)), 1.2)):
        ld = bpy.data.lights.new('preview_' + name, 'SUN')
        ld.energy = power
        ld.angle = math.radians(12)
        lo_ = bpy.data.objects.new('preview_' + name, ld)
        lo_.rotation_euler = rot
        _link(lo_)
        extra.append(lo_)
    cd = bpy.data.cameras.new('preview_cam')
    cam = bpy.data.objects.new('preview_cam', cd)
    _link(cam)
    s.camera = cam
    extra.append(cam)
    return cam, extra


VIEWS = {
    'side': Vector((1, 0, 0.08)),
    'side_l': Vector((-1, 0, 0.08)),
    '3/4': Vector((0.75, -1, 0.5)),
    '3/4 back': Vector((-0.75, 1, 0.5)),
    'front': Vector((0, -1, 0.08)),
    'back': Vector((0, 1, 0.08)),
    'top': Vector((0, -0.02, 1)),
}


def render_preview(path, views=('side', '3/4', 'front', 'back'), res=640, objs=None):
    from PIL import Image, ImageDraw
    cam, extra = _setup_render(res)
    lo, hi = bounds(objs)
    c = (lo + hi) / 2
    rad = (hi - lo).length / 2
    tiles = []
    tmp = os.path.join(os.path.dirname(path), '_tmp_view.png')
    for v in views:
        d = VIEWS[v].normalized()
        cam.data.type = 'ORTHO'
        cam.data.ortho_scale = rad * 2.25
        cam.location = c + d * (rad * 6 + 1)
        cam.data.clip_start = 0.001
        cam.data.clip_end = rad * 14 + 10
        cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
        # keep the light relative to the camera so every view is readable
        yaw = math.atan2(d.y, d.x) + math.pi / 2
        extra[0].rotation_euler = (math.radians(50), 0, yaw + math.radians(35))
        extra[1].rotation_euler = (math.radians(65), 0, yaw - math.radians(120))
        bpy.context.scene.render.filepath = tmp
        bpy.ops.render.render(write_still=True)
        im = Image.open(tmp).convert('RGB')
        ImageDraw.Draw(im).text((10, 8), v, fill=(255, 255, 255))
        tiles.append(im)
    sheet = Image.new('RGB', (res * len(tiles), res))
    for i, im in enumerate(tiles):
        sheet.paste(im, (i * res, 0))
    sheet.save(path)
    os.remove(tmp)
    for o in extra:
        bpy.data.objects.remove(o)


def finish(asset_id, out_dir, budget, views=('side', '3/4', 'front', 'back'), notes=None, per_object_budget=False, ground=False):
    """Clean, shade, paint, check, save .blend, export .glb, render preview, write stats."""
    os.makedirs(out_dir, exist_ok=True)
    objs = mesh_objects()
    if ground:                               # rest the asset on Z=0
        for o in objs:
            apply_mods(o)
        dz = bounds(objs)[0].z
        for o in objs:
            if Vector(o.location).length < 1e-9:
                o.data.transform(Matrix.Translation((0, 0, -dz)))
            else:
                o.location.z -= dz
        bpy.context.view_layer.update()
    for o in objs:
        apply_mods(o)
        _clean(o)
        _shade(o)
        _paint(o)
    problems = []
    for o in objs:
        me = o.data
        used = set()
        for p in me.polygons:
            used.update(p.vertices)
            if p.area < 1e-10:
                problems.append(f'{o.name}: zero-area face')
                break
        if len(used) != len(me.vertices):
            problems.append(f'{o.name}: loose vertices')
    tris = tri_count(objs)
    per = {o.name: tri_count([o]) for o in objs}
    lo, hi = bounds(objs)
    dims = [round(hi[i] - lo[i], 4) for i in range(3)]
    stats = {'asset': asset_id, 'triangles': tris, 'budget': budget, 'per_object': per,
             'dimensions_m': dims, 'min': [round(x, 4) for x in lo], 'max': [round(x, 4) for x in hi],
             'objects': len(objs), 'materials': sorted({m.name for o in objs for m in o.data.materials if m}),
             'problems': problems}
    if notes:
        stats['notes'] = notes
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out_dir, f'{asset_id}.blend'), compress=True)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(out_dir, f'{asset_id}.glb'), export_format='GLB',
                              use_selection=True, export_apply=True, export_yup=True,
                              export_vertex_color='ACTIVE', export_all_vertex_colors=False)
    render_preview(os.path.join(out_dir, f'preview_{asset_id}.png'), views)
    with open(os.path.join(out_dir, f'stats_{asset_id}.json'), 'w') as f:
        json.dump(stats, f, indent=1)
    print('STATS', json.dumps(stats))
    return stats
