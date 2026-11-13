## Three bosses, each guarding a lair, and the three keycard vaults they open.
## A boss is an Actor with a bot brain in boss mode (bot.gd): it is not a player, so it is not in game.actors,
## has no placement, is not counted as alive and the storm does not touch it. On death it drops its mythic items,
## about 150 gold and its keycard; the keycard opens the vault built beside the lair (once), whose three golden chests
## hold top loot. Vault walls are indestructible (see Structures.lookup) and stand on the bots' grid via mark_wall.
class_name Bosses
extends Node3D

## id -> name, lair (a Terrain property and the name of the place), look, health, gear.
## mythics: item ids another feature adds; any that do not exist are replaced by one legendary assault rifle.
const ORDER := ["weaver", "ravage", "tinker"]
const SPEC := {
	"weaver": {"name": "Weaver", "lair": "snow_town", "poi": "Frostpeak", "angle": 0.3, "body": "Xbot", "outfit": Color(0.04, 0.05, 0.07),
		"accent": Color(0.1, 0.85, 0.78), "scale": 1.0, "hp": 300.0, "shield": 150.0, "mythics": ["web_shooters"], "guns": [["smg", 3]],
		"card": "keycard_weaver", "plate": Color(0.35, 1.0, 0.9)},
	"ravage": {"name": "Ravage", "lair": "depot", "poi": "Sandbar Depot", "angle": 2.4, "body": "Soldier", "outfit": Color(0.5, 0.03, 0.04),
		"accent": Color(0.05, 0.02, 0.02), "scale": 1.3, "hp": 300.0, "shield": 150.0, "mythics": ["ravage_grasp"], "guns": [["shotgun", 3]],
		"card": "keycard_ravage", "plate": Color(1.0, 0.35, 0.3)},
	"tinker": {"name": "Tinker", "lair": "yard", "poi": "Gearworks Yard", "angle": 4.4, "body": "Xbot", "outfit": Color(0.78, 0.36, 0.1),
		"accent": Color(0.55, 0.6, 0.66), "scale": 1.15, "hp": 300.0, "shield": 150.0, "mythics": ["charge_shotgun", "shockwave_launcher"], "guns": [],
		"card": "keycard_tinker", "plate": Color(1.0, 0.7, 0.3)},
}
const LEASH := 45.0                      # how far from the lair a boss strays
const AGGRO := 28.0                       # how close you can get before a boss notices you
const BAR_RANGE := 60.0
const VAULT_W := 8.0                     # the vault: 8 wide (x) by 6 deep (z) by 4 high, door on the +z side
const VAULT_D := 6.0
const VAULT_H := 4.0
const DOOR_W := 2.4

var game: Node
var list: Array = []                     # {id, actor, plate, home, vault, alive, dmg_t, max_total, name, poi}
var vaults := {}                         # id -> vault dictionary
var hud_boss: Variant = null             # the boss whose health bar the HUD shows now
var tick_n := 0
var _mats := {}


func setup(g: Node) -> void:
	game = g
	for id in ORDER:
		_build_lair(id)


# ----------------------------------------------------------------------------- lookup

func alive_actors() -> Array:
	var out: Array = []
	for b in list:
		if b.alive and b.actor.alive():
			out.append(b.actor)
	return out


func data_for(a: Actor) -> Variant:
	for b in list:
		if b.actor == a:
			return b
	return null


func poi_subtitle(poi_name: String) -> String:
	for b in list:
		if b.poi == poi_name and b.alive:
			return "Boss: %s" % b.name
	return ""


func note_damage(victim: Actor, attacker: Actor) -> void:
	if attacker == game.player:
		var b = data_for(victim)
		if b != null:
			b.dmg_t = game.match_time


func vault_near(a: Actor) -> Variant:
	## The closed vault whose door this actor stands at.
	for id in vaults:
		var v: Dictionary = vaults[id]
		if v.opened:
			continue
		var f: Vector3 = v.front
		if Vector2(a.global_position.x - f.x, a.global_position.z - f.z).length() < 3.2 and absf(a.global_position.y - f.y) < 2.5:
			return v
	return null


func keycard_slot(a: Actor, v: Dictionary) -> int:
	return a.find_item(String(v.card))


