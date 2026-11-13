## Building, harvesting and destruction.
##
## Building: the 12 kit pieces (wall, floor, stairs, cone in wood, brick and metal) snap to a 4 m grid with
## 4 m storeys. A piece costs 10 of its material and its hit points climb while it builds (150 / 300 / 450).
## Pieces that touch each other form a support graph; when one breaks, every group that no longer reaches
## the ground collapses in a chain.
##
## Destruction: trees, rocks, fences, barrels, crates, doors, roofs, furniture, towers and the fort's kit
## pieces in the level all have hit points. Guns damage them, explosions do 2.5 times their damage, and the
## pickaxe harvests materials from them, with a blue weak point after every hit for double damage and yield.
class_name Structures
extends Node3D

const GRID := 4.0
const COST := 10
const MAX_MATS := 999
const PIECES := ["wall", "floor", "stairs", "cone"]
const PIECE_NAMES := {"wall": "Wall", "floor": "Floor", "stairs": "Stairs", "cone": "Cone"}
const PIECE_MESH := {"wall": "kit_wall_%s", "floor": "kit_floor_%s", "stairs": "kit_ramp_%s", "cone": "kit_cone_%s"}
const MATS := ["wood", "brick", "metal"]
const MAT_HP := {"wood": 150.0, "brick": 300.0, "metal": 450.0}
const BUILD_TIME := {"wood": 2.0, "brick": 3.5, "metal": 5.0}
const EXPLOSION_MULT := 2.5
const PICKAXE_DAMAGE := 50.0
const DEBRIS_COLORS := {"wood": Color(0.62, 0.42, 0.2), "brick": Color(0.72, 0.36, 0.26), "stone": Color(0.6, 0.58, 0.55), "metal": Color(0.55, 0.6, 0.68)}
const DIRV := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]       # north, east, south, west

## Level objects that break: mesh name -> [hit points, material it yields, yield per pickaxe hit]
const LEVEL := {
	"tree_pine": [250.0, "wood", 6], "tree_oak": [320.0, "wood", 7], "tree_palm": [200.0, "wood", 5],
	"rock_small_flat": [150.0, "brick", 5], "rock_small": [220.0, "brick", 6], "rock_medium_moss": [400.0, "brick", 7],
	"rock_wide_moss": [450.0, "brick", 7], "rock_tall": [550.0, "brick", 8],
	"farm_fence": [90.0, "wood", 4], "farm_barrel": [120.0, "wood", 5], "farm_crate": [120.0, "wood", 5],
	"warehouse_crates": [200.0, "wood", 6], "warehouse_door": [180.0, "metal", 5], "warehouse_roof": [700.0, "metal", 7],
	"house_door": [120.0, "wood", 5], "house_roof": [600.0, "wood", 8], "house_porch": [300.0, "wood", 6],
	"house_chimney": [400.0, "brick", 7], "house_furniture": [100.0, "wood", 5],
	"tower_frame": [700.0, "wood", 8], "tower_roof": [250.0, "wood", 6], "tower_ladder": [150.0, "wood", 4],
	"cactus": [160.0, "wood", 5],
	"house_shell": [900.0, "wood", 9], "warehouse_shell": [1400.0, "metal", 9],
}
## Breaking the first part also brings these sibling parts down.
const COLLAPSE := {"tower_frame": ["tower_roof", "tower_ladder"],
		"house_shell": ["house_roof", "house_porch", "house_chimney", "house_furniture", "house_door"],
		"warehouse_shell": ["warehouse_roof", "warehouse_door", "warehouse_crates"]}
## Parts that cannot break on their own but go with the building (trim, windows, stairs...).
const GO_WITH := {"house_shell": ["house_trim", "house_windows", "house_stairs", "house_door_frame"],
		"warehouse_shell": ["warehouse_frame", "warehouse_roller_door"]}

var game: Node
var by_body := {}                 # StaticBody3D instance id -> entry
var trees := {}                   # trunk body instance id -> {shape index -> entry}
var pieces := {}                  # piece key -> entry (player-built)
var by_cell := {}                 # Vector2i -> Array of entries
var features := {}                # feature string -> Array of entries
var building: Array = []          # pieces whose hit points are still climbing
var pending: Array = []           # [time, entry] chain-collapse queue
var debris: Array = []
var next_id := 1
var level_count := 0
var destroyed := 0
var built := 0
var preview: MeshInstance3D
var preview_ok_mat: StandardMaterial3D
var preview_bad_mat: StandardMaterial3D
var weak: MeshInstance3D          # the player's weak point
var weak_entry = null
var weak_time := -99.0
var mat_cache := {}
# piece editing (the player's)
var edit_entry = null
var edit_sel := {}
var edit_paint := true
var edit_overlay: Array = []
var edit_hover := -1
var shape_cache := {}


