## Match controller: loads the island, runs the drop, storm, loot, combat effects and the win condition.
## Command-line user args (after "--"):  --demo  (an AI plays the player's character),  --seed=N,  --autotest.
extends Node3D

const Terrain := preload("res://scripts/terrain.gd")
const BOT_COUNT := 24
const BLIMP_HEIGHT := 150.0
const BLIMP_SPEED := 15.0                # 600 m in 40 s
const BLIMP_TIME := 40.0
const LOOT_SPOTS := 118
const BOT_NAMES := ["Mako", "Juniper", "Flint", "Sable", "Quill", "Tansy", "Rook", "Indigo", "Bramble", "Pike", "Wren", "Cobalt",
		"Marlow", "Saffron", "Onyx", "Fennel", "Harbor", "Lark", "Dune", "Ember", "Sorrel", "Vesper", "Gale", "Thistle"]

var terrain: Terrain
var rng := RandomNumberGenerator.new()
var island: Node3D
var storm: Storm
var hud: Control
var actors: Array[Actor] = []
var player: Actor
var controller: Node
var pickups: Array = []
var containers: Array = []               # {node, pos, kind, opened, lid}
var projectiles: Array = []
var kill_feed: Array = []                # {text, time, color}
var match_time := 0.0
var blimp: Node3D
var blimp_from := Vector3.ZERO
var blimp_dir := Vector3.FORWARD
var over := false
var winner: Actor
var announce_text := ""
var announce_time := -99.0
var demo := false
var autotest := false
var nav: NavGrid
var fx_root: Node3D
var stats := {"shots": 0, "damage": 0.0, "pickups": 0, "containers_opened": 0}
var pick_tick := 0
var doors: Array = []


func _ready() -> void:
	var seed_v := int(Time.get_unix_time_from_system())
	for a in OS.get_cmdline_user_args():
		if a == "--demo": demo = true
		if a == "--autotest": autotest = true; demo = true
		if a.begins_with("--seed="): seed_v = int(a.get_slice("=", 1))
	rng.seed = seed_v
	terrain = Terrain.new()
	island = load("res://scenes/island.tscn").instantiate()
	add_child(island)
	fx_root = Node3D.new()
	add_child(fx_root)
	_setup_doors()
	_setup_nav()
	_setup_blimp()
	_setup_loot()
	storm = Storm.new()
	add_child(storm)
	storm.setup(self)
	_setup_actors()
	hud = preload("res://scripts/hud.gd").new()
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(hud)
	hud.setup(self)
	announce("Jump when you are ready  [Space]")
	if autotest:
		Engine.time_scale = 8.0
		Engine.max_physics_steps_per_frame = 16


# ----------------------------------------------------------------------------- set-up

func _setup_nav() -> void:
	nav = NavGrid.new()
	nav.load_grid(terrain)


func _setup_doors() -> void:
	## Hinged doors swing open when someone is close; warehouse roller doors start rolled up.
	for n in island.find_children("warehouse_roller_door", "MeshInstance3D", true, false):
		n.position.y += 3.5
	for nm in ["house_door", "warehouse_door"]:
		for n in island.find_children(nm, "MeshInstance3D", true, false):
			var shape: CollisionShape3D = null
			var found := n.find_children("*", "CollisionShape3D", true, false)
			if found.size() > 0:
				shape = found[0]
			doors.append({"node": n, "shape": shape, "open": false, "yaw": n.rotation.y, "pos": n.global_position, "sign": -1.0 if nm == "house_door" else 1.0})


func _update_doors() -> void:
	for d in doors:
		var near := false
		for a in actors:
			if a.alive() and a.state == Actor.State.GROUND and a.global_position.distance_squared_to(d.pos) < 9.0:
				near = true
				break
		if near != d.open:
			d.open = near
			if d.shape:
				d.shape.set_deferred("disabled", near)
			var tw := create_tween()
			tw.tween_property(d.node, "rotation:y", d.yaw + (deg_to_rad(105) * d.sign if near else 0.0), 0.25)


func nav_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	return nav.path(from, to)


func _setup_blimp() -> void:
	var old := island.get_node_or_null("Sky/CargoBlimp")
	if old:
		old.queue_free()
	var a := rng.randf() * TAU
	blimp_dir = Vector3(cos(a), 0, sin(a))
	var mid := Vector3(rng.randf_range(-40, 40), BLIMP_HEIGHT, rng.randf_range(-40, 40))
	blimp_from = mid - blimp_dir * (BLIMP_SPEED * BLIMP_TIME * 0.5)
	blimp = Models.make("drop_vehicle")
	blimp.rotation.y = atan2(blimp_dir.x, blimp_dir.z) + PI          # the nose (asset +Z... model nose is -Y in Blender = +Z here) leads
	add_child(blimp)
	blimp.position = blimp_from