func open_vault(v: Dictionary, by: Actor) -> bool:
	## The matching keycard is used up and the door slides open; false without it.
	if v.opened:
		return false
	var i := keycard_slot(by, v)
	if i < 0:
		return false
	by.slots[i] = null
	if i == by.active:
		by._refresh_held()
	v.opened = true
	game.sfx("reload_heavy", v.front)
	game.sfx("hit_metal", v.front)
	var door: Node3D = v.door
	var tw := door.create_tween()
	tw.tween_property(door, "position:x", 3.0, 1.1).set_trans(Tween.TRANS_SINE)
	(v.door_shape as CollisionShape3D).set_deferred("disabled", true)
	(v.reader_mat as StandardMaterial3D).albedo_color = Color(0.2, 1.0, 0.35)
	(v.reader_mat as StandardMaterial3D).emission = Color(0.2, 1.0, 0.35)
	game.nav.mark_wall(v.nav_door[0], v.nav_door[1], false)
	for c in v.chests:
		c["locked"] = false
		game._add_glow(c.node, Items.RARITY_COLORS[4], 1.0)
	game.stats["vaults_opened"] = game.stats.get("vaults_opened", 0) + 1
	if by == game.player:
		game.announce("Vault open")
	return true


func vault_drops(rng: RandomNumberGenerator) -> Array:
	## One golden vault chest: one or two epic or legendary guns with ammo, big healing, gold.
	var drops: Array = []
	for i in 1 + rng.randi() % 2:
		var w := Items.roll_weapon(rng)
		w["rarity"] = 4 if rng.randf() < 0.5 else 3
		drops.append(w)
		drops.append({"ammo": Items.def(w).ammo})
	drops.append(Items.make("mega_flask") if rng.randf() < 0.6 else Items.make("shield_potion", 0, 2))
	drops.append({"gold": 100})
	drops.append({"ammo": Items.AMMO_TYPES[rng.randi() % 4]})
	return drops


# ----------------------------------------------------------------------------- frame

func _physics_process(_delta: float) -> void:
	tick_n += 1
	if tick_n % 6 != 0:
		return
	var s: Actor = game.controller.subject() if game.controller != null else null
	hud_boss = null
	var best := 1e9
	for b in list:
		var a: Actor = b.actor
		var show: bool = b.alive and a.alive() and s != null
		if b.plate != null:
			b.plate.visible = show and s.global_position.distance_to(a.global_position) < 80.0
		if not show:
			continue
		var d := s.global_position.distance_to(a.global_position)
		if d < BAR_RANGE and d < best and (game.match_time - b.dmg_t < 8.0 or game.can_see(s.eye(), a.eye() + Vector3(0, 0.3, 0))):
			best = d
			hud_boss = b


# ----------------------------------------------------------------------------- the boss

func _build_lair(id: String) -> void:
	var spec: Dictionary = SPEC[id]
	var centre: Vector2 = game.terrain.get(spec.lair)
	var site := _find_site(centre, float(spec.angle))
	if site.is_empty():
		push_warning("no room for the %s vault" % id)
		return
	var v := _build_vault(id, site)
	vaults[id] = v
	_spawn_boss(id, v)


func _spawn_boss(id: String, v: Dictionary) -> void:
	var spec: Dictionary = SPEC[id]
	var a := Actor.new()
	game.add_child(a)
	a.setup(game, spec.name, false, spec.outfit, spec.accent, spec.body)
	a.is_boss = true
	a.state = Actor.State.GROUND
	var home: Vector3 = v.home
	a.global_position = home + Vector3(0, 0.3, 0)
	a.hp = float(spec.hp)
	a.shield = float(spec.shield)
	a.gold = 150
	a.set_meta("boss_max", float(spec.hp) + float(spec.shield))
	var sc: float = spec.scale
	a.body.scale = Vector3.ONE * sc
	var cap := a.shape_node.shape as CapsuleShape3D
	cap.radius = 0.3 * sc
	cap.height = Actor.STAND_H * sc
	a.shape_node.position.y = cap.height / 2.0
	for t in Items.AMMO_TYPES:
		a.ammo[t] = 400
	for t in Structures.MATS:
		a.mats[t] = 0                                 # bosses fight in the open: they never build
	var fallback := false
	for m in spec.mythics:
		if Items.DEFS.has(m):
			a.add_item(Items.make(m, 4))
		else:
			fallback = true
	for gd in spec.guns:
		if Items.DEFS.has(gd[0]):
			a.add_item(Items.make(gd[0], gd[1]))
	if fallback:
		a.add_item(Items.make("assault_rifle", 3))
	_dress(a, id)
	var plate := Label3D.new()
	plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	plate.font_size = 40
	plate.outline_size = 12
	plate.modulate = spec.plate
	plate.no_depth_test = true
	plate.position = Vector3(0, 2.05 * sc + 0.35, 0)
	plate.text = String(spec.name).to_upper()
	a.add_child(plate)
	var brain := preload("res://scripts/bot.gd").new()
	a.add_child(brain)
	brain.setup(game, a, 0.5)                      # a fair fight: average reactions, not a sniper
	a.spread_mul = 1.5
	brain.mode = "boss"
	brain.boss_home = home
	brain.boss_id = id
	brain.boss_face = v.yaw_out
	a.aim_yaw = v.yaw_out
	list.append({"id": id, "actor": a, "plate": plate, "home": home, "vault": v, "alive": true, "dmg_t": -99.0, "name": spec.name,
			"poi": spec.poi, "card": spec.card})