func setup(g: Node) -> void:
	game = g
	for body in g.island.find_children("*", "StaticBody3D", true, false):
		if body.name == "TrunkColliders":
			_register_trees(body)
			continue
		var mi := body.get_parent() as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var obj := mi.mesh.resource_path.get_file().get_basename()
		var spec = _level_spec(obj)
		if spec == null:
			continue
		var sc: float = mi.global_transform.basis.get_scale().x
		var e := _entry("level", obj, spec[0] * clampf(sc, 0.6, 1.6), spec[1], mi.global_position)
		e["yield"] = spec[2]
		e["node"] = mi
		e["body"] = body
		e["color"] = _debris_color(obj, spec[1])
		by_body[body.get_instance_id()] = e
		level_count += 1
	preview_ok_mat = Models.glow_material(Color(0.35, 0.7, 1.0), 0.6, 0.38)
	preview_bad_mat = Models.glow_material(Color(1.0, 0.3, 0.25), 0.6, 0.38)
	preview = MeshInstance3D.new()
	preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	preview.visible = false
	add_child(preview)
	weak = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.17
	disc.bottom_radius = 0.17
	disc.height = 0.03
	disc.radial_segments = 16
	weak.mesh = disc
	weak.material_override = Models.glow_material(Color(0.3, 0.75, 1.0), 3.0, 0.95)
	weak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	weak.visible = false
	add_child(weak)


static func _base_name(obj: String) -> String:
	## The snow and desert looks of a part (house_roof_snow) count as the part itself.
	for suffix in ["_snow", "_sand", "_dry"]:
		if obj.ends_with(suffix):
			return obj.trim_suffix(suffix)
	return obj


func _level_spec(obj: String) -> Variant:
	if LEVEL.has(obj):
		return LEVEL[obj]
	for suffix in ["_snow", "_sand", "_dry"]:                # the snow and desert looks break like the original
		if obj.ends_with(suffix) and LEVEL.has(obj.trim_suffix(suffix)):
			return LEVEL[obj.trim_suffix(suffix)]
	if obj.begins_with("kit_"):                       # the fort in the industrial yard
		var m := obj.get_slice("_", 2)
		if MAT_HP.has(m):
			return [MAT_HP[m], m, 5]
	return null


func _debris_color(obj: String, mat: String) -> Color:
	if obj.begins_with("rock_"):
		return DEBRIS_COLORS.stone
	if obj.begins_with("tree_") or obj == "cactus":
		return Color(0.35, 0.6, 0.25)
	return DEBRIS_COLORS.get(mat, DEBRIS_COLORS.wood)


func _entry(kind: String, obj: String, hp: float, mat: String, pos: Vector3) -> Dictionary:
	next_id += 1
	return {"id": next_id, "kind": kind, "name": obj, "hp": hp, "max": hp, "mat": mat, "pos": pos, "dead": false, "yield": 5, "color": DEBRIS_COLORS.get(mat, DEBRIS_COLORS.wood)}


func _register_trees(body: StaticBody3D) -> void:
	## Trees are GPU-instanced: trunk collider i belongs to instance i of the forest's MultiMesh.
	var group := body.get_parent()
	var mm: MultiMeshInstance3D = null
	for c in group.get_children():
		if c is MultiMeshInstance3D and c.get("transforms") != null:
			mm = c
	if mm == null:
		return
	var obj: String = (mm.get("mesh") as Mesh).resource_path.get_file().get_basename()
	var spec0 = _level_spec(obj)
	if spec0 == null:
		return
	var shapes := body.get_children()
	var count: int = (mm.get("transforms") as PackedFloat32Array).size() / 12
	if shapes.size() != count:
		push_warning("trunk colliders and tree instances differ in %s" % group.name)
		return
	var spec: Array = spec0
	var table := {}
	for i in count:
		var cs: CollisionShape3D = shapes[i]
		var e := _entry("tree", obj, spec[0], spec[1], cs.global_position)
		e["yield"] = spec[2]
		e["mm"] = mm
		e["index"] = i
		e["shape"] = cs
		e["body"] = body
		e["color"] = _debris_color(obj, spec[1])
		table[i] = e
		level_count += 1
	trees[body.get_instance_id()] = table


func lookup(collider: Object, shape := 0) -> Variant:
	if collider == null or (collider is Node and (collider as Node).has_meta("indestructible")):
		return null                                       # keycard vaults: no pickaxe, bullet or blast marks them
	var id := collider.get_instance_id()
	if trees.has(id):
		return trees[id].get(shape)
	var e = by_body.get(id)
	if e != null and e.dead:
		return null
	return e


var _harvest_cache: Array = []


func harvestables() -> Array:
	## Trees, rocks and farm clutter: what a bot short of materials goes and swings at.
	if _harvest_cache.is_empty():
		for table in trees.values():
			_harvest_cache.append_array((table as Dictionary).values())
		for e in by_body.values():
			var nm: String = e.name
			if e.kind == "level" and (nm.begins_with("rock_") or nm.begins_with("farm_")):
				_harvest_cache.append(e)
	return _harvest_cache


# ----------------------------------------------------------------------------- damage

func damage_at(collider: Object, shape: int, amount: float, attacker: Actor, at: Vector3) -> Variant:
	var e = lookup(collider, shape)
	if e != null:
		damage(e, amount, attacker, at)
	return e


