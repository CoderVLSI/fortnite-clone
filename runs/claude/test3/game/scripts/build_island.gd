## Builds the whole island level from zero and saves res://scenes/island.tscn and res://textures/minimap.png.
## Run:  godot --headless --path <project> -s scripts/build_island.gd   (then re-bake the bots' grid: scripts/bake_nav.gd)
## Everything comes from the stage 1 .glb assets or is generated here (terrain, water, roads, bridges, crops, cacti).
## This is the game's version of the stage 2 builder: the stage 2 island sits in the middle, with snowy mountains to
## the north, a desert to the south and green country east and west (see terrain.gd).
extends SceneTree

const Terrain := preload("res://scripts/terrain.gd")

const CELL := 2.5                      # terrain grid step
const HALF := 520.0                    # the terrain covers the whole 1040 x 1040 m ocean area
const CHUNKS := 8                      # the terrain mesh is split so only what is in view gets drawn
const REACH := 375.0                   # how far out from the centre things get scattered
const ASSETS := ["grenade", "bushes", "rocks", "farm_props", "ammo_box", "medkit", "shield_potion", "chest", "pistol", "shotgun",
		"assault_rifle", "sniper_rifle", "rocket_launcher", "supply_drop", "trees", "modular_kit", "lookout_tower", "warehouse",
		"house", "pickaxe", "drop_vehicle", "smg", "tactical_shotgun", "burst_rifle", "hunting_rifle", "upgrade_bench"]

var T: Terrain
var rng := RandomNumberGenerator.new()
var meshes := {}                        # object name -> ArrayMesh (colours converted, saved under res://meshes)
var xforms := {}                        # object name -> Transform3D inside its .glb
var parts := {}                         # asset id -> [object names]
var shapes := {}                        # cache of collision shapes
var blocked: Array = []                 # [Vector2 centre, radius] keep-clear circles
var isle: Node3D
var counts := {}
var tree_pts: Array = []                # [Vector2, Color] every planted tree, for the minimap
var buildings: Array = []               # [Vector2, half-size, yaw] footprints, for the minimap


func _init() -> void:
	rng.seed = 20261110
	T = Terrain.new()
	DirAccess.make_dir_recursive_absolute("res://meshes")
	DirAccess.make_dir_recursive_absolute("res://scenes")
	DirAccess.make_dir_recursive_absolute("res://textures")
	load_assets()
	make_cactus()
	isle = Node3D.new()
	isle.name = "Island"
	build_environment()
	build_terrain()
	build_water()
	build_bridges()
	build_village()
	build_farm()
	build_industrial()
	build_towers()
	build_forests()
	build_outer()
	build_scatter()
	build_loot()
	build_sky()
	build_spawns()
	build_minimap()
	own(isle)
	var ps := PackedScene.new()
	var err := ps.pack(isle)
	if err == OK:
		err = ResourceSaver.save(ps, "res://scenes/island.tscn")
	print("SAVE ", err, " ", JSON.stringify(counts))
	var f := FileAccess.open("res://scenes/island_counts.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(counts, "  "))
	f.close()
	isle.free()
	quit()


# ----------------------------------------------------------------------------- helpers

func own(n: Node) -> void:
	for c in n.get_children():
		c.owner = isle
		own(c)


func group(name: String, parent: Node = null) -> Node3D:
	var g := Node3D.new()
	g.name = name
	(parent if parent else isle).add_child(g)
	return g


func count(key: String, n := 1) -> void:
	counts[key] = counts.get(key, 0) + n


func ground(x: float, z: float) -> float:
	return T.height(x, z)


func at(x: float, z: float, lift := 0.0) -> Vector3:
	return Vector3(x, ground(x, z) + lift, z)


func block(p: Vector2, r: float) -> void:
	blocked.append([p, r])


func is_free(p: Vector2, r: float, road_gap := 3.2) -> bool:
	if ground(p.x, p.y) < 1.2 or T.coast(p) < 4.0:
		return false
	if p.distance_to(T.lake) < T.lake_r + 6.0 + r or T.river_info(p).x < 10.0 + r:
		return false
	if road_gap > 0.0 and T.road_dist(p) < road_gap + r:
		return false
	for b in blocked:
		if p.distance_to(b[0]) < b[1] + r:
			return false
	return true


func load_assets() -> void:
	## Pull every mesh out of the stage 1 .glb files. glTF vertex colours are linear; this renderer reads
	## them as sRGB, so convert once here and store the result as .res files the scene can share.
	for id in ASSETS:
		var ps: PackedScene = load("res://assets/%s.glb" % id)
		var inst := ps.instantiate()
		parts[id] = []
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var src: Mesh = mi.mesh
			var am := ArrayMesh.new()
			for s in src.get_surface_count():
				var arr := src.surface_get_arrays(s)
				var cols = arr[Mesh.ARRAY_COLOR]
				if cols != null:
					for k in cols.size():
						var c: Color = cols[k]
						var a := c.a
						c = c.linear_to_srgb()
						c.a = a
						cols[k] = c
					arr[Mesh.ARRAY_COLOR] = cols
				am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
				var mat: Material = src.surface_get_material(s)
				var mpath := "res://meshes/mat_%s_%s.tres" % [id, mat.resource_name.validate_filename() if mat.resource_name != "" else str(s)]
				if not ResourceLoader.exists(mpath) or not shapes.has(mpath):
					var m2: Material = mat.duplicate()
					ResourceSaver.save(m2, mpath)
					shapes[mpath] = true
				am.surface_set_material(s, load(mpath))
			var path := "res://meshes/%s.res" % mi.name
			ResourceSaver.save(am, path)
			meshes[String(mi.name)] = load(path)
			var xf := Transform3D.IDENTITY
			var n: Node = mi
			while n != inst and n != null:
				if n is Node3D:
					xf = n.transform * xf
				n = n.get_parent()
			xforms[String(mi.name)] = xf
			parts[id].append(String(mi.name))
		inst.free()


func mesh_node(obj: String, parent: Node, xf := Transform3D.IDENTITY, node_name := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = meshes[obj]
	mi.name = node_name if node_name != "" else obj
	mi.transform = xf
	parent.add_child(mi, true)
	return mi


func variant(obj: String, suffix: String, tint: Callable) -> String:
	## A recoloured copy of a mesh (snow on top, sandstone walls...): same shape, vertex colours passed through
	## tint(colour, normal). Saved as its own mesh so the game can tell it apart (and break it like the original).
	var nm := obj + "_" + suffix
	if meshes.has(nm):
		return nm
	var src: ArrayMesh = meshes[obj]
	var am := ArrayMesh.new()
	for si in src.get_surface_count():
		var arr := src.surface_get_arrays(si)
		var cols = arr[Mesh.ARRAY_COLOR]
		var nrm = arr[Mesh.ARRAY_NORMAL]
		if cols != null:
			for k in cols.size():
				cols[k] = tint.call(cols[k], nrm[k] if nrm != null else Vector3.UP)
			arr[Mesh.ARRAY_COLOR] = cols
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		am.surface_set_material(si, src.surface_get_material(si))
	var path := "res://meshes/%s.res" % nm
	ResourceSaver.save(am, path)
	meshes[nm] = load(path)
	xforms[nm] = xforms.get(obj, Transform3D.IDENTITY)
	return nm


func snowy(c: Color, n: Vector3) -> Color:
	## Snow settles on whatever faces up.
	return c.lerp(Color(0.94, 0.96, 1.0), clampf((n.y - 0.25) / 0.6, 0.0, 1.0) * 0.9)


func make_cactus() -> void:
	## A saguaro: a ribbed trunk with two arms, built here (stage 1 had no cactus).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var green := Color(0.3, 0.52, 0.24)
	var dark := Color(0.2, 0.4, 0.18)
	# [base, top, radius]
	var limbs := [[Vector3(0, 0, 0), Vector3(0, 3.6, 0), 0.34], [Vector3(0.3, 1.4, 0), Vector3(0.95, 1.55, 0), 0.2], [Vector3(0.95, 1.5, 0), Vector3(0.95, 2.7, 0), 0.2],
			[Vector3(-0.3, 1.9, 0), Vector3(-0.85, 2.0, 0), 0.18], [Vector3(-0.85, 1.95, 0), Vector3(-0.85, 2.9, 0), 0.18]]
	for l in limbs:
		var a: Vector3 = l[0]
		var b: Vector3 = l[1]
		var r: float = l[2]
		var ax := (b - a).normalized()
		var u := ax.cross(Vector3.FORWARD if absf(ax.z) < 0.9 else Vector3.RIGHT).normalized()
		var v := ax.cross(u)
		var seg := 10
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			var o0 := (u * cos(a0) + v * sin(a0))
			var o1 := (u * cos(a1) + v * sin(a1))
			var col := green if i % 2 == 0 else dark                # ribs
			for q in [[a + o0 * r, o0], [b + o0 * r, o0], [b + o1 * r, o1], [a + o0 * r, o0], [b + o1 * r, o1], [a + o1 * r, o1]]:
				st.set_color(col)
				st.set_normal(q[1])
				st.add_vertex(q[0])
			# rounded-ish cap: a fan to the tip
			st.set_color(green); st.set_normal(ax); st.add_vertex(b + o0 * r)
			st.set_color(green); st.set_normal(ax); st.add_vertex(b + ax * r * 0.8)
			st.set_color(green); st.set_normal(ax); st.add_vertex(b + o1 * r)
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	ResourceSaver.save(mesh, "res://meshes/cactus.res")
	meshes["cactus"] = load("res://meshes/cactus.res")


func trimesh(obj: String) -> Shape3D:
	var key := "tri_" + obj
	if not shapes.has(key):
		var sh: Shape3D = meshes[obj].create_trimesh_shape()
		ResourceSaver.save(sh, "res://meshes/%s_col.res" % obj)
		shapes[key] = load("res://meshes/%s_col.res" % obj)
	return shapes[key]


func convex(obj: String) -> Shape3D:
	var key := "cvx_" + obj
	if not shapes.has(key):
		var sh: Shape3D = meshes[obj].create_convex_shape(true, true)
		ResourceSaver.save(sh, "res://meshes/%s_hull.res" % obj)
		shapes[key] = load("res://meshes/%s_hull.res" % obj)
	return shapes[key]


func add_collider(parent: Node3D, shape: Shape3D, xf := Transform3D.IDENTITY, body_name := "Collider") -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	parent.add_child(body, true)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xf
	body.add_child(cs)
	return body


func place_asset(id: String, parent: Node, pos: Vector3, yaw := 0.0, node_name := "", solid: Array = [], hulls: Array = [], skip: Array = []) -> Node3D:
	## Instance a multi-part asset with every part at its own pivot. `solid` parts get exact (trimesh)
	## colliders, `hulls` parts get convex colliders.
	var n := Node3D.new()
	n.name = node_name if node_name != "" else id
	parent.add_child(n, true)
	n.position = pos
	n.rotation.y = yaw
	for obj in parts[id]:
		if obj in skip:
			continue
		var mi := mesh_node(obj, n, xforms[obj])
		if obj in solid:
			add_collider(mi, trimesh(obj))
		elif obj in hulls:
			add_collider(mi, convex(obj))
	n.set_meta("asset", id)
	count(id)
	return n


func place_single(obj: String, parent: Node, pos: Vector3, yaw := 0.0, scale := 1.0, hull := false, node_name := "") -> MeshInstance3D:
	## One object out of a multi-object set (a rock, a kit piece, a barrel), placed at its own origin.
	var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), pos)
	var mi := mesh_node(obj, parent, xf, node_name)
	if hull:
		add_collider(mi, convex(obj))
	count(obj)
	return mi


