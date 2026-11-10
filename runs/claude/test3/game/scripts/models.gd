## Instances stage 1 assets with the colour-corrected meshes saved by the level build.
class_name Models
extends RefCounted

static var _cache := {}


static func make(id: String) -> Node3D:
	if not _cache.has(id):
		_cache[id] = load("res://assets/%s.glb" % id)
	var n: Node3D = _cache[id].instantiate()
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var p := "res://meshes/%s.res" % mi.name
		if ResourceLoader.exists(p):
			mi.mesh = load(p)
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