func damage(e: Dictionary, amount: float, attacker: Actor, at: Vector3) -> void:
	if e.dead or amount <= 0.0 or game.warming_up():          # the island stays whole through the warm-up
		return
	e.hp -= amount
	if attacker != null and attacker == game.player and game.hud:
		game.hud.add_structure_number(at, amount)
	_wobble(e)
	if e.hp <= 0.0:
		destroy(e)


func explode(pos: Vector3, radius: float, amount: float, attacker: Actor) -> void:
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = radius
	q.shape = sph
	q.transform = Transform3D(Basis.IDENTITY, pos)
	q.collision_mask = 1
	var hit := {}
	for r in get_world_3d().direct_space_state.intersect_shape(q, 96):
		var e = lookup(r.collider, r.shape)
		if e == null or hit.has(e.id):
			continue
		hit[e.id] = true
		var d: float = (e.pos as Vector3).distance_to(pos)
		damage(e, amount * clampf(1.15 - d / (radius + 2.0), 0.35, 1.0), attacker, pos)


func _wobble(e: Dictionary) -> void:
	var n: Node3D = e.get("node")
	if n == null or game.autotest:
		return
	if not e.has("base_scale"):
		e["base_scale"] = n.scale
	var base: Vector3 = e.base_scale
	var tw := create_tween()
	tw.tween_property(n, "scale", base * 1.04, 0.05)
	tw.tween_property(n, "scale", base, 0.08)


func destroy(e: Dictionary) -> void:
	if e.dead:
		return
	e.dead = true
	destroyed += 1
	if weak_entry == e:
		weak_entry = null
		weak.visible = false
	burst(e.pos + Vector3(0, 1.0, 0), e.color, 10 if e.kind != "level" else 7)
	game.sfx(game.audio.material_sound("break_", e.mat), e.pos)
	match e.kind:
		"tree":
			var mm: MultiMeshInstance3D = e.mm
			if mm.multimesh:
				mm.multimesh.set_instance_transform(e.index, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.0001), Vector3(0, -50, 0)))
			(e.shape as CollisionShape3D).set_deferred("disabled", true)
		"level":
			var n: Node3D = e.node
			n.visible = false
			for cs in (e.body as Node).get_children():
				if cs is CollisionShape3D:
					cs.set_deferred("disabled", true)
			game.forget_door(n)
			var base := _base_name(e.name)
			if COLLAPSE.has(base):
				for sib in n.get_parent().get_children():
					if not (sib is MeshInstance3D and sib.mesh):
						continue
					var sn := _base_name(sib.mesh.resource_path.get_file().get_basename())
					if sn in COLLAPSE[base]:
						for b in sib.get_children():
							if b is StaticBody3D and by_body.has(b.get_instance_id()):
								pending.append([game.match_time + 0.15, by_body[b.get_instance_id()]])
					elif sn in GO_WITH.get(base, []):
						sib.visible = false
						for b in sib.get_children():
							if b is StaticBody3D:
								for cs in b.get_children():
									if cs is CollisionShape3D:
										cs.set_deferred("disabled", true)
			game.settle_pickups(e.pos, 10.0 if COLLAPSE.has(base) else 4.0)
		"build":
			_remove_piece(e)
			game.settle_pickups(e.pos, 4.5)


# ----------------------------------------------------------------------------- harvesting

func pickaxe_hit(a: Actor, hit: Dictionary) -> void:
	var e = lookup(hit.collider, hit.get("shape", 0))
	if e == null:
		return
	var crit: bool = a.is_player and weak_entry == e and weak.visible and weak.global_position.distance_to(hit.position) < 0.55
	game.sfx(game.audio.material_sound("hit_", e.mat), hit.position)
	if crit:
		game.sfx("weak_point", Vector3.INF)
	if e.kind != "build":
		var got: int = mini(int(e.yield) * (2 if crit else 1), MAX_MATS - int(a.mats[e.mat]))
		if got > 0:
			a.mats[e.mat] += got
			game.stats["harvested"] = game.stats.get("harvested", 0) + got
			if a.is_player and game.hud:
				game.hud.add_mat_note(e.mat, got, crit)
	damage(e, PICKAXE_DAMAGE * (2.0 if crit else 1.0), a, hit.position)
	if a.is_player:
		if e.dead:
			weak.visible = false
			weak_entry = null
		else:
			_place_weak_point(e, hit)


func _place_weak_point(e: Dictionary, hit: Dictionary) -> void:
	## A new weak point a short way from the last hit, on the same object's surface.
	var n: Vector3 = hit.normal
	var t1 := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var t2 := n.cross(t1).normalized()
	var space := get_world_3d().direct_space_state
	for attempt in 8:
		var ang: float = game.rng.randf() * TAU
		var r: float = game.rng.randf_range(0.35, 0.85)
		var q: Vector3 = hit.position + (t1 * cos(ang) + t2 * sin(ang) * 0.7) * r
		var rq := PhysicsRayQueryParameters3D.create(q + n * 0.8, q - n * 0.8, 1)
		var res := space.intersect_ray(rq)
		if res.is_empty() or lookup(res.collider, res.get("shape", 0)) != e:
			continue
		_show_weak(res.position, res.normal, e)
		return
	_show_weak(hit.position, n, e)