func instanced(mesh: Mesh, parent: Node, xfs: Array, node_name: String) -> MultiMeshInstance3D:
	## The dummy renderer used by a headless build cannot store MultiMesh buffers, so the transforms
	## are kept on the node and the MultiMesh is created when the scene loads (see instanced.gd).
	var buf := PackedFloat32Array()
	buf.resize(xfs.size() * 12)
	for i in xfs.size():
		var t: Transform3D = xfs[i]
		var o := i * 12
		buf[o] = t.basis.x.x; buf[o + 1] = t.basis.y.x; buf[o + 2] = t.basis.z.x; buf[o + 3] = t.origin.x
		buf[o + 4] = t.basis.x.y; buf[o + 5] = t.basis.y.y; buf[o + 6] = t.basis.z.y; buf[o + 7] = t.origin.y
		buf[o + 8] = t.basis.x.z; buf[o + 9] = t.basis.y.z; buf[o + 10] = t.basis.z.z; buf[o + 11] = t.origin.z
	var mmi := MultiMeshInstance3D.new()
	mmi.set_script(load("res://scripts/instanced.gd"))
	mmi.set("mesh", mesh)
	mmi.set("transforms", buf)
	mmi.name = node_name
	parent.add_child(mmi, true)
	return mmi


func multimesh(obj: String, parent: Node, xfs: Array, node_name: String) -> MultiMeshInstance3D:
	count(obj, xfs.size())
	return instanced(meshes[obj], parent, xfs, node_name)


func box_mesh(size: Vector3, color: Color) -> BoxMesh:
	var key := "box_%s_%s" % [size, color.to_html()]
	if not shapes.has(key):
		var m := BoxMesh.new()
		m.size = size
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.8
		m.material = mat
		shapes[key] = m
	return shapes[key]


func box_node(parent: Node, name: String, size: Vector3, color: Color, xf: Transform3D, solid := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = box_mesh(size, color)
	mi.name = name
	mi.transform = xf
	parent.add_child(mi, true)
	if solid:
		var sh := BoxShape3D.new()
		sh.size = size
		add_collider(mi, sh)
	return mi


func yaw_to(from: Vector2, to: Vector2) -> float:
	## Yaw that turns an asset's front (+Z in this engine) from `from` towards `to`.
	var d := to - from
	return atan2(d.x, d.y)


# ----------------------------------------------------------------------------- environment

func build_environment() -> void:
	var g := group("Lighting")
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 0.95
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 220.0
	g.add_child(sun)
	var env := Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.25, 0.5, 0.9)
	psm.sky_horizon_color = Color(0.72, 0.85, 0.96)
	psm.ground_horizon_color = Color(0.72, 0.85, 0.96)
	psm.ground_bottom_color = Color(0.2, 0.4, 0.6)
	sky.sky_material = psm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.8, 0.9)
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.85, 0.96)
	env.fog_density = 0.0004
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	g.add_child(we)


# ----------------------------------------------------------------------------- terrain

