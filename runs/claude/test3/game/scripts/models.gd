## Instances stage 1 assets with the colour-corrected meshes saved by the level build.
class_name Models
extends RefCounted

static var _cache := {}


static func make(id: String) -> Node3D:
	match id:
		"small_shield":
			var sp := make("shield_potion")
			sp.scale = Vector3.ONE * 0.65
			var wrap := Node3D.new()
			wrap.add_child(sp)
			return wrap
		"healing_drink", "launch_pad", "apple", "mushroom":
			return _procedural(id)
	if not _cache.has(id):
		_cache[id] = load("res://assets/%s.glb" % id)
	var n: Node3D = _cache[id].instantiate()
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var p := "res://meshes/%s.res" % mi.name
		if ResourceLoader.exists(p):
			mi.mesh = load(p)
	return n


static func _part(parent: Node3D, mesh: Mesh, col: Color, pos: Vector3, emit := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.6
	if col.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emit
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _cyl(r: float, h: float, r2 := -1.0) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r if r2 < 0.0 else r2
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 14
	return c


static func _procedural(id: String) -> Node3D:
	## Small items that have no stage 1 model: built here from primitives in the same style.
	var n := Node3D.new()
	match id:
		"healing_drink":
			_part(n, _cyl(0.055, 0.17), Color(0.75, 0.9, 1.0, 0.35), Vector3(0, 0.085, 0))
			_part(n, _cyl(0.048, 0.13), Color(0.25, 0.85, 0.3), Vector3(0, 0.07, 0), 0.8)
			_part(n, _cyl(0.025, 0.06, 0.02), Color(0.75, 0.9, 1.0, 0.35), Vector3(0, 0.2, 0))
			_part(n, _cyl(0.022, 0.035), Color(0.72, 0.52, 0.3), Vector3(0, 0.235, 0))
			_part(n, _cyl(0.057, 0.05), Color(0.95, 0.95, 0.92), Vector3(0, 0.09, 0))
		"launch_pad":
			_part(n, _cyl(1.1, 0.16), Color(0.24, 0.26, 0.3), Vector3(0, 0.08, 0))
			_part(n, _cyl(0.95, 0.04), Color(0.2, 0.55, 1.0), Vector3(0, 0.18, 0), 1.2)
			for i in 3:
				var bm := BoxMesh.new()
				bm.size = Vector3(0.9 - i * 0.2, 0.03, 0.14)
				var arrow := _part(n, bm, Color(1.0, 0.82, 0.2), Vector3(0, 0.215, -0.35 + i * 0.3), 0.6)
				arrow.rotation.y = 0.0
		"apple":
			var s := SphereMesh.new()
			s.radius = 0.1
			s.height = 0.18
			_part(n, s, Color(0.85, 0.12, 0.1), Vector3(0, 0.09, 0))
			_part(n, _cyl(0.008, 0.06), Color(0.35, 0.22, 0.1), Vector3(0, 0.2, 0))
			var leaf := BoxMesh.new()
			leaf.size = Vector3(0.06, 0.008, 0.03)
			_part(n, leaf, Color(0.3, 0.7, 0.2), Vector3(0.03, 0.2, 0))
		"mushroom":
			_part(n, _cyl(0.035, 0.12), Color(0.95, 0.92, 0.85), Vector3(0, 0.06, 0))
			var cap := SphereMesh.new()
			cap.radius = 0.11
			cap.height = 0.11
			cap.is_hemisphere = true
			_part(n, cap, Color(0.3, 0.55, 0.95), Vector3(0, 0.11, 0), 0.25)
	return n


static func glow_material(c: Color, energy := 1.6, alpha := 0.55) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