func blimp_pos() -> Vector3:
	return blimp_from + blimp_dir * BLIMP_SPEED * match_time


func blimp_seat() -> Vector3:
	return blimp_pos() + Vector3(0, -2.5, 0)


func blimp_velocity() -> Vector3:
	return blimp_dir * BLIMP_SPEED


func _setup_loot() -> void:
	# containers: the chests, ammo boxes and the supply drop placed in the level
	for n in island.get_tree().get_nodes_in_group("loot") if false else _loot_nodes():
		var kind: String = n.get_meta("loot", "")
		if kind == "chest" or kind == "ammo_box" or kind == "supply_drop":
			var lid: Node3D = n.get_node_or_null("chest_lid" if kind == "chest" else "ammo_box_lid")
			containers.append({"node": n, "pos": n.global_position, "kind": kind, "opened": false, "lid": lid})
			if kind != "ammo_box":
				_add_glow(n, Items.RARITY_COLORS[4], 0.9)
		else:
			n.queue_free()                                        # floor loot is rolled fresh every match
	# floor loot spots: inside buildings first, then spread over the island
	var spots: Array[Vector3] = []
	for h in _named(island, "House_") + _named(island, "Farmhouse"):
		for l in [Vector3(0.6, 0.3, 1.6), Vector3(-2.4, 0.3, 2.1), Vector3(-0.5, 3.35, 0.4)]:
			spots.append(h.global_transform * l)
	for w in _named(island, "Warehouse_"):
		for l in [Vector3(-4.0, 0.3, 2.0), Vector3(4.0, 0.3, -2.0), Vector3(0.0, 0.3, 0.0), Vector3(-4.5, 0.3, -2.5)]:
			spots.append(w.global_transform * l)
	for t in _named(island, "LookoutTower_"):
		spots.append(t.global_transform * Vector3(0.4, 7.35, 0.3))
		spots.append(t.global_transform * Vector3(0.0, 0.3, 3.4))
	var want := LOOT_SPOTS - containers.size()
	var tries := 0
	while spots.size() < want and tries < 5000:
		tries += 1
		var p := Vector2(rng.randf_range(-190, 190), rng.randf_range(-190, 190))
		var h2 := terrain.height(p.x, p.y)
		if h2 < 1.6 or terrain.is_water(p.x, p.y):
			continue
		var from := Vector3(p.x, h2 + 30.0, p.y)
		var res := ray(from, from + Vector3(0, -40, 0), null, 1)
		if res.is_empty() or absf(res.position.y - h2) > 0.4:      # something is standing here
			continue
		spots.append(Vector3(p.x, h2 + 0.3, p.y))
	spots.resize(mini(spots.size(), want))
	for s in spots:
		var it := Items.roll_floor(rng)
		spawn_pickup(it, s)
		if it.has("id") and Items.def(it).kind == "weapon":       # a weapon comes with some ammo next to it
			spawn_pickup({"ammo": Items.def(it).ammo}, s + Vector3(0.7, 0, 0.3))
	stats["loot_spots"] = containers.size() + spots.size()
	stats["containers"] = containers.size()


func _loot_nodes() -> Array:
	var out: Array = []
	var g := island.get_node_or_null("Loot")
	if g:
		out.append_array(g.get_children())
	for h in _named(island, "House_"):
		for c in h.get_children():
			if c.has_meta("loot"):
				out.append(c)
	return out


func _named(root: Node, prefix: String) -> Array:
	var out: Array = []
	for n in root.find_children(prefix + "*", "Node3D", true, false):
		if n.has_meta("asset"):
			out.append(n)
	return out


func _add_glow(n: Node3D, c: Color, r: float) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = r
	cyl.bottom_radius = r * 0.8
	cyl.height = 0.5
	cyl.cap_top = false
	cyl.cap_bottom = false
	cyl.radial_segments = 16
	mi.mesh = cyl
	mi.material_override = Models.glow_material(c, 1.5, 0.3)
	mi.position = Vector3(0, 0.3, 0)
	mi.name = "Glow"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)


