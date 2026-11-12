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
		"healing_drink", "launch_pad", "apple", "mushroom", "bandages", "hydro_juice", "mega_flask":
			return _procedural(id)
		"smg", "tactical_shotgun", "burst_rifle", "hunting_rifle":
			if not ResourceLoader.exists("res://assets/%s.glb" % id):
				return _variant(id)               # no stage 1 model yet: recoloured copy of an existing gun
	if not _cache.has(id):
		_cache[id] = load("res://assets/%s.glb" % id)
	var n: Node3D = _cache[id].instantiate()
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var p := "res://meshes/%s.res" % mi.name
		if ResourceLoader.exists(p):
			mi.mesh = load(p)
	return n


## New guns built from the stage 1 weapon meshes: base asset, scale, parts left out, and a tint per mesh name
## (multiplies the vertex colours; "*" is every other part).
const VARIANTS := {
	"smg": {"base": "assault_rifle", "scale": Vector3(0.92, 0.92, 0.6), "hide": ["rifle_lens"],
		"tint": {"rifle_body": Color(0.3, 0.42, 0.95), "rifle_metal": Color(0.7, 0.75, 0.95), "rifle_magazine": Color(1.0, 0.65, 0.3)}},
	"tactical_shotgun": {"base": "shotgun", "scale": Vector3(1.0, 1.0, 0.8), "hide": [],
		"tint": {"shotgun_body": Color(0.38, 0.38, 0.45), "shotgun_barrels": Color(0.55, 0.55, 0.6), "shotgun_pump": Color(1.0, 0.55, 0.3)}},
	"burst_rifle": {"base": "assault_rifle", "scale": Vector3(0.95, 0.95, 1.12), "hide": [],
		"tint": {"rifle_body": Color(0.5, 0.78, 0.55), "rifle_magazine": Color(0.65, 0.65, 0.7), "rifle_lens": Color(0.4, 1.0, 0.5)}},
	"hunting_rifle": {"base": "sniper_rifle", "scale": Vector3(1.0, 1.0, 0.82), "hide": ["sniper_scope"],
		"tint": {"sniper_body": Color(0.72, 0.5, 0.36), "sniper_metal": Color(0.62, 0.62, 0.66), "sniper_magazine": Color(0.8, 0.75, 0.7)}},
}
static var _tint_cache := {}


static func _variant(id: String) -> Node3D:
	var v: Dictionary = VARIANTS[id]
	var n := make(v.base)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name) in v.hide:
			mi.visible = false
		elif v.tint.has(String(mi.name)) and mi.mesh:
			var key := id + String(mi.name)
			if not _tint_cache.has(key):
				var m: StandardMaterial3D = (mi.mesh.surface_get_material(0) as StandardMaterial3D).duplicate()
				m.albedo_color = v.tint[String(mi.name)]
				_tint_cache[key] = m
			mi.material_override = _tint_cache[key]
	var wrap := Node3D.new()
	n.scale = v.scale
	wrap.add_child(n)
	return wrap


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
		"bandages":
			for k in 2:
				var rr := 0.085 - k * 0.012
				var x := -0.07 + k * 0.15
				_part(n, _cyl(rr, 0.075), Color(0.96, 0.95, 0.9), Vector3(x, 0.0375, 0.0 + k * 0.05))
				_part(n, _cyl(0.032, 0.08), Color(0.35, 0.3, 0.28), Vector3(x, 0.0375, 0.0 + k * 0.05))
				_part(n, _cyl(rr + 0.004, 0.022), Color(0.85, 0.15, 0.15), Vector3(x, 0.0375, 0.0 + k * 0.05))
			var tail := BoxMesh.new()
			tail.size = Vector3(0.11, 0.008, 0.05)
			_part(n, tail, Color(0.96, 0.95, 0.9), Vector3(0.0, 0.004, 0.11))
		"hydro_juice":
			var cup := _cyl(0.065, 0.2, 0.08)
			cup.radial_segments = 16
			_part(n, cup, Color(0.75, 0.92, 1.0, 0.35), Vector3(0, 0.1, 0))
			var cup_in := _cyl(0.057, 0.16, 0.07)
			_part(n, cup_in, Color(0.15, 0.75, 1.0), Vector3(0, 0.09, 0), 1.0)
			_part(n, _cyl(0.085, 0.025), Color(0.95, 0.95, 0.98), Vector3(0, 0.208, 0))
			_part(n, _cyl(0.068, 0.045), Color(1.0, 0.55, 0.15), Vector3(0, 0.05, 0))
			var straw := _part(n, _cyl(0.009, 0.2), Color(1.0, 0.9, 0.2), Vector3(0.02, 0.3, 0))
			straw.rotation.z = -0.2
		"mega_flask":
			var glass := SphereMesh.new()
			glass.radius = 0.15
			glass.height = 0.3
			_part(n, glass, Color(0.8, 0.95, 1.0, 0.3), Vector3(0, 0.15, 0))
			var liq := SphereMesh.new()
			liq.radius = 0.135
			liq.height = 0.27
			_part(n, liq, Color(0.3, 0.95, 0.55), Vector3(0, 0.15, 0), 1.0)
			var core := SphereMesh.new()
			core.radius = 0.07
			core.height = 0.14
			_part(n, core, Color(0.3, 0.6, 1.0), Vector3(0, 0.14, 0), 1.4)
			_part(n, _cyl(0.05, 0.08), Color(0.8, 0.95, 1.0, 0.3), Vector3(0, 0.33, 0))
			_part(n, _cyl(0.062, 0.025), Color(1.0, 0.75, 0.2), Vector3(0, 0.37, 0), 0.4)
			_part(n, _cyl(0.04, 0.05), Color(0.72, 0.52, 0.3), Vector3(0, 0.41, 0))
			var ring := TorusMesh.new()
			ring.inner_radius = 0.025
			ring.outer_radius = 0.05
			var handle := _part(n, ring, Color(1.0, 0.75, 0.2), Vector3(0.14, 0.3, 0), 0.4)
			handle.rotation.x = PI / 2
			_part(n, _cyl(0.1, 0.03), Color(1.0, 0.75, 0.2), Vector3(0, 0.015, 0), 0.4)
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