func _show_weak(p: Vector3, n: Vector3, e: Dictionary) -> void:
	var y := n.normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	weak.global_transform = Transform3D(Basis(x, y, z), p + y * 0.03)
	weak.visible = true
	weak_entry = e
	weak_time = game.match_time


# ----------------------------------------------------------------------------- building

func _cardinal(yaw: float) -> int:
	var f := Vector2(-sin(yaw), -cos(yaw))
	if absf(f.x) > absf(f.y):
		return 1 if f.x > 0.0 else 3
	return 0 if f.y < 0.0 else 2


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / GRID)), int(floor(p.z / GRID)))


func _datum_near(cells: Array, feet: float) -> Variant:
	var best = null
	var bd := 1e9
	for c in cells:
		for e in by_cell.get(c, []):
			var d := absf(e.datum + e.level * GRID - feet)
			if d < bd:
				bd = d
				best = e.datum
	return best if bd < 9.0 else null


func target(a: Actor, piece: String) -> Dictionary:
	var p := a.global_position
	var c := _cell(p)
	var dir := _cardinal(a.aim_yaw)
	var ahead: Vector2i = c + DIRV[dir]
	var cells := []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			cells.append(c + Vector2i(dx, dz))
	cells.append(ahead + DIRV[dir])
	var dv = _datum_near(cells, p.y)
	var datum: float = dv if dv != null else p.y - 0.25
	var rel := p.y - datum
	var lvl := int(floor((rel + 1.0) / GRID))
	var pitch := a.aim_pitch
	var cell := ahead
	var t := {"piece": piece, "dir": dir, "datum": datum}
	match piece:
		"wall":
			cell = c
			lvl += 1 if pitch > 0.55 else 0
		"floor", "cone":
			if pitch < -0.55:
				cell = c
			elif pitch > (0.3 if piece == "cone" else 0.55):
				cell = c
				lvl += 1
		"stairs":
			lvl = int(floor((rel + 2.5) / GRID))
			if pitch < -0.75:
				cell = c
	t["cell"] = cell
	t["level"] = lvl
	var y := datum + lvl * GRID
	var key := ""
	var xf := Transform3D.IDENTITY
	var feats: Array = []
	var dk := "%.1f" % datum
	match piece:
		"wall":
			var e := _edge(cell, dir)
			key = "W|%s|%d|%d|%d|%s" % [e[0], e[1], e[2], lvl, dk]
			if e[0] == "H":
				xf = Transform3D(Basis.IDENTITY, Vector3(e[1] * GRID + GRID / 2, y, e[2] * GRID))
				feats = [_ef(e, lvl, dk), _ef(e, lvl + 1, dk), "P|%d|%d|%d|%s" % [e[1], e[2], lvl, dk], "P|%d|%d|%d|%s" % [e[1] + 1, e[2], lvl, dk]]
			else:
				xf = Transform3D(Basis(Vector3.UP, PI / 2), Vector3(e[1] * GRID, y, e[2] * GRID + GRID / 2))
				feats = [_ef(e, lvl, dk), _ef(e, lvl + 1, dk), "P|%d|%d|%d|%s" % [e[1], e[2], lvl, dk], "P|%d|%d|%d|%s" % [e[1], e[2] + 1, lvl, dk]]
		"floor", "cone":
			key = "%s|%d|%d|%d|%s" % ["F" if piece == "floor" else "C", cell.x, cell.y, lvl, dk]
			xf = Transform3D(Basis.IDENTITY, Vector3(cell.x * GRID + GRID / 2, y, cell.y * GRID + GRID / 2))
			for d in 4:
				feats.append(_ef(_edge(cell, d), lvl, dk))
		"stairs":
			key = "S|%d|%d|%d|%s" % [cell.x, cell.y, lvl, dk]
			xf = Transform3D(Basis(Vector3.UP, -dir * PI / 2), Vector3(cell.x * GRID + GRID / 2, y, cell.y * GRID + GRID / 2))
			for d in 4:
				feats.append(_ef(_edge(cell, d), lvl, dk))
				feats.append(_ef(_edge(cell, d), lvl + 1, dk))
	t["key"] = key
	t["xf"] = xf
	t["features"] = feats
	return t


func _edge(cell: Vector2i, dir: int) -> Array:
	## The cell edge on side `dir`, in a canonical form: [H|V, x, z].
	match dir:
		0: return ["H", cell.x, cell.y]
		1: return ["V", cell.x + 1, cell.y]
		2: return ["H", cell.x, cell.y + 1]
	return ["V", cell.x, cell.y]


func _ef(e: Array, h: int, dk: String) -> String:
	return "E|%s|%d|%d|%d|%s" % [e[0], e[1], e[2], h, dk]