func terrain_color(p: Vector2, h: float, slope: float) -> Color:
	var grass := Color(0.27, 0.5, 0.16).lerp(Color(0.4, 0.6, 0.2), 0.5 + 0.5 * T.n_small.get_noise_2d(p.x * 0.4, p.y * 0.4))
	var sand := Color(0.82, 0.72, 0.5)
	var rock := Color(0.47, 0.46, 0.44)
	var dirt := Color(0.62, 0.47, 0.29)
	var c := grass
	# forests are a darker green
	c = c.lerp(Color(0.2, 0.42, 0.18), 0.45 * (1.0 - smoothstep(-80.0, -45.0, p.y)) * (1.0 - smoothstep(50.0, 90.0, p.x)))
	# the biomes: snow in the north, sand in the south (with green along the oasis river)
	var sn := T.snow(p)
	var de := T.desert(p)
	if sn > 0.0:
		var snowc := Color(0.8, 0.84, 0.9).lerp(Color(0.66, 0.73, 0.86), 0.5 + 0.5 * T.n_small.get_noise_2d(p.x * 0.3, p.y * 0.3))
		c = c.lerp(snowc, sn)
	if de > 0.0:
		var dune := 0.5 + 0.5 * sin(p.x * 0.045 + T.n_dune.get_noise_2d(p.x, p.y) * 4.0)
		var sandc := Color(0.82, 0.7, 0.48).lerp(Color(0.74, 0.58, 0.38), dune * 0.6 + 0.2 * T.n_small.get_noise_2d(p.x, p.y))
		var oasis := 1.0 - smoothstep(14.0, 32.0, T.river_info(p).x)
		c = c.lerp(sandc.lerp(Color(0.33, 0.55, 0.22), oasis * 0.85), de)
	# the shoreline
	c = c.lerp(sand, clampf(1.0 - smoothstep(0.9, 1.9, h), 0.0, 1.0))
	# rock on steep ground and on the three tower hills (grey stone in the snow, red rock in the desert)
	rock = rock.lerp(Color(0.52, 0.54, 0.6), sn).lerp(Color(0.7, 0.42, 0.28), de)
	var rocky := smoothstep(0.42, 0.8, slope)
	for i in [1, 2]:
		rocky = maxf(rocky, (1.0 - smoothstep(18.0, 40.0, p.distance_to(T.towers[i]))) * smoothstep(6.0, 11.0, h) * 0.8)
	if h > 1.5:
		c = c.lerp(rock, rocky)
	# river and lake beds
	var ri := T.river_info(p)
	if ri.x < 13.0:
		c = c.lerp(Color(0.62, 0.6, 0.5), 1.0 - smoothstep(6.0, 12.0, ri.x))
	if p.distance_to(T.lake) < T.lake_r + 9.0:
		c = c.lerp(Color(0.6, 0.6, 0.55), 1.0 - smoothstep(T.lake_r - 2.0, T.lake_r + 8.0, p.distance_to(T.lake)))
	if h > 1.0:
		# crop fields
		for f in T.fields:
			var q: Vector2 = (p - f[0]).abs()
			if q.x < f[1].x and q.y < f[1].y:
				var stripe := 0.86 + 0.14 * sin(p.x * 2.4)
				c = Color(f[2].r * stripe, f[2].g * stripe, f[2].b * stripe)
		# paved industrial yard
		if T.in_yard(p):
			c = Color(0.44, 0.45, 0.47).lerp(Color(0.38, 0.39, 0.41), 0.5 + 0.5 * T.n_small.get_noise_2d(p.x, p.y))
		# dirt roads and the village plaza
		var rd := T.road_dist(p)
		var w := 1.0 - smoothstep(2.3, 3.8, rd)
		w = maxf(w, 1.0 - smoothstep(15.0, 19.0, p.distance_to(T.village)))
		if not T.in_yard(p, -2.0):
			c = c.lerp(dirt.lerp(Color(0.78, 0.78, 0.8), sn).lerp(Color(0.72, 0.58, 0.4), de), w)
		# the outer towns' squares
		for f in T.flats:
			if f[1] > 20.0:
				c = c.lerp(dirt.lerp(Color(0.8, 0.8, 0.82), sn).lerp(Color(0.74, 0.6, 0.42), de), (1.0 - smoothstep(f[1] * 0.25, f[1] * 0.35, p.distance_to(f[0]))) * 0.8)
	if h < 0.0:
		c = c.lerp(Color(0.5, 0.56, 0.5), clampf(-h / 4.0, 0.0, 1.0))
	return c