func _setup_actors() -> void:
	var colors := [Color(0.85, 0.3, 0.25), Color(0.25, 0.55, 0.85), Color(0.3, 0.7, 0.4), Color(0.85, 0.65, 0.2), Color(0.6, 0.35, 0.8),
			Color(0.2, 0.7, 0.7), Color(0.85, 0.45, 0.65), Color(0.45, 0.5, 0.55)]
	player = Actor.new()
	add_child(player)
	player.setup(self, "You", true, Color(0.95, 0.55, 0.15), Color(0.15, 0.2, 0.3))
	actors.append(player)
	for i in BOT_COUNT:
		var b := Actor.new()
		add_child(b)
		b.setup(self, BOT_NAMES[i], false, colors[i % colors.size()], colors[(i * 3 + 2) % colors.size()].darkened(0.3))
		actors.append(b)
		var brain := preload("res://scripts/bot.gd").new()
		b.add_child(brain)
		brain.setup(self, b, rng.randf())
	if demo:
		var brain2 := preload("res://scripts/bot.gd").new()
		player.add_child(brain2)
		brain2.setup(self, player, 0.75)
	controller = preload("res://scripts/player.gd").new()
	add_child(controller)
	controller.setup(self, player, demo)


# ----------------------------------------------------------------------------- frame

func _physics_process(delta: float) -> void:
	match_time += delta
	if match_time < BLIMP_TIME + 6.0:
		blimp.position = blimp_pos()
		for p in ["blimp_prop_l", "blimp_prop_r"]:
			var prop := blimp.find_child(p, true, false)
			if prop:
				prop.rotate_object_local(Vector3(0, 0, 1), delta * 20.0)
		if match_time >= BLIMP_TIME:
			for a in actors:
				if a.state == Actor.State.BLIMP:
					a.jump_from_blimp()
	elif blimp.visible:
		blimp.visible = false
	if not storm.active and match_time > 20.0:
		storm.start()
	_update_projectiles(delta)
	_update_pickups(delta)
	_check_win()


func alive_count() -> int:
	var n := 0
	for a in actors:
		if a.alive():
			n += 1
	return n


func _check_win() -> void:
	if over:
		return
	var n := alive_count()
	if autotest and int(match_time) % 30 == 0 and int(match_time) != stats.get("last_log", -1):
		stats["last_log"] = int(match_time)
		var armed := 0
		var landed := 0
		var modes := {}
		for a in actors:
			if a.alive():
				armed += 1 if a.has_weapon() else 0
				landed += 1 if a.state == Actor.State.GROUND else 0
				var m = a.get_child(a.get_child_count() - 1).get("mode")
				modes[m] = modes.get(m, 0) + 1
		for a in actors:
			if a.alive() and a != player and int(match_time) in [90, 120]:
				var br = a.get_child(a.get_child_count() - 1)
				print("  BOT %s pos=(%.0f,%.1f,%.0f) goal=(%.0f,%.1f,%.0f) has_goal=%s path=%d i=%d vel=%.1f floor=%s mode=%s" % [a.display_name, a.global_position.x, a.global_position.y,
						a.global_position.z, br.goal.x, br.goal.y, br.goal.z, br.has_goal, br.path.size(), br.path_i, a.velocity.length(), a.is_on_floor(), br.mode])
		print("T=%d alive=%d landed=%d armed=%d pickups_left=%d modes=%s storm r=%.0f" % [int(match_time), n, landed, armed, pickups.size(), modes, storm.radius])
	if n <= 1:
		over = true
		for a in actors:
			if a.alive():
				winner = a
				a.placement = 1
		var armed_ever := 0
		for a in actors:
			armed_ever += 1 if a.ever_armed else 0
		stats["ever_armed"] = armed_ever
		print("MATCH_OVER ", JSON.stringify({"winner": winner.display_name if winner else "nobody", "winner_kills": winner.kills if winner else 0,
				"time": snappedf(match_time, 0.1), "player_place": player.placement, "player_kills": player.kills, "storm_phase": storm.phase + 1, "stats": stats}))
		if autotest:
			get_tree().quit()


func announce(t: String) -> void:
	announce_text = t
	announce_time = match_time