func can_place(a: Actor, t: Dictionary, mat: String) -> bool:
	return not pieces.has(t.key) and int(a.mats[mat]) >= COST


func update_preview(a: Actor, show: bool) -> void:
	if not show or a.build_piece == "" or not a.alive() or a.state != Actor.State.GROUND:
		preview.visible = false
		return
	var t := target(a, a.build_piece)
	preview.mesh = _kit_mesh(a.build_piece, a.build_mat)
	preview.global_transform = t.xf
	preview.material_override = preview_ok_mat if can_place(a, t, a.build_mat) else preview_bad_mat
	preview.visible = true


func place(a: Actor) -> bool:
	if a.build_piece == "" or a.state != Actor.State.GROUND or game.warming_up():
		return false
	if int(a.mats[a.build_mat]) < COST:            # out of this material: build with one you have
		for m in MATS:
			if int(a.mats[m]) >= COST:
				a.build_mat = m
				break
	var t := target(a, a.build_piece)
	if not can_place(a, t, a.build_mat):
		return false
	a.mats[a.build_mat] -= COST
	_spawn_piece(t, a.build_mat, a)
	game.sfx("build", a.global_position)
	return true


func place_target(t: Dictionary, mat: String, owner_a: Actor) -> Dictionary:
	## Used by tests and bots: place a computed target without the material check.
	return _spawn_piece(t, mat, owner_a)


func _kit_mesh(piece: String, mat: String) -> Mesh:
	var k: String = PIECE_MESH[piece] % mat
	if not mat_cache.has(k):
		mat_cache[k] = load("res://meshes/%s.res" % k)
	return mat_cache[k]


func _shape(piece: String) -> Array:
	## [shape, local transform]
	if not shape_cache.has(piece):
		match piece:
			"wall":
				var b := BoxShape3D.new()
				b.size = Vector3(GRID, GRID, 0.25)
				shape_cache[piece] = [b, Transform3D(Basis.IDENTITY, Vector3(0, GRID / 2, 0))]
			"floor":
				var b2 := BoxShape3D.new()
				b2.size = Vector3(GRID, 0.25, GRID)
				shape_cache[piece] = [b2, Transform3D(Basis.IDENTITY, Vector3(0, 0.125, 0))]
			"stairs":
				var b3 := BoxShape3D.new()
				b3.size = Vector3(GRID, 0.25, GRID * sqrt(2.0))
				shape_cache[piece] = [b3, Transform3D(Basis(Vector3.RIGHT, PI / 4), Vector3(0, GRID / 2, 0))]
			"cone":
				var cv := ConvexPolygonShape3D.new()
				cv.points = PackedVector3Array([Vector3(-2, 0, -2), Vector3(2, 0, -2), Vector3(2, 0, 2), Vector3(-2, 0, 2), Vector3(0, 2, 0)])
				shape_cache[piece] = [cv, Transform3D.IDENTITY]
	return shape_cache[piece]


func _spawn_piece(t: Dictionary, mat: String, owner_a: Actor) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	root.global_transform = t.xf
	var mi := MeshInstance3D.new()
	mi.mesh = _kit_mesh(t.piece, mat)
	root.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	var cs := CollisionShape3D.new()
	var sh: Array = _shape(t.piece)
	cs.shape = sh[0]
	cs.transform = sh[1]
	body.add_child(cs)
	var centre: Vector3 = t.xf * (sh[1] as Transform3D).origin
	var e := _entry("build", "%s %s" % [mat, t.piece], MAT_HP[mat], mat, centre)
	e.hp = MAT_HP[mat] * 0.1
	e["node"] = mi
	e["root"] = root
	e["body"] = body
	e["piece"] = t.piece
	e["key"] = t.key
	e["cell"] = t.cell
	e["level"] = t.level
	e["datum"] = t.datum
	e["features"] = t.features
	e["dir"] = t.dir
	e["edit"] = []
	e["owner"] = owner_a
	e["born"] = game.match_time
	e["grounded"] = _grounded(t, root)
	by_body[body.get_instance_id()] = e
	pieces[t.key] = e
	if not by_cell.has(t.cell):
		by_cell[t.cell] = []
	by_cell[t.cell].append(e)
	for f in t.features:
		if not features.has(f):
			features[f] = []
		features[f].append(e)
	building.append(e)
	built += 1
	if t.piece == "wall" and e.grounded and game.get("nav") != null:
		# bots path around walls standing on the ground
		var half: Vector3 = (t.xf as Transform3D).basis.x * GRID * 0.5
		e["nav_ends"] = [t.xf.origin - half, t.xf.origin + half]
		game.nav.mark_wall(e.nav_ends[0], e.nav_ends[1], true)
	if not game.autotest:
		mi.scale = Vector3(1, 0.2, 1)
		var tw := create_tween()
		tw.tween_property(mi, "scale", Vector3.ONE, 0.16)
	return e