func boss_died(victim: Actor, killer: Actor) -> void:
	## Called from game.on_eliminated: the loot is already on the ground; add the keycard and tell everyone.
	var b = data_for(victim)
	if b == null:
		return
	b.alive = false
	if b.plate != null:
		b.plate.queue_free()
		b.plate = null
	var p: Vector3 = victim.global_position + Vector3(0, 0.3, 0)
	game.spawn_pickup(Items.make(b.card), p + Vector3(0.6, 0.0, 1.5))
	if killer != null and killer != victim:
		killer.kills += 1
	game.kill_feed.append({"text": "%s was defeated%s" % [b.name, (" by " + killer.display_name) if killer != null else ""], "time": game.match_time,
			"mine": killer == game.player})
	if game.kill_feed.size() > 6:
		game.kill_feed.pop_front()
	if game.autotest:
		print("BOSS_DOWN t=%.0f %s by %s" % [game.match_time, b.name, killer.display_name if killer != null else "-"])
	game.stats["bosses_slain"] = game.stats.get("bosses_slain", 0) + 1
	game.announce("%s is down: take the keycard" % b.name if killer == game.player else "%s has been defeated" % b.name)
	if killer == game.player:
		game.sfx("elimination", Vector3.INF)


# ----------------------------------------------------------------------------- looks