func ray(from: Vector3, to: Vector3, exclude: Actor = null, mask := 3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	if exclude:
		q.exclude = [exclude.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)


func can_see(from: Vector3, to: Vector3) -> bool:
	return ray(from, to, null, 1).is_empty()


func player_aim_point() -> Vector3:
	return controller.aim_point()


func sfx(_id: String, _pos: Vector3) -> void:
	pass                                                           # the sound pass is a later prompt


# ----------------------------------------------------------------------------- eliminations

func on_damage_dealt(attacker: Actor, victim: Actor, amount: float, at: Vector3) -> void:
	stats.damage += amount
	if attacker == player and hud:
		hud.add_damage_number(at, amount, victim.shield > 0.0, not victim.alive())
	if victim == player and hud and attacker:
		hud.add_damage_arc(attacker.global_position)


func on_eliminated(victim: Actor, killer: Actor) -> void:
	victim.placement = alive_count() + 1
	var cause := "killed" if (killer != null and killer != victim) else ("storm" if storm.outside(victim.global_position) > 0.0 else "other")
	stats["deaths_" + cause] = stats.get("deaths_" + cause, 0) + 1
	if autotest:
		print("ELIM t=%.0f %s by %s (%s) armed=%s pos=(%.0f,%.0f,%.0f) mode=%s" % [match_time, victim.display_name, killer.display_name if killer else "-", cause,
				victim.ever_armed, victim.global_position.x, victim.global_position.y, victim.global_position.z, victim.get_child(victim.get_child_count() - 1).get("mode")])
	var text := ""
	if killer != null and killer != victim:
		killer.kills += 1
		text = "%s eliminated %s" % [killer.display_name, victim.display_name]
	elif storm.outside(victim.global_position) > 0.0:
		text = "%s was lost to the storm" % victim.display_name
	else:
		text = "%s was eliminated" % victim.display_name
	kill_feed.append({"text": text, "time": match_time, "mine": killer == player or victim == player})
	if kill_feed.size() > 6:
		kill_feed.pop_front()
	if victim == player:
		controller.on_player_eliminated(killer)


# ----------------------------------------------------------------------------- pickups and containers

func spawn_pickup(it: Dictionary, pos: Vector3) -> void:
	var n := Node3D.new()
	fx_root.add_child(n)
	# rest on whatever is below (floor, ground, platform)
	var res := ray(pos + Vector3(0, 0.6, 0), pos + Vector3(0, -30, 0), null, 1)
	n.position = (res.position if not res.is_empty() else pos) + Vector3(0, 0.45, 0)
	var color: Color
	var model: Node3D
	if it.has("ammo"):
		color = Items.AMMO_COLORS[it.ammo]
		model = Node3D.new()
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.28, 0.18, 0.18)
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		bm.material = m
		mi.mesh = bm
		model.add_child(mi)
	else:
		color = Items.RARITY_COLORS[it.rarity]
		model = Models.make(Items.def(it).asset)
		if Items.def(it).kind == "weapon":
			model.rotation.z = PI / 2
	n.add_child(model)
	var ring := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.4
	cyl.height = 0.9
	cyl.cap_top = false
	cyl.cap_bottom = false
	cyl.radial_segments = 12
	ring.mesh = cyl
	ring.material_override = Models.glow_material(color, 1.8, 0.28)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(ring)
	pickups.append({"node": n, "model": model, "item": it, "pos": n.position, "born": match_time})


func remove_pickup(p: Dictionary) -> void:
	pickups.erase(p)
	p.node.queue_free()


func _update_pickups(delta: float) -> void:
	for p in pickups:
		p.model.rotate_y(delta * 1.4)
	# walking over ammo, stackables and anything that fits a free slot picks it up
	pick_tick += 1
	if pick_tick % 12 == 3:
		_update_doors()
	if pick_tick % 6 != 0:
		return
	for a in actors:
		if not a.alive() or a.state != Actor.State.GROUND:
			continue
		for p in pickups.duplicate():
			if match_time - p.born < 0.6 or a.global_position.distance_squared_to(p.pos) > 2.9:
				continue
			if a.wants(p.item) and a.add_item(p.item):
				stats.pickups += 1
				if p.item.has("id") and Items.def(p.item).kind == "weapon":
					a.ever_armed = true
				if a == player and hud:
					hud.add_pickup_note(p.item)
				remove_pickup(p)


func nearest_pickup(a: Actor, max_dist: float) -> Variant:
	var best = null
	var bd := max_dist * max_dist
	for p in pickups:
		var d := a.global_position.distance_squared_to(p.pos)
		if d < bd:
			bd = d
			best = p
	return best


func nearest_container(pos: Vector3, max_dist: float) -> Variant:
	var best = null
	var bd := max_dist * max_dist
	for c in containers:
		if c.opened:
			continue
		var d := pos.distance_squared_to(c.pos)
		if d < bd:
			bd = d
			best = c
	return best