func _grounded(t: Dictionary, root: Node3D) -> bool:
	## Does the piece rest on the terrain or on a level object (not on another built piece)?
	var xf: Transform3D = t.xf
	var pts: Array = []
	match t.piece:
		"wall": pts = [Vector3(-1.9, 0, 0), Vector3(0, 0, 0), Vector3(1.9, 0, 0)]
		"stairs": pts = [Vector3(-1.9, 0, 1.9), Vector3(0, 0, 1.9), Vector3(1.9, 0, 1.9)]
		_: pts = [Vector3(-1.9, 0, -1.9), Vector3(1.9, 0, -1.9), Vector3(1.9, 0, 1.9), Vector3(-1.9, 0, 1.9), Vector3.ZERO]
	var space := get_world_3d().direct_space_state
	for lp in pts:
		var q: Vector3 = xf * lp
		if q.y <= game.terrain.height(q.x, q.z) + 0.45:
			return true
		var res := space.intersect_ray(PhysicsRayQueryParameters3D.create(q + Vector3(0, 0.1, 0), q - Vector3(0, 0.5, 0), 1))
		if not res.is_empty():
			var other = lookup(res.collider, res.get("shape", 0))
			if other == null or other.kind != "build":
				return true
	return false


func _remove_piece(e: Dictionary) -> void:
	if e.has("nav_ends"):
		game.nav.mark_wall(e.nav_ends[0], e.nav_ends[1], false)
		e.erase("nav_ends")
	pieces.erase(e.key)
	by_body.erase((e.body as Node).get_instance_id())
	(by_cell.get(e.cell, []) as Array).erase(e)
	building.erase(e)
	var neighbours := []
	for f in e.features:
		var list: Array = features.get(f, [])
		list.erase(e)
		for o in list:
			if not o.dead and not neighbours.has(o):
				neighbours.append(o)
	(e.root as Node).queue_free()
	_check_support(neighbours)


func _check_support(start: Array) -> void:
	## Every group of pieces that lost its last path to the ground collapses, nearest pieces first.
	var done := {}
	for s in start:
		if s.dead or done.has(s.id):
			continue
		var comp := []
		var order := {}
		var queue := [s]
		order[s.id] = 0
		var grounded := false
		while not queue.is_empty():
			var e: Dictionary = queue.pop_front()
			comp.append(e)
			if e.grounded:
				grounded = true
			for f in e.features:
				for o in features.get(f, []):
					if not o.dead and not order.has(o.id):
						order[o.id] = order[e.id] + 1
						queue.append(o)
		for e in comp:
			done[e.id] = true
		if not grounded:
			for e in comp:
				pending.append([game.match_time + minf(0.08 * order[e.id], 1.5), e])


# ----------------------------------------------------------------------------- frame

func _physics_process(delta: float) -> void:
	for e in building.duplicate():
		if e.dead:
			building.erase(e)
			continue
		var bt: float = BUILD_TIME[e.mat]
		e.hp = minf(e.hp + e.max * 0.9 * delta / bt, e.max)
		if game.match_time - e.born >= bt:
			building.erase(e)
	if not pending.is_empty():
		for p in pending.duplicate():
			if game.match_time >= p[0]:
				pending.erase(p)
				destroy(p[1])
	if weak.visible:
		if game.match_time - weak_time > 4.0:
			weak.visible = false
			weak_entry = null
		else:
			var s := 1.0 + 0.15 * sin(game.match_time * 9.0)
			weak.scale = Vector3(s, 1, s)
	for d in debris.duplicate():
		d.life -= delta
		d.vel.y -= 18.0 * delta
		var n: Node3D = d.node
		n.position += d.vel * delta
		n.rotate_x(delta * 6.0)
		if d.life < 0.3:
			n.scale = Vector3.ONE * maxf(d.life / 0.3, 0.01)
		if d.life <= 0.0:
			debris.erase(d)
			n.queue_free()


func burst(at: Vector3, col: Color, n: int, up_min := 3.0, up_max := 8.0, size := 1.0) -> void:
	## Small pieces thrown into the air: debris from broken things, droplets from a splash.
	if game.autotest:
		return
	var key := "debris_%s_%.2f" % [col.to_html(), size]
	if not mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		var bm := BoxMesh.new()
		bm.size = Vector3(0.28, 0.2, 0.36) * size
		bm.material = m
		mat_cache[key] = bm
	for i in n:
		var mi := MeshInstance3D.new()
		mi.mesh = mat_cache[key]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		game.fx_root.add_child(mi)
		mi.global_position = at + Vector3(game.rng.randf_range(-0.8, 0.8), game.rng.randf_range(-0.6, 0.8), game.rng.randf_range(-0.8, 0.8))
		var v := Vector3(game.rng.randf_range(-4, 4), game.rng.randf_range(up_min, up_max), game.rng.randf_range(-4, 4))
		debris.append({"node": mi, "vel": v, "life": game.rng.randf_range(0.8, 1.4)})


# ----------------------------------------------------------------------------- editing

func tile_count(e: Dictionary) -> int:
	return 9 if e.piece == "wall" else 4