func _m(c: Color, emit := 0.0, metal := 0.0, rough := 0.7) -> StandardMaterial3D:
	var k := "%s_%s_%s_%s" % [c.to_html(), emit, metal, rough]
	if not _mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		if emit > 0.0:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = emit
		_mats[k] = m
	return _mats[k]


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _box(parent: Node3D, size: Vector3, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return _part(parent, bm, mat, pos, rot)


func _rod(parent: Node3D, from: Vector3, to: Vector3, r0: float, r1: float, mat: Material) -> void:
	var cm := CylinderMesh.new()
	cm.bottom_radius = r0
	cm.top_radius = r1
	cm.height = from.distance_to(to)
	cm.radial_segments = 6
	cm.rings = 1
	var mi := _part(parent, cm, mat, (from + to) / 2.0)
	mi.basis = Basis(Quaternion(Vector3.UP, (to - from).normalized()))


func _dress(a: Actor, id: String) -> void:
	## Procedural accessories on the body (it faces -Z; the back is +Z).
	var b: Node3D = a.body
	var steel := _m(Color(0.45, 0.48, 0.52), 0.0, 0.7, 0.4)
	var head := _head_node(a)                            # head parts ride on the head bone, in its local frame
	var fz := 1.0 if SPEC[id].body == "Xbot" else -1.0   # which way "forward" is in the rig (the Xbot is built facing +Z)
	match id:
		"weaver":
			var white := _m(Color(0.96, 0.97, 1.0), 0.0, 0.0, 0.4)
			var mask := SphereMesh.new()
			mask.radius = 0.112
			mask.height = 0.25
			var mi := _part(head, mask, white, Vector3(0, 0.09, fz * 0.025))
			mi.scale = Vector3(1.0, 1.08, 0.92)
			for sx in [-1.0, 1.0]:
				_box(head, Vector3(0.05, 0.026, 0.02), _m(Color(0.02, 0.02, 0.03)), Vector3(sx * 0.04, 0.105, fz * 0.126), Vector3(0, 0, sx * -0.35))
			_box(b, Vector3(0.1, 0.1, 0.02), _m(Color(0.1, 0.85, 0.78), 1.2), Vector3(0, 1.33, -0.115), Vector3(0, 0, PI / 4))
		"ravage":
			var dark := _m(Color(0.12, 0.02, 0.03), 0.0, 0.2, 0.5)
			var red := _m(Color(0.55, 0.04, 0.05), 0.3, 0.0, 0.5)
			# tendrils: tapering chains of rods that arc up and back from the shoulders and spine
			var bases := [Vector3(0.12, 1.45, 0.12), Vector3(-0.12, 1.45, 0.12), Vector3(0.07, 1.25, 0.14), Vector3(-0.07, 1.25, 0.14), Vector3(0, 1.1, 0.14)]
			var tips := [Vector3(0.62, 2.15, 0.62), Vector3(-0.62, 2.15, 0.62), Vector3(0.55, 1.45, 0.8), Vector3(-0.55, 1.45, 0.8), Vector3(0, 0.55, 0.85)]
			var bend := [Vector3(0.35, 2.0, 0.0), Vector3(-0.35, 2.0, 0.0), Vector3(0.45, 1.9, 0.1), Vector3(-0.45, 1.9, 0.1), Vector3(0, 1.3, 0.6)]
			for i in bases.size():
				var prev: Vector3 = bases[i]
				for k in range(1, 7):
					var t := k / 6.0
					var p: Vector3 = (bases[i] as Vector3).lerp(bend[i], t).lerp((bend[i] as Vector3).lerp(tips[i], t), t)
					_rod(b, prev, p, 0.05 * (1.0 - (k - 1) / 6.0) + 0.012, 0.05 * (1.0 - k / 6.0) + 0.012, dark if k % 2 == 0 else red)
					prev = p
			for sx in [-1.0, 1.0]:                          # glowing eyes, and horns
				_box(head, Vector3(0.05, 0.025, 0.02), _m(Color(1.0, 0.15, 0.1), 2.0), Vector3(sx * 0.042, 0.06, fz * 0.1))
				_rod(head, Vector3(sx * 0.07, 0.12, 0.0), Vector3(sx * 0.17, 0.35, fz * 0.05), 0.03, 0.006, dark)
		"tinker":
			var rust := _m(Color(0.7, 0.3, 0.08), 0.0, 0.5, 0.6)
			var dk := _m(Color(0.16, 0.17, 0.19), 0.0, 0.6, 0.5)
			_box(b, Vector3(0.46, 0.56, 0.22), rust, Vector3(0, 1.28, 0.2))
			_box(b, Vector3(0.38, 0.1, 0.24), dk, Vector3(0, 1.0, 0.2))
			for sx in [-1.0, 1.0]:
				var cm := CylinderMesh.new()
				cm.top_radius = 0.045
				cm.bottom_radius = 0.055
				cm.height = 0.5
				_part(b, cm, steel, Vector3(sx * 0.15, 1.7, 0.24))
				_box(b, Vector3(0.2, 0.09, 0.22), rust, Vector3(sx * 0.28, 1.47, 0.0))
				_box(b, Vector3(0.12, 0.12, 0.06), dk, Vector3(sx * 0.14, 1.28, -0.12))
			_box(head, Vector3(0.22, 0.19, 0.22), steel, Vector3(0, 0.09, 0.0))
			_box(head, Vector3(0.18, 0.04, 0.02), _m(Color(1.0, 0.55, 0.1), 2.5), Vector3(0, 0.1, fz * 0.115))
			_box(b, Vector3(0.28, 0.2, 0.05), rust, Vector3(0, 1.3, -0.12))
	if id == "ravage":
		_paint_soldier(a, Color(0.42, 0.03, 0.04), Color(0.1, 0.02, 0.02))


func _head_node(a: Actor) -> Node3D:
	## A node that follows the head bone (or the body, if the skeleton has no "Head" bone).
	var skel: Skeleton3D = a.body.skel
	if skel == null or skel.find_bone("Head") < 0:
		return a.body
	var ba := BoneAttachment3D.new()
	ba.bone_name = "Head"
	skel.add_child(ba)
	return ba


func _paint_soldier(a: Actor, main: Color, dark: Color) -> void:
	## The Soldier mesh only tints by half: give Ravage a proper dark red and black.
	var n := 0
	for mi in a.body.rig.find_children("*", "MeshInstance3D", true, false):
		for s in (mi as MeshInstance3D).mesh.get_surface_count():
			var base: Material = (mi as MeshInstance3D).get_active_material(s)
			var m: Material = base.duplicate() if base else StandardMaterial3D.new()
			if m is StandardMaterial3D:
				(m as StandardMaterial3D).albedo_color = main if n % 3 != 2 else dark
				(m as StandardMaterial3D).roughness = 0.55
			(mi as MeshInstance3D).set_surface_override_material(s, m)
			n += 1


# ----------------------------------------------------------------------------- the vault

func _find_site(centre: Vector2, angle: float) -> Dictionary:
	## A flat, empty, walkable patch for the 8 x 6 vault with room in front of its door, near the place's centre.
	for r in [22.0, 28.0, 16.0, 34.0, 10.0, 40.0, 46.0]:
		for k in 36:
			var ang: float = angle + (k / 2 + 1) * (TAU / 36.0) * (1.0 if k % 2 == 0 else -1.0)
			var c: Vector2 = centre + Vector2(cos(ang), sin(ang)) * float(r)
			var face: Vector2 = (centre - c).normalized()
			for yaw_off in [0.0, PI / 2, -PI / 2, PI]:
				var f: Vector2 = face.rotated(float(yaw_off))
				var yaw := atan2(f.x, f.y)
				var s := _site_ok(c, yaw)
				if not s.is_empty():
					return s
	return {}


func _site_ok(c: Vector2, yaw: float) -> Dictionary:
	var T = game.terrain
	var basis := Basis(Vector3.UP, yaw)
	var hmax := -1e9
	var hmin := 1e9
	for ix in range(-6, 7, 3):
		for iz in range(-5, 11, 3):                         # the vault and the 7 m of ground before its door
			var w := basis * Vector3(ix, 0, iz)
			var p := Vector2(c.x + w.x, c.y + w.z)
			if T.water_surface(p.x, p.y) > -999.0 or T.is_water(p.x, p.y):
				return {}
			var h: float = T.height(p.x, p.y)
			hmax = maxf(hmax, h)
			hmin = minf(hmin, h)
	if hmax - hmin > 0.35 or hmax < 1.0:
		return {}
	# nothing standing in the way: buildings, trees, props (a box that clears the flat ground by 0.6 m)
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.6, 4.0, 15.0)
	q.shape = box
	q.collision_mask = 1
	var mid := basis * Vector3(0, 0, 2.5)
	q.transform = Transform3D(basis, Vector3(c.x + mid.x, hmax + 0.6 + 2.0, c.y + mid.z))
	if not game.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty():
		return {}
	var front := basis * Vector3(0, 0, 11.0)
	var home: Vector3 = game.events._dry_spot(Vector2(c.x + front.x, c.y + front.z))
	for dz in [0.0, 4.3, 8.0]:
		var w2: Vector3 = basis * Vector3(0, 0, float(dz))
		if not game.nav.walkable(Vector3(c.x + w2.x, 0, c.y + w2.z)):
			return {}
	return {"c": c, "yaw": yaw, "h": hmax, "home": home}