func build_terrain() -> void:
	var n := int(HALF * 2.0 / CELL) + 1
	var hs := PackedFloat32Array()
	hs.resize(n * n)
	for j in n:
		for i in n:
			hs[j * n + i] = T.height(-HALF + i * CELL, -HALF + j * CELL)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(n * n); norms.resize(n * n); cols.resize(n * n)
	for j in n:
		for i in n:
			var k := j * n + i
			var x := -HALF + i * CELL
			var z := -HALF + j * CELL
			var h := hs[k]
			var hx := hs[j * n + mini(i + 1, n - 1)] - hs[j * n + maxi(i - 1, 0)]
			var hz := hs[mini(j + 1, n - 1) * n + i] - hs[maxi(j - 1, 0) * n + i]
			var nrm := Vector3(-hx, 2.0 * CELL, -hz).normalized()
			verts[k] = Vector3(x, h, z)
			norms[k] = nrm
			cols[k] = terrain_color(Vector2(x, z), h, Vector2(hx, hz).length() / (2.0 * CELL))
	# a generated noise texture gives the flat vertex colours some grain
	var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
	var nz := FastNoiseLite.new()
	nz.seed = 3; nz.frequency = 0.09
	for y in 256:
		for x in 256:
			var v := 0.82 + 0.18 * nz.get_noise_2d(x, y) + rng.randf_range(-0.04, 0.04)
			img.set_pixel(x, y, Color(v, v, v))
	img.save_png("res://textures/terrain_detail.png")
	var tex := ImageTexture.create_from_image(img)
	ResourceSaver.save(tex, "res://textures/terrain_detail.tres")
	var sh := Shader.new()
	sh.code = """shader_type spatial;
uniform sampler2D detail : repeat_enable, filter_linear_mipmap;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float d = texture(detail, wpos.xz * 0.11).r * 0.6 + texture(detail, wpos.xz * 0.017).r * 0.4;
	ALBEDO = COLOR.rgb * (0.7 + d * 0.4);
	ROUGHNESS = 0.92;
}"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("detail", load("res://textures/terrain_detail.tres"))
	ResourceSaver.save(mat, "res://meshes/terrain_material.tres")
	var g := group("Terrain")
	# the mesh, in CHUNKS x CHUNKS pieces so the renderer can skip the ones out of view
	var per := (n - 1) / CHUNKS
	var tris := 0
	for cj in CHUNKS:
		for ci in CHUNKS:
			var cv := PackedVector3Array()
			var cn := PackedVector3Array()
			var cc := PackedColorArray()
			var ix := PackedInt32Array()
			var w := per + 1
			for j in range(cj * per, cj * per + w):
				for i in range(ci * per, ci * per + w):
					var k := j * n + i
					cv.append(verts[k]); cn.append(norms[k]); cc.append(cols[k])
			for j in per:
				for i in per:
					var a := j * w + i
					ix.append_array([a, a + 1, a + w, a + 1, a + w + 1, a + w])
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = cv
			arr[Mesh.ARRAY_NORMAL] = cn
			arr[Mesh.ARRAY_COLOR] = cc
			arr[Mesh.ARRAY_INDEX] = ix
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			am.surface_set_material(0, load("res://meshes/terrain_material.tres"))
			var path := "res://meshes/terrain_%d_%d.res" % [ci, cj]
			ResourceSaver.save(am, path)
			var mi := MeshInstance3D.new()
			mi.name = "TerrainMesh_%d_%d" % [ci, cj]
			mi.mesh = load(path)
			g.add_child(mi)
			tris += ix.size() / 3
	# collision: a height field on the same grid
	var hm := HeightMapShape3D.new()
	hm.map_width = n
	hm.map_depth = n
	hm.map_data = hs
	ResourceSaver.save(hm, "res://meshes/terrain_heightmap.res")
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	g.add_child(body)
	var cs := CollisionShape3D.new()
	cs.shape = load("res://meshes/terrain_heightmap.res")
	cs.scale = Vector3(CELL, 1.0, CELL)
	body.add_child(cs)
	counts["terrain_triangles"] = tris


# ----------------------------------------------------------------------------- water

func water_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.12
	m.metallic = 0.25
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func build_water() -> void:
	var g := group("Water")
	var ocean := MeshInstance3D.new()
	ocean.name = "Ocean"
	var pm := PlaneMesh.new()
	pm.size = Vector2(6000, 6000)
	pm.material = water_material(Color(0.1, 0.42, 0.72, 0.88))
	ocean.mesh = pm
	g.add_child(ocean)
	# lake: a disc at the lake level
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 40
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var r := T.lake_r + 9.0
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(T.lake.x, T.LAKE_LEVEL, T.lake.y))
		st.add_vertex(Vector3(T.lake.x + cos(a1) * r, T.LAKE_LEVEL, T.lake.y + sin(a1) * r))
		st.add_vertex(Vector3(T.lake.x + cos(a0) * r, T.LAKE_LEVEL, T.lake.y + sin(a0) * r))
	var lake := MeshInstance3D.new()
	lake.name = "Lake"
	var lm := st.commit()
	lm.surface_set_material(0, water_material(Color(0.14, 0.5, 0.8, 0.8)))
	lake.mesh = lm
	g.add_child(lake)
	# river: a ribbon that follows the channel and falls from the lake level to the sea
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 320
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for i in steps + 1:
		var t := float(i) / steps
		var p := T.river_point(t)
		var d := (T.river_point(minf(t + 0.01, 1.0)) - T.river_point(maxf(t - 0.01, 0.0))).normalized()
		var side := Vector2(-d.y, d.x) * 11.5
		var y := T.water_level(t) + 0.02
		var l := Vector3(p.x - side.x, y, p.y - side.y)
		var r2 := Vector3(p.x + side.x, y, p.y + side.y)
		if i > 0:
			st.set_normal(Vector3.UP)
			for v in [prev_l, prev_r, r2, prev_l, r2, l]:
				st.add_vertex(v)
		prev_l = l
		prev_r = r2
	var river := MeshInstance3D.new()
	river.name = "River"
	var rm := st.commit()
	rm.surface_set_material(0, water_material(Color(0.14, 0.52, 0.82, 0.8)))
	river.mesh = rm
	g.add_child(river)
	# water volumes for gameplay (swimming): one Area per body of water
	var area := Area3D.new()
	area.name = "OceanArea"
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2600, 20, 2600)
	cs.shape = bs
	cs.position = Vector3(0, -10, 0)
	area.add_child(cs)
	area.set_meta("water", true)
	g.add_child(area)


# ----------------------------------------------------------------------------- bridges

func build_bridges() -> void:
	var g := group("Bridges")
	var wood := Color(0.62, 0.42, 0.2)
	var wood_d := Color(0.48, 0.31, 0.14)
	var idx := 0
	for c in [Terrain.px(758, 422), Terrain.px(765, 768), Vector2(98, 300)]:
		idx += 1
		var ri := T.river_info(c)
		var mid := T.river_point(ri.y)
		var dir := (T.river_point(minf(ri.y + 0.01, 1.0)) - T.river_point(maxf(ri.y - 0.01, 0.0))).normalized()
		var across := Vector2(-dir.y, dir.x)
		var length := 30.0
		var deck_y := maxf(ground(mid.x + across.x * 15.0, mid.y + across.y * 15.0), ground(mid.x - across.x * 15.0, mid.y - across.y * 15.0)) + 0.25
		var b := Node3D.new()
		b.name = "Bridge_%02d" % idx
		g.add_child(b)
		b.position = Vector3(mid.x, deck_y, mid.y)
		b.rotation.y = atan2(-across.y, across.x)             # local +X runs across the river
		var planks := 20
		for i in planks:
			var x := -length / 2 + length * (i + 0.5) / planks
			box_node(b, "Plank", Vector3(length / planks - 0.08, 0.22, 5.2), wood if i % 2 else wood_d, Transform3D(Basis.IDENTITY, Vector3(x, 0, 0)), false)
		var deck := BoxShape3D.new()
		deck.size = Vector3(length, 0.3, 5.2)
		add_collider(b, deck, Transform3D.IDENTITY, "DeckCollider")
		for s in [-1, 1]:
			box_node(b, "Beam", Vector3(length, 0.35, 0.3), wood_d, Transform3D(Basis.IDENTITY, Vector3(0, -0.25, s * 2.2)), false)
			box_node(b, "Rail", Vector3(length, 0.16, 0.16), wood, Transform3D(Basis.IDENTITY, Vector3(0, 1.05, s * 2.5)))
			for i in 7:
				var x2 := -length / 2 + length * i / 6.0
				box_node(b, "Post", Vector3(0.26, 1.5, 0.26), wood_d, Transform3D(Basis.IDENTITY, Vector3(x2, 0.45, s * 2.5)), false)
				if i % 2 == 0:
					box_node(b, "Pile", Vector3(0.4, 5.0, 0.4), wood_d, Transform3D(Basis.IDENTITY, Vector3(x2, -2.6, s * 2.2)), false)
		block(mid, 17.0)
		count("bridge")


# ----------------------------------------------------------------------------- village (centre)

const HOUSE_SOLID := ["house_shell", "house_roof", "house_porch", "house_stairs", "house_chimney", "house_trim", "house_door_frame", "house_furniture"]


func place_house(parent: Node, p: Vector2, yaw: float, name: String, look := "") -> Node3D:
	var h := place_asset("house", parent, at(p.x, p.y, 0.0), yaw, name, HOUSE_SOLID, ["house_door"])       # furniture needs exact colliders: one hull would span both floors
	block(p, 8.5)
	buildings.append([p, 5.0, yaw])
	if look == "snow":
		(h.get_node("house_roof") as MeshInstance3D).mesh = meshes[variant("house_roof", "snow", snowy)]
	elif look == "sand":
		(h.get_node("house_shell") as MeshInstance3D).mesh = meshes[variant("house_shell", "sand", func(c: Color, _n: Vector3) -> Color: return c.lerp(Color(0.86, 0.72, 0.52), 0.65))]
		(h.get_node("house_roof") as MeshInstance3D).mesh = meshes[variant("house_roof", "sand", func(c: Color, _n: Vector3) -> Color: return c.lerp(Color(0.72, 0.38, 0.24), 0.6))]
	return h


func build_village() -> void:
	var g := group("Zone_Center_Village")
	var c := T.village
	var n := 7
	var chest_i := 0
	for i in n:
		var a := TAU * (i + 0.5) / n
		var p := c + Vector2(cos(a), sin(a)) * 37.0
		var yaw := yaw_to(p, c)
		var house := place_house(g, p, yaw, "House_%02d" % (i + 1))
		if i < 5:                                              # treasure chests inside the houses
			chest_i += 1
			var chest := place_asset("chest", house, Vector3(-2.4, 0.16, -1.9), PI * 0.5, "Chest_%02d" % chest_i, [], ["chest_base"])
			chest.set_meta("loot", "chest")
		# a little yard clutter
		var side := Vector2(cos(a + 0.35), sin(a + 0.35)) * 28.0 + c
		place_single("farm_barrel", g, at(side.x, side.y), rng.randf() * TAU, 1.0, true)
		place_single("farm_crate", g, at(side.x + 1.2, side.y + 0.6), rng.randf() * TAU, 1.0, true)
	# plaza: a big oak in a ring of rocks, and a few benches made of crates
	place_single("tree_oak", g, at(c.x, c.y), 0.6, 1.15, false, "PlazaOak")
	add_tree_collider(g, at(c.x, c.y), 0.45)
	block(c, 6.0)
	for i in 8:
		var a2 := TAU * i / 8.0
		var q := c + Vector2(cos(a2), sin(a2)) * 4.6
		place_single("rock_small", g, at(q.x, q.y, -0.25), rng.randf() * TAU, 0.9, true)
	block(c, 56.0)                                             # keep the forest out of the village


# ----------------------------------------------------------------------------- farm (north-east)

func fence_line(parent: Node, a: Vector2, b: Vector2, gap_at := -1) -> void:
	var n := int(round(a.distance_to(b) / 2.0))
	var d := (b - a) / n
	var yaw := atan2(-d.y, d.x)
	for i in n:
		if i == gap_at:
			continue
		var p := a + d * (i + 0.5)
		place_single("farm_fence", parent, at(p.x, p.y, -0.05), yaw, 1.0, true)


func build_farm() -> void:
	var g := group("Zone_NorthEast_Farm")
	var fh := Terrain.px(960, 240)
	place_house(g, fh, yaw_to(fh, T.farm), "Farmhouse")
	var crops := group("Crops", g)
	for f in T.fields:
		var c: Vector2 = f[0]
		var hs: Vector2 = f[1]
		# fence around each field, with a gate gap on the south side
		fence_line(g, c + Vector2(-hs.x - 1, -hs.y - 1), c + Vector2(hs.x + 1, -hs.y - 1))
		fence_line(g, c + Vector2(-hs.x - 1, hs.y + 1), c + Vector2(hs.x + 1, hs.y + 1), int(hs.x / 2))
		fence_line(g, c + Vector2(-hs.x - 1, -hs.y - 1), c + Vector2(-hs.x - 1, hs.y + 1))
		fence_line(g, c + Vector2(hs.x + 1, -hs.y - 1), c + Vector2(hs.x + 1, hs.y + 1))
		# crop rows (procedural, instanced)
		var col: Color = f[2]
		var bm := box_mesh(Vector3(0.55, 0.6, 0.55), col.lightened(0.12))
		var xfs: Array = []
		var x := -hs.x + 1.0
		while x < hs.x - 0.5:
			var z := -hs.y + 1.0
			while z < hs.y - 0.5:
				var p := c + Vector2(x, z)
				var sc := rng.randf_range(0.7, 1.2)
				xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1, sc, 1)), at(p.x, p.y, 0.15 * sc)))
				z += 1.3
			x += 1.3
		instanced(bm, crops, xfs, "CropRows")
		count("crop_plants", xfs.size())
		block(c, maxf(hs.x, hs.y) + 4.0)
	# barrels, crates and hay-coloured stacks around the yard
	for i in 14:
		var p2 := T.farm + Vector2(rng.randf_range(-34, 34), rng.randf_range(-34, 34))
		if not is_free(p2, 1.2):
			continue
		if i % 2 == 0:
			place_single("farm_barrel", g, at(p2.x, p2.y), rng.randf() * TAU, 1.0, true)
		else:
			place_single("farm_crate", g, at(p2.x, p2.y), rng.randf() * TAU, 1.0, true)
			if rng.randf() < 0.4:
				place_single("farm_crate", g, at(p2.x, p2.y, 0.8), rng.randf() * TAU, 0.9, true)
		block(p2, 1.4)


# ----------------------------------------------------------------------------- industrial yard (south-west)

const WAREHOUSE_SOLID := ["warehouse_shell", "warehouse_roof", "warehouse_frame"]


func build_industrial() -> void:
	var g := group("Zone_SouthWest_Industrial")
	var yaw := -T.yard_rot + PI * 0.5
	var spots := [Terrain.px(290, 790), Terrain.px(445, 878), Terrain.px(315, 935)]
	for i in 3:
		var p: Vector2 = spots[i]
		place_asset("warehouse", g, at(p.x, p.y, 0.05), yaw + (PI if i == 1 else 0.0), "Warehouse_%02d" % (i + 1), WAREHOUSE_SOLID,
				["warehouse_door", "warehouse_crates"], ["warehouse_roller_door"] if i == 0 else [])
		block(p, 10.5)
		buildings.append([p, 8.0, yaw])
	# crates and ammo boxes around the yard
	var placed := 0
	var tries := 0
	while placed < 26 and tries < 600:
		tries += 1
		var q := T.yard + Vector2(rng.randf_range(-48, 48), rng.randf_range(-36, 36)).rotated(T.yard_rot)
		if not T.in_yard(q, -3.0) or not is_free(q, 1.3, 0.0):
			continue
		place_single("farm_crate", g, at(q.x, q.y), rng.randf() * TAU, rng.randf_range(1.0, 1.35), true)
		if rng.randf() < 0.35:
			place_single("farm_crate", g, at(q.x + 0.15, q.y - 0.1, 0.8 * 1.15), rng.randf() * TAU, 1.0, true)
		block(q, 1.6)
		placed += 1
	# a small fort from the modular kit: 2 x 2 cells, brick walls, wood floor on top, a metal ramp and two roofs
	var fort := group("Fort", g)
	var fc := T.yard + Vector2(30, -20).rotated(T.yard_rot)
	fort.position = at(fc.x, fc.y)
	fort.rotation.y = -T.yard_rot
	block(fc, 11.0)
	var walls := [[-2, -4, 0.0], [2, -4, 0.0], [-2, 4, 0.0], [2, 4, 0.0], [-4, -2, PI / 2], [-4, 2, PI / 2], [4, -2, PI / 2]]   # the (4, 2) side is the doorway
	for w in walls:
		kit_piece(fort, "kit_wall_brick", Vector3(w[0], 0, w[1]), w[2])
	for cx in [-2, 2]:
		for cz in [-2, 2]:
			kit_piece(fort, "kit_floor_wood", Vector3(cx, 4.0, cz), 0.0)
	kit_piece(fort, "kit_ramp_metal", Vector3(-2, 0, 6), 0.0)             # climbs towards -Z onto the roof
	kit_piece(fort, "kit_cone_metal", Vector3(2, 4.25, -2), 0.0)
	kit_piece(fort, "kit_cone_wood", Vector3(2, 4.25, 2), 0.0)
	kit_piece(fort, "kit_wall_wood", Vector3(-2, 4.25, -4), 0.0)
	kit_piece(fort, "kit_wall_metal", Vector3(-4, 4.25, -2), PI / 2)


func kit_piece(parent: Node, obj: String, pos: Vector3, yaw: float) -> void:
	var mi := mesh_node(obj, parent, Transform3D(Basis(Vector3.UP, yaw), pos))
	add_collider(mi, trimesh(obj))
	count(obj)


# ----------------------------------------------------------------------------- towers

func build_towers() -> void:
	var g := group("Towers")
	for i in T.towers.size():
		var p: Vector2 = T.towers[i]
		place_asset("lookout_tower", g, at(p.x, p.y, -0.1), yaw_to(p, T.village), "LookoutTower_%02d" % (i + 1), ["tower_frame", "tower_roof", "tower_ladder"])
		block(p, 5.5)
		buildings.append([p, 2.5, 0.0])
	for i in T.extra_towers.size():
		var q: Vector2 = T.extra_towers[i]
		place_asset("lookout_tower", g, at(q.x, q.y, -0.1), yaw_to(q, Vector2.ZERO), "LookoutTower_%02d" % (T.towers.size() + i + 1), ["tower_frame", "tower_roof", "tower_ladder"])
		block(q, 5.5)
		buildings.append([q, 2.5, 0.0])


# ----------------------------------------------------------------------------- forests

func add_tree_collider(parent: Node3D, pos: Vector3, radius: float, height := 4.5) -> void:
	var key := "trunk_%.2f_%.1f" % [radius, height]
	if not shapes.has(key):
		var cyl := CylinderShape3D.new()
		cyl.radius = radius
		cyl.height = height
		shapes[key] = cyl
	var body: StaticBody3D = parent.get_node_or_null("TrunkColliders")
	if body == null:
		body = StaticBody3D.new()
		body.name = "TrunkColliders"
		parent.add_child(body)
	var cs := CollisionShape3D.new()
	cs.shape = shapes[key]
	cs.position = pos + Vector3(0, height / 2, 0)
	body.add_child(cs)


func forest(g: Node3D, obj: String, want: int, region: Callable, spacing: float, trunk_r: float, keep: Callable = Callable()) -> int:
	var xfs: Array = []
	var tries := 0
	var dot := Color(0.12, 0.3, 0.1) if obj != "cactus" else Color(0.25, 0.45, 0.2)
	if obj.ends_with("_snow"):
		dot = Color(0.3, 0.42, 0.36)
	while xfs.size() < want and tries < want * 60:
		tries += 1
		var p: Vector2 = region.call()
		if keep.is_valid() and not keep.call(p):
			continue
		if not is_free(p, spacing * 0.5):
			continue
		tree_pts.append([p, dot])
		var sc := rng.randf_range(0.8, 1.25)
		var pos := at(p.x, p.y, -0.1)
		xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), pos))
		add_tree_collider(g, pos, trunk_r * sc)
		block(p, spacing * 0.5)
	multimesh(obj, g, xfs, obj.capitalize().replace(" ", "") + "s")
	return xfs.size()


func build_forests() -> void:
	var north := group("Zone_North_PineForest")
	counts["pines"] = forest(north, "tree_pine", 175, func(): return Vector2(rng.randf_range(-175, 75), rng.randf_range(-200, -62)), 5.2, 0.32)
	# rock clusters in the north, including the moss rocks
	for i in 34:
		var p := Vector2(rng.randf_range(-170, 80), rng.randf_range(-195, -65))
		if not is_free(p, 1.5):
			continue
		var kinds := ["rock_medium_moss", "rock_wide_moss", "rock_tall", "rock_small", "rock_medium_moss"]
		for k in rng.randi_range(2, 4):
			var q := p + Vector2(rng.randf_range(-2.4, 2.4), rng.randf_range(-2.4, 2.4))
			place_single(kinds[rng.randi() % kinds.size()], north, at(q.x, q.y, -0.2), rng.randf() * TAU, rng.randf_range(0.8, 1.25), true)
		block(p, 3.6)
	var west := group("Zone_West_OakForest")
	# clearings: a few keep-clear circles before planting
	for c in [Vector2(-150, -15), Vector2(-120, 20), Vector2(-165, 25)]:
		block(c, 9.0)
	counts["oaks"] = forest(west, "tree_oak", 132, func(): return Vector2(rng.randf_range(-196, -62), rng.randf_range(-78, 34)), 6.2, 0.36)
	var east := group("Zone_East_Beach")
	counts["palms"] = forest(east, "tree_palm", 36, func(): return Vector2(rng.randf_range(148, 200), rng.randf_range(-125, 170)), 7.0, 0.26)
	var wild := group("Zone_Wild")
	counts["wild_oaks"] = forest(wild, "tree_oak", 46, func(): return Vector2(rng.randf_range(-70, 150), rng.randf_range(-50, 175)), 9.0, 0.36)


# ----------------------------------------------------------------------------- the new country around the stage 2 island

func town(g: Node3D, c: Vector2, n: int, r: float, prefix: String, look: String, chests: int) -> void:
	## A ring of houses facing a little square, with chests inside some of them.
	var start := rng.randf() * TAU
	for i in n:
		var a := start + TAU * (i + 0.5) / n
		var p := c + Vector2(cos(a), sin(a)) * r
		var house := place_house(g, p, yaw_to(p, c), "House_%s%02d" % [prefix, i + 1], look)
		if i < chests:
			var chest := place_asset("chest", house, Vector3(-2.4, 0.16, -1.9), PI * 0.5, "Chest_%s%02d" % [prefix, i + 1], [], ["chest_base"])
			chest.set_meta("loot", "chest")
		var side := c + Vector2(cos(a + 0.4), sin(a + 0.4)) * (r * 0.72)
		place_single("farm_barrel", g, at(side.x, side.y), rng.randf() * TAU, 1.0, true)
		place_single("farm_crate", g, at(side.x + 1.2, side.y + 0.6), rng.randf() * TAU, 1.0, true)
	block(c, r + 12.0)


func rand_in(x0: float, x1: float, z0: float, z1: float) -> Callable:
	return func() -> Vector2: return Vector2(rng.randf_range(x0, x1), rng.randf_range(z0, z1))


func build_outer() -> void:
	# --- the snowy north: a mountain village, snow-dusted pines and rocks
	var north := group("Zone_Far_North_Snow")
	town(north, T.snow_town, 6, 24.0, "N", "snow", 4)
	var snowy_pine := variant("tree_pine", "snow", snowy)
	var pines := group("SnowPines", north)
	counts["snow_pines"] = forest(pines, snowy_pine, 300, rand_in(-REACH, REACH, -REACH, -200.0), 5.6, 0.32, func(p: Vector2) -> bool: return T.snow(p) > 0.55)
	for i in 46:
		var p := Vector2(rng.randf_range(-REACH, REACH), rng.randf_range(-REACH, -215.0))
		if T.snow(p) < 0.6 or not is_free(p, 1.5):
			continue
		for k in rng.randi_range(2, 4):
			var q := p + Vector2(rng.randf_range(-2.6, 2.6), rng.randf_range(-2.6, 2.6))
			var kind: String = ["rock_medium_moss", "rock_wide_moss", "rock_tall", "rock_small"][rng.randi() % 4]
			place_single(variant(kind, "snow", snowy), north, at(q.x, q.y, -0.2), rng.randf() * TAU, rng.randf_range(0.9, 1.5), true)
		block(p, 3.8)
	# --- the desert south: a sandstone town, a depot, cacti, palms along the oasis river and dry scrub
	var south := group("Zone_Far_South_Desert")
	town(south, T.desert_town, 6, 24.0, "S", "sand", 4)
	var depot := group("Depot", south)
	for i in 2:
		var wp: Vector2 = T.depot + Vector2(-11.0 + i * 22.0, 0.0)
		place_asset("warehouse", depot, at(wp.x, wp.y, 0.05), PI * 0.5 + i * PI, "Warehouse_%02d" % (4 + i), WAREHOUSE_SOLID, ["warehouse_door", "warehouse_crates"])
		block(wp, 10.5)
		buildings.append([wp, 8.0, PI * 0.5])
	for i in 14:
		var q2 := T.depot + Vector2(rng.randf_range(-30, 30), rng.randf_range(-26, 26))
		if not is_free(q2, 1.3, 0.0):
			continue
		place_single("farm_crate", depot, at(q2.x, q2.y), rng.randf() * TAU, rng.randf_range(1.0, 1.3), true)
		block(q2, 1.6)
	block(T.depot, 34.0)
	var cacti := group("Cacti", south)
	counts["cacti"] = forest(cacti, "cactus", 170, rand_in(-REACH, REACH, 215.0, REACH), 6.0, 0.34,
			func(p: Vector2) -> bool: return T.desert(p) > 0.6 and T.river_info(p).x > 30.0)
	var oasis := group("OasisPalms", south)
	counts["oasis_palms"] = forest(oasis, "tree_palm", 46, func() -> Vector2: return T.river_point(rng.randf_range(0.66, 0.97)) + Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30)), 6.5, 0.26,
			func(p: Vector2) -> bool: return T.desert(p) > 0.4 and T.river_info(p).x > 12.0 and T.river_info(p).x < 32.0)
	var dry := variant("bush_plain", "dry", func(c: Color, _n: Vector3) -> Color: return c.lerp(Color(0.6, 0.52, 0.3), 0.7))
	var xfs: Array = []
	var tries := 0
	while xfs.size() < 110 and tries < 6000:
		tries += 1
		var p3 := Vector2(rng.randf_range(-REACH, REACH), rng.randf_range(215.0, REACH))
		if T.desert(p3) < 0.6 or not is_free(p3, 1.0):
			continue
		xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.1)), at(p3.x, p3.y, -0.05)))
		block(p3, 1.0)
	multimesh(dry, south, xfs, "DryBushes")
	for m in T.mesas:                                       # boulders at the foot of each mesa
		for k in 7:
			var a := rng.randf() * TAU
			var q3: Vector2 = m[0] + Vector2(cos(a), sin(a)) * (float(m[1]) + rng.randf_range(2.0, 6.0))
			if is_free(q3, 1.5):
				var kind2: String = ["rock_tall", "rock_small", "rock_small_flat"][rng.randi() % 3]
				place_single(variant(kind2, "sand", func(c: Color, _n: Vector3) -> Color: return c.lerp(Color(0.72, 0.45, 0.3), 0.6)), south, at(q3.x, q3.y, -0.2), rng.randf() * TAU, rng.randf_range(1.0, 1.6), true)
				block(q3, 2.2)
	# --- green country east and west: two hamlets, woods and a palm-lined east coast
	var west := group("Zone_Far_West")
	town(west, T.west_hamlet, 4, 20.0, "W", "", 2)
	var westwood := group("WestOaks", west)
	counts["west_oaks"] = forest(westwood, "tree_oak", 150, rand_in(-REACH, -200.0, -200.0, 215.0), 6.4, 0.36,
			func(p: Vector2) -> bool: return T.outer(p) > 0.8 and T.snow(p) < 0.2 and T.desert(p) < 0.2)
	var east := group("Zone_Far_East")
	town(east, T.east_cove, 4, 20.0, "E", "", 2)
	var eastwood := group("EastOaks", east)
	counts["east_oaks"] = forest(eastwood, "tree_oak", 90, rand_in(200.0, REACH, -200.0, 215.0), 7.0, 0.36,
			func(p: Vector2) -> bool: return T.outer(p) > 0.8 and T.coast(p) > 40.0 and T.snow(p) < 0.2 and T.desert(p) < 0.2)
	var coastp := group("EastCoastPalms", east)
	counts["coast_palms"] = forest(coastp, "tree_palm", 60, rand_in(240.0, REACH + 20.0, -220.0, 230.0), 7.0, 0.26,
			func(p: Vector2) -> bool: return T.coast(p) > 6.0 and T.coast(p) < 40.0 and T.desert(p) < 0.3 and T.snow(p) < 0.3)


# ----------------------------------------------------------------------------- bushes and rocks everywhere

func build_scatter() -> void:
	var g := group("Scatter")
	for obj in ["bush_plain", "bush_berry"]:
		var xfs: Array = []
		var tries := 0
		var want := 330 if obj == "bush_plain" else 150
		while xfs.size() < want and tries < 20000:
			tries += 1
			var p := Vector2(rng.randf_range(-REACH, REACH), rng.randf_range(-REACH, REACH))
			if not is_free(p, 1.0) or T.in_yard(p, 2.0) or T.snow(p) > 0.4 or T.desert(p) > 0.4:
				continue
			tree_pts.append([p, Color(0.2, 0.42, 0.16)])
			xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.25)), at(p.x, p.y, -0.05)))
			block(p, 1.0)
		multimesh(obj, g, xfs, obj.capitalize().replace(" ", "") + "s")
	var kinds := ["rock_small_flat", "rock_small", "rock_tall", "rock_medium_moss", "rock_wide_moss", "rock_small"]
	var placed := 0
	var tries2 := 0
	while placed < 230 and tries2 < 14000:
		tries2 += 1
		var p2 := Vector2(rng.randf_range(-REACH, REACH), rng.randf_range(-REACH, REACH))
		# more rocks on the hills and along the south and west coasts
		var keep := 0.25
		for t in T.towers:
			if p2.distance_to(t) < 40.0:
				keep = 1.0
		if T.coast(p2) < 22.0 and p2.x < 120.0:
			keep = 1.0
		if rng.randf() > keep or T.in_yard(p2, 2.0) or ground(p2.x, p2.y) < 0.9:
			continue
		if not is_free(p2, 1.6):
			continue
		var kind: String = kinds[rng.randi() % kinds.size()]
		if T.snow(p2) > 0.5:
			kind = variant(kind, "snow", snowy)
		elif T.desert(p2) > 0.5:
			kind = variant(kind, "sand", func(c: Color, _n: Vector3) -> Color: return c.lerp(Color(0.72, 0.45, 0.3), 0.6))
		place_single(kind, g, at(p2.x, p2.y, -0.2), rng.randf() * TAU, rng.randf_range(0.8, 1.25), true)
		block(p2, 2.0)
		placed += 1
	# sea rocks just off the coast
	for i in 70:
		var a := rng.randf() * TAU
		var dir := Vector2(cos(a), sin(a))
		var r := 330.0
		while T.coast(dir * r) > -10.0 and r < 560.0:
			r += 3.0
		var q := dir * (r + rng.randf_range(0.0, 14.0))
		place_single(["rock_tall", "rock_small", "rock_medium_moss"][rng.randi() % 3], g, Vector3(q.x, maxf(ground(q.x, q.y), -1.6) - 0.3, q.y), rng.randf() * TAU,
				rng.randf_range(1.1, 1.8), true, "SeaRock")


# ----------------------------------------------------------------------------- loot

func loot_item(g: Node3D, id: String, p: Vector2, kind: String, lift := 0.0, hulls: Array = []) -> Node3D:
	var n := place_asset(id, g, at(p.x, p.y, lift), rng.randf() * TAU, "Loot_%s_%02d" % [kind, counts.get("loot_" + kind, 0) + 1], [], hulls)
	n.set_meta("loot", kind)
	n.add_to_group("loot", true)
	count("loot_" + kind)
	block(p, 1.2)
	return n


func free_spot(region: Callable, r := 1.0, road_gap := 2.0) -> Vector2:
	for i in 400:
		var p: Vector2 = region.call()
		if is_free(p, r, road_gap):
			return p
	return Vector2(0, 40)


func build_loot() -> void:
	var g := group("Loot")
	var anywhere := func(): return Vector2(rng.randf_range(-REACH, REACH), rng.randf_range(-REACH, REACH))
	# treasure chests outside the village: towers, warehouses, farm and the wild
	for t in T.towers:
		loot_item(g, "chest", free_spot(func(): return t + Vector2(rng.randf_range(-9, 9), rng.randf_range(-9, 9))), "chest", 0.0, ["chest_base"])
	for t in T.extra_towers:
		loot_item(g, "chest", free_spot(func(): return t + Vector2(rng.randf_range(-9, 9), rng.randf_range(-9, 9))), "chest", 0.0, ["chest_base"])
	for i in 14:
		loot_item(g, "chest", free_spot(anywhere), "chest", 0.0, ["chest_base"])
	for i in 6:
		loot_item(g, "ammo_box", free_spot(func(): return T.depot + Vector2(rng.randf_range(-28, 28), rng.randf_range(-24, 24)), 0.8, 0.0), "ammo_box", 0.0, ["ammo_box_base"])
	# ammo boxes: the yard and across the island
	for i in 8:
		loot_item(g, "ammo_box", free_spot(func(): return T.yard + Vector2(rng.randf_range(-46, 46), rng.randf_range(-34, 34)).rotated(T.yard_rot), 0.8, 0.0), "ammo_box", 0.0, ["ammo_box_base"])
	for i in 22:
		loot_item(g, "ammo_box", free_spot(anywhere), "ammo_box", 0.0, ["ammo_box_base"])
	for i in 24:
		loot_item(g, "medkit", free_spot(anywhere), "medkit")
	for i in 24:
		loot_item(g, "shield_potion", free_spot(anywhere), "shield_potion")
	# every weapon type on the ground, eight of each
	for id in ["pistol", "shotgun", "assault_rifle", "sniper_rifle", "rocket_launcher", "grenade"]:
		for i in 8:
			var n := loot_item(g, id, free_spot(anywhere), id, 0.12 if id == "grenade" else 0.3)
			if id != "grenade":
				n.rotation.z = PI / 2                         # lying on its side
	# one landed supply drop, parachute folded away
	var sp := free_spot(func(): return Vector2(rng.randf_range(40, 110), rng.randf_range(20, 100)), 3.0)
	var drop := place_asset("supply_drop", g, at(sp.x, sp.y), 0.4, "SupplyDrop_Landed", [], ["supply_crate"])
	drop.get_node("supply_parachute").visible = false
	drop.set_meta("loot", "supply_drop")
	block(sp, 3.0)


# ----------------------------------------------------------------------------- sky

func build_sky() -> void:
	var g := group("Sky")
	var blimp := place_asset("drop_vehicle", g, Vector3(-120, ground(-120, -90) + 80.0, -90), deg_to_rad(125), "CargoBlimp")
	blimp.set_meta("flight_height", 80.0)


# ----------------------------------------------------------------------------- spawns

func build_spawns() -> void:
	var g := group("Spawns")
	var pts: Array = []
	var tries := 0
	var min_d := 90.0
	while pts.size() < 40 and tries < 30000:
		tries += 1
		if tries % 2500 == 0:
			min_d -= 5.0
		var p := Vector2(rng.randf_range(-REACH, REACH), rng.randf_range(-REACH, REACH))
		if not is_free(p, 1.5, 0.0) or ground(p.x, p.y) < 1.6:
			continue
		# walkable: not on a steep slope
		var slope := absf(ground(p.x + 1, p.y) - ground(p.x - 1, p.y)) + absf(ground(p.x, p.y + 1) - ground(p.x, p.y - 1))
		if slope > 0.9:
			continue
		var ok := true
		for q in pts:
			if p.distance_to(q) < min_d:
				ok = false
				break
		if not ok:
			continue
		pts.append(p)
	for i in pts.size():
		var m := Marker3D.new()
		m.name = "Spawn_%02d" % (i + 1)
		m.position = at(pts[i].x, pts[i].y, 0.1)
		m.rotation.y = yaw_to(pts[i], T.village)
		m.add_to_group("spawn", true)
		g.add_child(m)
	counts["spawns"] = pts.size()


# ----------------------------------------------------------------------------- minimap

const MAP_METRES := 900.0              # must match hud.gd: the minimap covers this many metres, centred on the island
const MAP_PX := 1024


func build_minimap() -> void:
	## A painted top view for the HUD: the terrain colours with hill shading, water, trees and buildings.
	var img := Image.create(MAP_PX, MAP_PX, false, Image.FORMAT_RGB8)
	var m := MAP_METRES / MAP_PX
	for j in MAP_PX:
		for i in MAP_PX:
			var x := -MAP_METRES / 2 + (i + 0.5) * m
			var z := -MAP_METRES / 2 + (j + 0.5) * m
			var h := ground(x, z)
			var c: Color
			var ws: float = T.water_surface(x, z)
			if ws > h:
				var depth := clampf((ws - h) / 6.0, 0.0, 1.0)
				c = Color(0.36, 0.66, 0.86).lerp(Color(0.12, 0.36, 0.66), depth)
			else:
				var hx := ground(x + 1.5, z) - ground(x - 1.5, z)
				var hz := ground(x, z + 1.5) - ground(x, z - 1.5)
				c = terrain_color(Vector2(x, z), h, Vector2(hx, hz).length() / 3.0)
				var shade := clampf(1.0 - (hx + hz) * 0.12, 0.65, 1.25)          # light from the north-west
				c = Color(c.r * shade, c.g * shade, c.b * shade)
			img.set_pixel(i, j, c)
	# trees and bushes as dots
	for t in tree_pts:
		var px: Vector2 = (t[0] + Vector2(MAP_METRES / 2, MAP_METRES / 2)) / m
		var col: Color = t[1]
		for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			var q: Vector2i = Vector2i(int(px.x), int(px.y)) + d
			if q.x >= 0 and q.y >= 0 and q.x < MAP_PX and q.y < MAP_PX:
				img.set_pixel(q.x, q.y, img.get_pixel(q.x, q.y).lerp(col, 0.55))
	# buildings as dark roofs
	for b in buildings:
		var cpos: Vector2 = b[0]
		var half: float = b[1]
		var yaw: float = b[2]
		var steps := int(half * 2.0 / m) + 2
		for a in steps:
			for k in steps:
				var local := Vector2(-half + a * m, -half + k * m)
				var wpt := cpos + local.rotated(-yaw)
				var q2 := Vector2i(int((wpt.x + MAP_METRES / 2) / m), int((wpt.y + MAP_METRES / 2) / m))
				if q2.x >= 0 and q2.y >= 0 and q2.x < MAP_PX and q2.y < MAP_PX:
					var edge := absf(local.x) > half - m * 1.5 or absf(local.y) > half - m * 1.5
					img.set_pixel(q2.x, q2.y, Color(0.2, 0.18, 0.17) if edge else Color(0.55, 0.32, 0.26))
	img.save_png("res://textures/minimap.png")
	print("MINIMAP saved")