func begin_edit(a: Actor, e) -> bool:
	## Open the edit grid on one of your own pieces.
	if e == null or e.dead or e.kind != "build" or e.get("owner") != a:
		return false
	if (e.pos as Vector3).distance_to(a.global_position) > 8.0:
		return false
	cancel_edit()
	edit_entry = e
	edit_sel = {}
	for t in e.edit:
		edit_sel[t] = true
	_build_overlay(e, a)
	return true


func cancel_edit() -> void:
	for n in edit_overlay:
		if is_instance_valid(n):
			n.queue_free()
	edit_overlay = []
	edit_entry = null
	edit_hover = -1


func confirm_edit() -> void:
	if edit_entry != null and not edit_entry.dead:
		apply_edit(edit_entry, edit_sel.keys())
	cancel_edit()


func reset_edit() -> void:
	## Put the piece back the way it was built.
	var e = edit_entry
	cancel_edit()
	if e != null and not e.dead:
		e.edit = []
		_rebuild(e)


func update_edit(a: Actor, from: Vector3, dir: Vector3, held: bool, just: bool) -> void:
	var e = edit_entry
	if e == null:
		return
	if e.dead or (e.pos as Vector3).distance_to(a.global_position) > 9.0 or not a.alive():
		cancel_edit()
		return
	edit_hover = edit_tile_at(e, from, dir)
	if just and edit_hover >= 0:
		edit_paint = not edit_sel.has(edit_hover)       # first tile decides: select or deselect
	if held and edit_hover >= 0:
		if edit_paint:
			edit_sel[edit_hover] = true
		else:
			edit_sel.erase(edit_hover)
	for i in edit_overlay.size():
		var mi: MeshInstance3D = edit_overlay[i]
		var on := edit_sel.has(i)
		var c := Color(0.25, 0.6, 1.0, 0.55) if on else Color(1, 1, 1, 0.2)
		if i == edit_hover:
			c = Color(0.55, 0.85, 1.0, 0.75) if on else Color(1, 1, 1, 0.45)
		(mi.material_override as StandardMaterial3D).albedo_color = c


func edit_tile_at(e: Dictionary, from: Vector3, dir: Vector3) -> int:
	## Which tile of the piece's edit grid the ray points at, or -1.
	var inv := (e.root as Node3D).global_transform.affine_inverse()
	var o := inv * from
	var d := (inv.basis * dir).normalized()
	var p := Vector3.ZERO
	match e.piece:
		"wall":
			if absf(d.z) < 1e-4:
				return -1
			var t := -o.z / d.z
			if t < 0.0:
				return -1
			p = o + d * t
			var col := int(floor((p.x + 2.0) / (4.0 / 3.0)))
			var row := int(floor(p.y / (4.0 / 3.0)))
			if col < 0 or col > 2 or row < 0 or row > 2:
				return -1
			return row * 3 + col
		"stairs":
			var den := d.y + d.z
			if absf(den) < 1e-4:
				return -1
			var t2 := (2.0 - o.y - o.z) / den
			if t2 < 0.0:
				return -1
			p = o + d * t2
		_:
			var plane_y := 0.125 if e.piece == "floor" else 1.0
			if absf(d.y) < 1e-4:
				return -1
			var t3 := (plane_y - o.y) / d.y
			if t3 < 0.0:
				return -1
			p = o + d * t3
	if absf(p.x) > 2.0 or absf(p.z) > 2.0:
		return -1
	return (0 if p.z < 0.0 else 2) + (0 if p.x < 0.0 else 1)


func _build_overlay(e: Dictionary, a: Actor) -> void:
	var root: Node3D = e.root
	var side := 1.0
	if e.piece == "wall":
		var cam_local := root.global_transform.affine_inverse() * a.eye()
		side = 1.0 if cam_local.z >= 0.0 else -1.0
	for i in tile_count(e):
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.no_depth_test = true
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		match e.piece:
			"wall":
				q.size = Vector2(1.22, 1.22)
				mi.position = Vector3(-2.0 + (i % 3 + 0.5) * 4.0 / 3.0, (i / 3 + 0.5) * 4.0 / 3.0, 0.16 * side)
			"stairs":
				q.size = Vector2(1.85, 1.85 * sqrt(2.0))
				var z := -1.0 if i < 2 else 1.0
				mi.position = Vector3(-1.0 if i % 2 == 0 else 1.0, 2.0 - z + 0.2, z)
				mi.rotation.x = -PI / 4
			_:
				q.size = Vector2(1.85, 1.85)
				mi.position = Vector3(-1.0 if i % 2 == 0 else 1.0, 0.32 if e.piece == "floor" else 1.15, -1.0 if i < 2 else 1.0)
				mi.rotation.x = -PI / 2
		mi.mesh = q
		root.add_child(mi)
		edit_overlay.append(mi)