func open_container(c: Dictionary, _by: Actor) -> void:
	if c.opened:
		return
	c.opened = true
	stats.containers_opened += 1
	var glow := (c.node as Node3D).get_node_or_null("Glow")
	if glow:
		glow.queue_free()
	if c.lid:
		var tw := create_tween()
		tw.tween_property(c.lid, "rotation:x", (c.lid as Node3D).rotation.x + deg_to_rad(75), 0.35)
	var p: Vector3 = c.pos + Vector3(0, 0.6, 0)
	var drops: Array = []
	match c.kind:
		"chest":
			var w := Items.roll_weapon(rng, 0.08)
			drops = [w, {"ammo": Items.def(w).ammo}, {"ammo": Items.AMMO_TYPES[rng.randi() % 5]}]
			if rng.randf() < 0.7:
				drops.append(Items.make("shield_potion" if rng.randf() < 0.5 else "medkit"))
		"ammo_box":
			drops = [{"ammo": Items.AMMO_TYPES[rng.randi() % 4]}, {"ammo": Items.AMMO_TYPES[rng.randi() % 5]}]
		"supply_drop":
			drops = [Items.roll_weapon(rng, 0.45), Items.roll_weapon(rng, 0.45), Items.make("shield_potion", 0, 2), Items.make("medkit"), {"ammo": "rockets"}, {"ammo": "medium"}]
	for i in drops.size():
		var a := TAU * i / drops.size() + rng.randf() * 0.5
		spawn_pickup(drops[i], p + Vector3(cos(a), 0, sin(a)) * 1.5)


# ----------------------------------------------------------------------------- projectiles and effects

func spawn_rocket(owner_a: Actor, pos: Vector3, dir: Vector3, dmg: float, radius: float) -> void:
	var n := Models.make("rocket_launcher").find_child("launcher_rocket", true, false).duplicate() as Node3D
	fx_root.add_child(n)
	n.global_position = pos
	n.look_at(pos + dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT)
	n.rotate_object_local(Vector3.UP, PI)
	projectiles.append({"node": n, "vel": dir * 46.0, "owner": owner_a, "damage": dmg, "radius": radius, "life": 6.0, "kind": "rocket"})


func spawn_grenade(owner_a: Actor, pos: Vector3, vel: Vector3, dmg: float, radius: float) -> void:
	var n := Models.make("grenade")
	n.scale = Vector3.ONE * 2.2
	fx_root.add_child(n)
	n.global_position = pos
	projectiles.append({"node": n, "vel": vel, "owner": owner_a, "damage": dmg, "radius": radius, "life": 2.4, "kind": "grenade"})


func _update_projectiles(delta: float) -> void:
	for pr in projectiles.duplicate():
		var n: Node3D = pr.node
		pr.life -= delta
		var from := n.global_position
		if pr.kind == "grenade":
			pr.vel.y -= 20.0 * delta
		var to: Vector3 = from + pr.vel * delta
		var res := ray(from, to, pr.owner)
		if not res.is_empty():
			if pr.kind == "rocket" or res.collider is Actor:
				explode(res.position, pr)
				continue
			pr.vel = (pr.vel as Vector3).bounce(res.normal) * 0.42      # grenades bounce and roll
			to = res.position + res.normal * 0.08
		n.global_position = to
		if pr.kind == "grenade":
			n.rotate_x(delta * 9.0)
		if pr.life <= 0.0 or to.y < -3.0:
			explode(to, pr)


func explode(pos: Vector3, pr: Dictionary) -> void:
	projectiles.erase(pr)
	pr.node.queue_free()
	for a in actors:
		if not a.alive() or a.state == Actor.State.BLIMP:
			continue
		var d := (a.global_position + Vector3(0, 0.9, 0)).distance_to(pos)
		if d < pr.radius and can_see(pos + Vector3(0, 0.3, 0), a.eye()):
			var dmg: float = pr.damage * clampf(1.15 - d / pr.radius, 0.2, 1.0) * (0.5 if a == pr.owner else 1.0)
			a.hit(dmg, pr.owner, false, pos)
			on_damage_dealt(pr.owner, a, dmg, a.eye())
	fx_blast(pos, pr.radius)


func fx_blast(pos: Vector3, radius: float) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	var mat := Models.glow_material(Color(1.0, 0.6, 0.15), 3.0, 0.8)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx_root.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.4
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius * 0.8, 0.28)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.3)
	tw.chain().tween_callback(mi.queue_free)


func fx_tracer(from: Vector3, to: Vector3, rarity: int) -> void:
	stats.shots += 1
	if autotest or from.distance_to(to) < 0.5:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var len := from.distance_to(to)
	bm.size = Vector3(0.035, 0.035, len)
	mi.mesh = bm
	var mat := Models.glow_material(Color(1.0, 0.92, 0.6).lerp(Items.RARITY_COLORS[rarity], 0.25), 2.5, 0.85)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx_root.add_child(mi)
	mi.global_position = (from + to) / 2.0
	mi.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.98 else Vector3.RIGHT)
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.09)
	tw.tween_callback(mi.queue_free)