func _build_vault(id: String, site: Dictionary) -> Dictionary:
	var spec: Dictionary = SPEC[id]
	var c: Vector2 = site.c
	var root := Node3D.new()
	root.name = "Vault_" + id
	add_child(root)
	root.position = Vector3(c.x, float(site.h), c.y)
	root.rotation.y = float(site.yaw)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("indestructible", true)
	body.set_meta("vault", id)
	root.add_child(body)
	var concrete := _m(Color(0.52, 0.53, 0.55), 0.0, 0.0, 0.9)
	var steel := _m(Color(0.2, 0.22, 0.25), 0.0, 0.6, 0.45)
	var floor_m := _m(Color(0.3, 0.31, 0.33), 0.0, 0.0, 0.8)
	var yellow := _m(Color(0.95, 0.74, 0.08), 0.0, 0.0, 0.6)
	var accent: Color = spec.plate
	var wt := 0.5
	var hw := VAULT_W / 2.0
	var hd := VAULT_D / 2.0
	var gap := DOOR_W / 2.0
	var wy := 0.1 + VAULT_H / 2.0
	# [size, centre, material]: walls, lintel, roof and the slab they stand on (all solid)
	var parts := [
		[Vector3(VAULT_W + 1.0, 1.7, VAULT_D + 1.2), Vector3(0, -0.75, 0), floor_m],
		[Vector3(VAULT_W, VAULT_H, wt), Vector3(0, wy, -hd + wt / 2.0), concrete],
		[Vector3(wt, VAULT_H, VAULT_D), Vector3(-hw + wt / 2.0, wy, 0), concrete],
		[Vector3(wt, VAULT_H, VAULT_D), Vector3(hw - wt / 2.0, wy, 0), concrete],
		[Vector3(hw - gap, VAULT_H, wt), Vector3(-(hw + gap) / 2.0, wy, hd - wt / 2.0), concrete],
		[Vector3(hw - gap, VAULT_H, wt), Vector3((hw + gap) / 2.0, wy, hd - wt / 2.0), concrete],
		[Vector3(DOOR_W, 0.8, wt), Vector3(0, 0.1 + VAULT_H - 0.4, hd - wt / 2.0), steel],
		[Vector3(VAULT_W + 0.8, 0.4, VAULT_D + 0.8), Vector3(0, 0.1 + VAULT_H + 0.2, 0), steel],
	]
	for p in parts:
		var sz: Vector3 = p[0]
		_box(root, sz, p[2], p[1])
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = sz
		cs.shape = bs
		cs.position = p[1]
		body.add_child(cs)
	# steel bands round the walls, hazard stripes beside the door, a vent and a beacon on the roof
	for y in [0.6, 3.6]:
		_box(root, Vector3(VAULT_W + 0.12, 0.16, VAULT_D + 0.12), steel, Vector3(0, y, 0))
	for sx in [-1.0, 1.0]:
		for k in 4:
			_box(root, Vector3(0.2, 0.5, 0.05), yellow, Vector3(sx * (gap + 0.2), 0.45 + k * 0.85, hd + 0.02))
	_box(root, Vector3(1.4, 0.5, 1.0), steel, Vector3(-2.0, 4.65, -1.0))
	var reader_mat := StandardMaterial3D.new()
	reader_mat.albedo_color = Color(1.0, 0.12, 0.1)
	reader_mat.emission_enabled = true
	reader_mat.emission = Color(1.0, 0.12, 0.1)
	reader_mat.emission_energy_multiplier = 2.5
	var beacon := SphereMesh.new()
	beacon.radius = 0.22
	beacon.height = 0.44
	_part(root, beacon, reader_mat, Vector3(2.4, 4.8, 1.8))
	# the reader beside the door: a dark box with a light and a card slot
	_box(root, Vector3(0.36, 0.62, 0.14), steel, Vector3(-gap - 0.75, 1.5, hd + 0.07))
	_box(root, Vector3(0.18, 0.12, 0.03), reader_mat, Vector3(-gap - 0.75, 1.68, hd + 0.16))
	_box(root, Vector3(0.2, 0.025, 0.03), _m(Color(0.02, 0.02, 0.02)), Vector3(-gap - 0.75, 1.42, hd + 0.16))
	_box(root, Vector3(0.12, 0.05, 0.03), _m(accent, 1.0), Vector3(-gap - 0.75, 1.3, hd + 0.16))
	var sign_l := Label3D.new()
	sign_l.text = "VAULT"
	sign_l.font_size = 64
	sign_l.pixel_size = 0.0055
	sign_l.outline_size = 8
	sign_l.modulate = Color(1.0, 0.85, 0.2)
	sign_l.position = Vector3(0, 3.86, hd + 0.02)
	root.add_child(sign_l)
	var sub_l := Label3D.new()
	sub_l.text = "%s  ·  KEYCARD" % String(spec.name).to_upper()
	sub_l.font_size = 40
	sub_l.pixel_size = 0.004
	sub_l.outline_size = 6
	sub_l.modulate = accent
	sub_l.position = Vector3(0, 3.57, hd + 0.02)
	root.add_child(sub_l)
	# the door: a heavy steel plate in front of the opening that slides sideways along the wall
	var door := Node3D.new()
	door.position = Vector3(0, 0.1 + 1.65, hd + 0.1)
	root.add_child(door)
	_box(door, Vector3(DOOR_W + 0.4, 3.3, 0.3), steel, Vector3.ZERO)
	for k in 3:
		_box(door, Vector3(DOOR_W + 0.42, 0.14, 0.32), yellow, Vector3(0, -1.2 + k * 1.2, 0.0))
	var wheel := CylinderMesh.new()
	wheel.top_radius = 0.5
	wheel.bottom_radius = 0.5
	wheel.height = 0.12
	_part(door, wheel, _m(Color(0.62, 0.64, 0.68), 0.0, 0.8, 0.3), Vector3(0, 0, 0.2), Vector3(PI / 2, 0, 0))
	_box(door, Vector3(0.9, 0.1, 0.1), _m(Color(0.62, 0.64, 0.68), 0.0, 0.8, 0.3), Vector3(0, 0, 0.27))
	_box(door, Vector3(0.1, 0.9, 0.1), _m(Color(0.62, 0.64, 0.68), 0.0, 0.8, 0.3), Vector3(0, 0, 0.27))
	var dbody := StaticBody3D.new()
	dbody.collision_layer = 1
	dbody.collision_mask = 0
	dbody.set_meta("indestructible", true)
	dbody.set_meta("vault", id)
	door.add_child(dbody)
	var dcs := CollisionShape3D.new()
	var dbs := BoxShape3D.new()
	dbs.size = Vector3(DOOR_W + 0.4, 3.3, 0.3)
	dcs.shape = dbs
	dbody.add_child(dcs)
	# lights
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.85, 0.55)
	lamp.light_energy = 1.4
	lamp.omni_range = 7.5
	lamp.position = Vector3(0, 3.2, 0)
	root.add_child(lamp)
	var lamp2 := OmniLight3D.new()
	lamp2.light_color = accent
	lamp2.light_energy = 0.7
	lamp2.omni_range = 6.0
	lamp2.position = Vector3(0, 2.2, hd + 1.5)
	root.add_child(lamp2)
	# three golden chests along the back wall
	var gold := _m(Color(1.0, 0.76, 0.18), 0.35, 0.85, 0.3)
	var chests: Array = []
	for cx in [-2.3, 0.0, 2.3]:
		var ch := Models.make("chest")
		root.add_child(ch)
		ch.position = Vector3(cx, 0.1, -hd + 1.0)
		ch.rotation.y = 0.0
		ch.scale = Vector3.ONE * 1.25
		for mi in ch.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = gold
		var cb := StaticBody3D.new()
		var ccs := CollisionShape3D.new()
		var cbs := BoxShape3D.new()
		cbs.size = Vector3(1.0, 0.8, 0.7)
		ccs.shape = cbs
		ccs.position = Vector3(0, 0.4, 0)
		cb.add_child(ccs)
		ch.add_child(cb)
		var lid: Node3D = ch.get_node_or_null("chest_lid")
		var entry := {"node": ch, "pos": ch.global_position, "kind": "chest", "opened": false, "lid": lid, "vault": id, "locked": true}
		game.containers.append(entry)
		chests.append(entry)
	# bots' grid: the walls block while they stand, the door opens with the vault
	var xf := root.global_transform
	var yc := 0.0
	var zf := hd - wt / 2.0
	var segs := [
		[Vector3(-hw + wt / 2.0, yc, -hd + wt / 2.0), Vector3(hw - wt / 2.0, yc, -hd + wt / 2.0)],
		[Vector3(-hw + wt / 2.0, yc, -hd + wt / 2.0), Vector3(-hw + wt / 2.0, yc, zf)],
		[Vector3(hw - wt / 2.0, yc, -hd + wt / 2.0), Vector3(hw - wt / 2.0, yc, zf)],
		[Vector3(-hw + wt / 2.0, yc, zf), Vector3(-gap, yc, zf)],
		[Vector3(gap, yc, zf), Vector3(hw - wt / 2.0, yc, zf)],
	]
	for s in segs:
		game.nav.mark_wall(xf * s[0], xf * s[1], true)
	var nav_door := [xf * Vector3(-gap, yc, zf), xf * Vector3(gap, yc, zf)]
	game.nav.mark_wall(nav_door[0], nav_door[1], true)
	var out := xf.basis * Vector3(0, 0, 1)
	return {"id": id, "root": root, "door": door, "door_shape": dcs, "reader_mat": reader_mat, "opened": false, "card": spec.card,
			"front": xf * Vector3(0, 0, hd + 1.3), "pos": root.global_position, "home": site.home, "yaw_out": atan2(-out.x, -out.z),
			"chests": chests, "nav_door": nav_door, "body": body, "door_body": dbody}