func apply_edit(e: Dictionary, tiles: Array) -> bool:
	## Cut the selected tiles out (walls, floors, cones) or turn a ramp towards the selected side.
	var sel := tiles.duplicate()
	sel.sort()
	match e.piece:
		"stairs":
			var sides := {"0,1": 0, "1,3": 1, "2,3": 2, "0,2": 3}
			var k := ",".join(sel.map(func(x): return str(x)))
			if not sides.has(k):
				return false
			e.dir = (int(e.dir) + int(sides[k])) % 4
			e.edit = []
		_:
			if sel.size() >= tile_count(e):
				return false                            # at least one tile has to stay
			e.edit = sel
	_rebuild(e)
	return true


func _rebuild(e: Dictionary) -> void:
	var root: Node3D = e.root
	var body: StaticBody3D = e.body
	for c in body.get_children():
		body.remove_child(c)
		c.free()
	for c in root.get_children():
		if c is MeshInstance3D and not edit_overlay.has(c):
			root.remove_child(c)
			c.free()
	var mat: String = e.mat
	if e.piece == "stairs":
		root.global_transform = Transform3D(Basis(Vector3.UP, -int(e.dir) * PI / 2), root.global_position)
	if (e.edit as Array).is_empty():
		var mi := MeshInstance3D.new()
		mi.mesh = _kit_mesh(e.piece, mat)
		root.add_child(mi)
		var sh: Array = _shape(e.piece)
		var cs := CollisionShape3D.new()
		cs.shape = sh[0]
		cs.transform = sh[1]
		body.add_child(cs)
		e.node = mi
		return
	e.node = root
	match e.piece:
		"wall":
			var tb := BoxShape3D.new()
			tb.size = Vector3(4.0 / 3.0, 4.0 / 3.0, 0.25)
			for i in 9:
				if e.edit.has(i):
					continue
				var cx := -2.0 + (i % 3 + 0.5) * 4.0 / 3.0
				var by := (i / 3) * 4.0 / 3.0
				var mi2 := MeshInstance3D.new()
				mi2.mesh = _kit_mesh("wall", mat)
				mi2.transform = Transform3D(Basis.IDENTITY.scaled(Vector3(1.0 / 3.0, 1.0 / 3.0, 1.0)), Vector3(cx, by, 0))
				root.add_child(mi2)
				var cs2 := CollisionShape3D.new()
				cs2.shape = tb
				cs2.position = Vector3(cx, by + 2.0 / 3.0, 0)
				body.add_child(cs2)
		"floor":
			var fb := BoxShape3D.new()
			fb.size = Vector3(2.0, 0.25, 2.0)
			for i in 4:
				if e.edit.has(i):
					continue
				var c3 := Vector3(-1.0 if i % 2 == 0 else 1.0, 0, -1.0 if i < 2 else 1.0)
				var mi3 := MeshInstance3D.new()
				mi3.mesh = _kit_mesh("floor", mat)
				mi3.transform = Transform3D(Basis.IDENTITY.scaled(Vector3(0.5, 1.0, 0.5)), c3)
				root.add_child(mi3)
				var cs3 := CollisionShape3D.new()
				cs3.shape = fb
				cs3.position = c3 + Vector3(0, 0.125, 0)
				body.add_child(cs3)
		"cone":
			_rebuild_cone(e, root, body)


func _rebuild_cone(e: Dictionary, root: Node3D, body: StaticBody3D) -> void:
	## A pyramid made of four corner quarters; the cut quarters leave an opening.
	var A := [Vector3(-2, 0, -2), Vector3(2, 0, -2), Vector3(-2, 0, 2), Vector3(2, 0, 2)]
	var P := Vector3(0, 2, 0)
	var mids := {"0,1": Vector3(0, 0, -2), "1,3": Vector3(2, 0, 0), "2,3": Vector3(0, 0, 2), "0,2": Vector3(-2, 0, 0)}
	var tri := {0: [], 1: [], 2: [], 3: []}
	for k in mids:
		var ab: PackedStringArray = k.split(",")
		var i0 := int(ab[0]); var i1 := int(ab[1])
		tri[i0].append([A[i0], mids[k], P])
		tri[i1].append([mids[k], A[i1], P])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col: Color = Items.MAT_COLORS[e.mat]
	for i in 4:
		if e.edit.has(i):
			continue
		var pts := PackedVector3Array([A[i], P, Vector3.ZERO])
		for t in tri[i]:
			var n: Vector3 = ((t[1] - t[0]) as Vector3).cross(t[2] - t[0]).normalized()
			if n.y < 0.0:
				n = -n
			for v in t:
				st.set_normal(n)
				st.set_color(col)
				st.add_vertex(v)
			pts.append(t[0]); pts.append(t[1])
		var cv := ConvexPolygonShape3D.new()
		cv.points = pts
		var cs := CollisionShape3D.new()
		cs.shape = cv
		body.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.8
	mi.material_override = m
	root.add_child(mi)


func looked_at(from: Vector3, dir: Vector3, reach: float, exclude: Actor) -> Variant:
	var res: Dictionary = game.ray(from, from + dir * reach, exclude, 1)
	if res.is_empty():
		return null
	return lookup(res.collider, res.get("shape", 0))
