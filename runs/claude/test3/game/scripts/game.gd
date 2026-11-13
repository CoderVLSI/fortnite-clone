## Match controller: loads the island, runs the drop, storm, loot, combat effects and the win condition.
## Command-line user args (after "--"):  --demo  (an AI plays the player's character),  --seed=N,  --autotest.
extends Node3D

const Terrain := preload("res://scripts/terrain.gd")
const BOT_COUNT := 49
const BLIMP_HEIGHT := 150.0
const BLIMP_SPEED := 20.0                # 1000 m in 50 s: right across the big island
const BLIMP_TIME := 50.0
const LOOT_SPOTS := 340
const BOT_NAMES := ["Mako", "Juniper", "Flint", "Sable", "Quill", "Tansy", "Rook", "Indigo", "Bramble", "Pike", "Wren", "Cobalt",
		"Marlow", "Saffron", "Onyx", "Fennel", "Harbor", "Lark", "Dune", "Ember", "Sorrel", "Vesper", "Gale", "Thistle",
		"Aspen", "Basalt", "Cinder", "Delta", "Echo", "Fable", "Garnet", "Hollis", "Ivy", "Jasper", "Kestrel", "Linden",
		"Moss", "Nova", "Opal", "Pepper", "Quarry", "Rowan", "Slate", "Tundra", "Umber", "Vale", "Willow", "Yarrow", "Zephyr"]

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
var shots_dir := ""
var shot_times := [5.0, 22.0, 45.0, 70.0, 100.0, 125.0, 160.0]
var shot_i := 0
var structures: Structures
var events: WorldEvents
var buildtest := false
var movetest := false
var poses := false
var eventtest := false
var crosshairs := false
# front end (menu / pause / summary)
var player_damage := 0.0                 # damage the player has dealt, shown on the summary
var player_survived := 0.0               # match time when the player was eliminated (or the match ended)
var over_time := 0.0
var summary_shown := false
var pause_menu: CanvasLayer
var summarytest := ""                    # --summarytest=<dir>: scripted end-of-match run that saves menu_*.png captures
var soundtest := false
var audio: GameAudio
var profile := false                     # --profile: print frame-time monitors every 10 s
const WARMUP := 20.0                     # the warm-up before the blimp: everyone on the island, nothing counts yet
var warmup_left := 0.0
var difficulty := "normal"               # bot difficulty: easy / normal / sweaty (Settings, or --difficulty=)


func _ready() -> void:
	var seed_v := int(Time.get_unix_time_from_system())
	var settings_node := get_node_or_null("/root/Settings")
	var saved = settings_node.get("bot_difficulty") if settings_node else null
	if saved is String and saved in ["easy", "normal", "sweaty"]:
		difficulty = saved
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--difficulty=") and a.get_slice("=", 1) in ["easy", "normal", "sweaty"]:
			difficulty = a.get_slice("=", 1)
		if a == "--demo": demo = true
		if a == "--autotest": autotest = true; demo = true
		if a == "--buildtest": buildtest = true
		if a == "--movetest": movetest = true
		if a == "--poses": poses = true
		if a == "--eventtest": eventtest = true
		if a == "--crosshairs": crosshairs = true
		if a.begins_with("--summarytest="): summarytest = a.get_slice("=", 1)
		if a == "--soundtest": soundtest = true
		if a == "--profile": profile = true
		if a.begins_with("--seed="): seed_v = int(a.get_slice("=", 1))
		if a.begins_with("--shots="):
			shots_dir = a.get_slice("=", 1)
			demo = true
			Engine.max_physics_steps_per_frame = 90          # keep game time real even when frames are slow
	rng.seed = seed_v
	terrain = Terrain.new()
	island = load("res://scenes/island.tscn").instantiate()
	add_child(island)
	var tb := island.get_node_or_null("Terrain/TerrainBody/CollisionShape3D") as CollisionShape3D
	if tb == null:
		var found := island.get_node("Terrain/TerrainBody").find_children("*", "CollisionShape3D", false, false)
		tb = found[0] if found.size() > 0 else null
	if tb and tb.shape is HeightMapShape3D:
		terrain.use_baked_heights(tb.shape, tb.scale.x)
	fx_root = Node3D.new()
	add_child(fx_root)
	audio = GameAudio.new()
	add_child(audio)
	audio.setup(self)
	_setup_doors()
	structures = Structures.new()
	add_child(structures)
	structures.setup(self)
	stats["destructible_parts"] = structures.level_count
	_setup_nav()
	_setup_blimp()
	events = WorldEvents.new()
	add_child(events)
	events.setup(self)
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
	announce("Jump when you are ready")
	pause_menu = preload("res://scripts/pause_menu.gd").new()       # front end: Esc opens it (player.gd)
	add_child(pause_menu)
	pause_menu.setup(self)
	if summarytest != "":
		var st := preload("res://scripts/menutest.gd").new()
		add_child(st)
		st.setup(self, summarytest)
	if OS.has_feature("mobile"):                                   # phones: no shadows or MSAA, shorter view
		var sun := island.find_child("Sun", true, false) as DirectionalLight3D
		if sun:
			sun.shadow_enabled = false
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	if crosshairs:
		var ct := preload("res://scripts/crosshairtest.gd").new()
		add_child(ct)
		ct.setup(self)
	if eventtest:
		var et := preload("res://scripts/eventtest.gd").new()
		add_child(et)
		et.setup(self)
	if poses:
		var ps := preload("res://scripts/posesheet.gd").new()
		add_child(ps)
		ps.setup(self)
	if movetest:
		var mt := preload("res://scripts/movetest.gd").new()
		add_child(mt)
		mt.setup(self)
	if buildtest:
		var t := preload("res://scripts/selftest.gd").new()
		add_child(t)
		t.setup(self)
	if soundtest:
		_run_soundtest()
	if autotest:
		Engine.time_scale = 8.0
		Engine.max_physics_steps_per_frame = 16
	_start_warmup()
	var st := get_node_or_null("/root/Settings")
	if st and not demo:
		st.play_music("battle", -9.0, 2.5)          # sits under gunfire and footsteps


# ----------------------------------------------------------------------------- set-up

func _setup_nav() -> void:
	nav = NavGrid.new()
	nav.load_grid(terrain)


func _setup_doors() -> void:
	## Hinged doors swing open when someone is close; warehouse roller doors start rolled up.
	for n in island.find_children("warehouse_roller_door", "MeshInstance3D", true, false):
		n.position.y += 3.5
	# a house's door frame and trim are decoration: the shell already has the opening, and their colliders
	# put a lip and a low lintel in the doorway that trapped people inside
	for deco in ["house_door_frame", "house_trim"]:
		for n in island.find_children(deco, "MeshInstance3D", true, false):
			for cs in n.find_children("*", "CollisionShape3D", true, false):
				cs.disabled = true
	for nm in ["house_door", "warehouse_door"]:
		for n in island.find_children(nm, "MeshInstance3D", true, false):
			var shape: CollisionShape3D = null
			var found := n.find_children("*", "CollisionShape3D", true, false)
			if found.size() > 0:
				shape = found[0]
			doors.append({"node": n, "shape": shape, "open": false, "yaw": n.rotation.y, "pos": n.global_position, "sign": -1.0 if nm == "house_door" else 1.0})


func _update_doors() -> void:
	var who: Array = actors if hired == null else actors + [hired]
	for d in doors:
		var near := false
		for a in who:
			if a.alive() and a.state == Actor.State.GROUND and a.global_position.distance_squared_to(d.pos) < 9.0:
				near = true
				break
		if near != d.open:
			d.open = near
			if d.shape:
				d.shape.set_deferred("disabled", near)
			var tw := create_tween()
			tw.tween_property(d.node, "rotation:y", d.yaw + (deg_to_rad(105) * d.sign if near else 0.0), 0.25)


func forget_door(n: Node) -> void:
	for d in doors.duplicate():
		if d.node == n:
			doors.erase(d)


var prof := {}                          # --profile: microseconds spent per area since the last report


func prof_add(key: String, us: int) -> void:
	prof[key] = prof.get(key, 0) + us


func nav_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if not profile:
		return nav.path(from, to, can_see)
	var t0 := Time.get_ticks_usec()
	var p := nav.path(from, to, can_see)
	prof_add("nav", Time.get_ticks_usec() - t0)
	prof["nav_n"] = prof.get("nav_n", 0) + 1
	return p


func _setup_blimp() -> void:
	var old := island.get_node_or_null("Sky/CargoBlimp")
	if old:
		old.queue_free()
	var a := rng.randf() * TAU
	blimp_dir = Vector3(cos(a), 0, sin(a))
	var mid := Vector3(rng.randf_range(-90, 90), BLIMP_HEIGHT, rng.randf_range(-90, 90))
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
		var p := Vector2(rng.randf_range(-370, 370), rng.randf_range(-370, 370))
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


var npcs: Array = []                      # characters for hire (not players: no placement, not in actors)
var hired: Actor = null                   # the one working for the player
## [name, where (offset from a point of interest), body, outfit, accent, what they say, cost in gold]
const NPCS := [
	["Marlo", "village", Vector2(-14, 14), "Soldier", Color(0.35, 0.55, 0.3), Color(0.25, 0.18, 0.1), "Ten years I've guarded this village. For %d gold I'll guard you instead.", 200],
	["Frost", "snow_town", Vector2(-8, 9), "Soldier", Color(0.9, 0.93, 1.0), Color(0.3, 0.45, 0.7), "Cold up here, isn't it? Pay me and I'll keep the others colder.", 200],
	["Dusty", "desert_town", Vector2(9, -7), "Soldier", Color(0.85, 0.7, 0.45), Color(0.45, 0.25, 0.15), "Sand in my boots, aim in my eye. %d gold and I ride with you.", 180],
	["B0LT", "depot", Vector2(-12, 6), "Xbot", Color(0.95, 0.85, 0.2), Color(0.15, 0.15, 0.18), "UNIT B0LT ONLINE. COMBAT ESCORT AVAILABLE. FEE: %d GOLD.", 250],
	["Haywire", "farm", Vector2(-10, 12), "Xbot", Color(0.35, 0.75, 0.35), Color(0.85, 0.6, 0.2), "Beep. The crows are gone. I'm bored. Hire me for %d?", 220],
	["Captain Shore", "east_cove", Vector2(7, -9), "Soldier", Color(0.25, 0.45, 0.8), Color(0.9, 0.85, 0.7), "Ahoy. My boat sank, my aim didn't. %d gold.", 200],
]


func _setup_npcs() -> void:
	for d in NPCS:
		var c: Vector2 = terrain.get(d[1])
		var spot: Vector3 = events._dry_spot(c + d[2])
		var n := Actor.new()
		add_child(n)
		n.setup(self, d[0], false, d[4], d[5], d[3])
		n.is_npc = true
		n.state = Actor.State.GROUND
		n.global_position = spot + Vector3(0, 0.3, 0)
		var brain := preload("res://scripts/npc.gd").new()
		brain.name = "NpcBrain"
		n.add_child(brain)
		var line: String = d[6]
		brain.setup(self, n, {"name": d[0], "line": line % d[7] if line.contains("%d") else line, "cost": d[7]})
		npcs.append(n)


func npc_near(a: Actor) -> Variant:
	for n in npcs:
		if not n.hired and n.alive() and a.global_position.distance_to(n.global_position) < 3.0:
			return n
	return null


func hire_npc(n: Actor) -> bool:
	## The player pays and the character joins them: a gun, ammo, a shield and a bot brain that fights on their side.
	var brain: Node = n.get_node("NpcBrain")
	var cost: int = brain.info.cost
	if hired != null or warming_up() or player.gold < cost or not n.alive():
		return false
	player.gold -= cost
	brain.plate.text = "%s
your ally" % brain.info.name
	brain.plate.modulate = Color(0.45, 1.0, 0.5)
	brain.set_physics_process(false)
	n.hired = true
	hired = n
	n.add_item(Items.make("assault_rifle", 2))
	n.ammo["medium"] = 150
	n.shield = 50.0
	var bot := preload("res://scripts/bot.gd").new()
	n.add_child(bot)
	bot.setup(self, n, 0.75)
	bot.ally_of = player
	bot.mode = "follow"
	announce("%s joins you!" % brain.info.name)
	sfx("chest_open", n.global_position)
	return true


func _setup_actors() -> void:
	var colors := [Color(0.85, 0.3, 0.25), Color(0.25, 0.55, 0.85), Color(0.3, 0.7, 0.4), Color(0.85, 0.65, 0.2), Color(0.6, 0.35, 0.8),
			Color(0.2, 0.7, 0.7), Color(0.85, 0.45, 0.65), Color(0.45, 0.5, 0.55)]
	player = Actor.new()
	add_child(player)
	var look: Array = [Color(0.95, 0.55, 0.15), Color(0.15, 0.2, 0.3), "Soldier"]
	var stn := get_node_or_null("/root/Settings")
	if stn and not demo:
		var o: Array = stn.OUTFITS[stn.outfit]          # the outfit picked in the lobby's locker
		look = [o[1], o[2], o[3]]
	player.setup(self, "You", true, look[0], look[1], look[2])
	actors.append(player)
	for i in BOT_COUNT:
		var b := Actor.new()
		add_child(b)
		var robot := i % 4 == 3                                   # a quarter of the bots wear robot skins
		b.setup(self, BOT_NAMES[i], false, colors[i % colors.size()], colors[(i * 3 + 2) % colors.size()].darkened(0.3) if not robot else colors[(i * 5 + 1) % colors.size()], "Xbot" if robot else "Soldier")
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
	_setup_npcs()


# ----------------------------------------------------------------------------- frame

func warming_up() -> bool:
	return warmup_left > 0.0


func _start_warmup() -> void:
	## A real match (started from the lobby, no test or demo flags) opens with a short warm-up on the island.
	var st := get_node_or_null("/root/Settings")
	var flags: Array = Array(OS.get_cmdline_user_args()).filter(func(x: String) -> bool: return x.begins_with("--"))
	if demo or not flags.is_empty() or (st and st.get("skip_warmup")):
		return
	warmup_left = WARMUP
	announce_text = ""                                   # no blimp to jump from yet
	var spots: Array = get_tree().get_nodes_in_group("spawn")
	spots.shuffle()
	for i in actors.size():
		var a: Actor = actors[i]
		var m: Node3D = spots[i % spots.size()]
		var off := Vector3(cos(i * 2.4), 0, sin(i * 2.4)) * (2.5 * (i / spots.size()))
		a.state = Actor.State.GROUND
		a.global_position = m.global_position + off + Vector3(0, 0.3, 0)
		a.velocity = Vector3.ZERO
		a.aim_yaw = m.rotation.y + PI
	controller.yaw = player.aim_yaw


func _end_warmup() -> void:
	## Everyone boards the blimp with nothing: the match proper starts now.
	warmup_left = 0.0
	for a in actors:
		a.stop_emote()
		a.zip = null
		a.mantle_t = -1.0
		a.launched = false
		a.velocity = Vector3.ZERO
		a.set_crouched(false)
		a.build_piece = ""
		for i in Items.SLOTS:
			a.slots[i] = null
		a.active = -1
		for t in Items.AMMO_TYPES:
			a.ammo[t] = 0
		a.mats = {"wood": 0, "brick": 0, "metal": 0}
		a.hp = 100.0
		a.shield = 0.0
		a.state = Actor.State.BLIMP
		a._refresh_held()
	announce("All aboard the blimp! Jump when you are ready")


func _physics_process(delta: float) -> void:
	if warmup_left > 0.0:
		warmup_left -= delta
		pick_tick += 1
		if pick_tick % 12 == 3:
			_update_doors()
		if warmup_left <= 0.0:
			_end_warmup()
		return
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
	if autotest and OS.get_cmdline_user_args().has("--trace") and Engine.get_physics_frames() % 60 == 0:
		for a in actors:                                    # follow every bot that is standing in the storm
			if not a.alive() or a.state < Actor.State.GROUND or storm.outside(a.global_position) <= 0.0:
				continue
			var br = a.get_child(a.get_child_count() - 1)
			if br.get("mode") == null:
				continue
			var wp: Vector3 = br.path[mini(br.path_i, br.path.size() - 1)] if br.path.size() > 0 else Vector3.ZERO
			print("TR %.1f %s st=%d mode=%s hp=%.0f out=%.1f pos=(%.1f,%.1f,%.1f) goal=(%.1f,%.1f) d=%.1f wp=(%.1f,%.1f) i=%d/%d vel=%.1f walk=%s" % [match_time, a.display_name, a.state, br.mode,
					a.hp, storm.outside(a.global_position), a.global_position.x, a.global_position.y, a.global_position.z, br.goal.x, br.goal.z,
					Vector2(br.goal.x - a.global_position.x, br.goal.z - a.global_position.z).length(), wp.x, wp.z, br.path_i, br.path.size(), a.velocity.length(), nav.walkable(a.global_position)])
	_update_projectiles(delta)
	_update_pickups(delta)
	_check_win()
	if profile and Engine.get_physics_frames() % 600 == 0:
		print("PROFILE t=%.0f alive=%d physics=%.2f ms process=%.2f ms fps=%d" % [match_time, alive_count(),
				Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				Engine.get_frames_per_second()])
		var parts := []
		for k in prof:
			parts.append("%s=%s" % [k, ("%.1fms/s" % (prof[k] / 10000.0)) if not k.ends_with("_n") else str(prof[k] / 10)])
		print("   ", " ".join(parts))
		prof.clear()


func _process(_d: float) -> void:
	if over and not summary_shown and not autotest and match_time - over_time >= 3.0:
		summary_shown = true                                       # banner has been up for ~3 s: show the summary panel
		var sm := preload("res://scripts/summary.gd").new()
		add_child(sm)
		sm.setup(self)
	if shots_dir != "" and shot_i < shot_times.size() and match_time >= shot_times[shot_i]:
		if shot_times[shot_i] == 100.0:
			controller.show_map = true
		elif shot_times[shot_i] == 125.0:
			controller.show_map = false
		get_viewport().get_texture().get_image().save_png(shots_dir.path_join("game_%03d.png" % int(shot_times[shot_i])))
		print("SHOT ", shot_times[shot_i])
		shot_i += 1
		if shot_i >= shot_times.size() or over:
			get_tree().quit()


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
		over_time = match_time
		if player.alive():
			player_survived = match_time
			sfx("victory", Vector3.INF)
			player.placement = 1
			_record_career()
		for a in actors:
			if a.alive():
				winner = a
				a.placement = 1
		var armed_ever := 0
		for a in actors:
			armed_ever += 1 if a.ever_armed else 0
		stats["ever_armed"] = armed_ever
		stats["pieces_built"] = structures.built
		stats["parts_destroyed"] = structures.destroyed
		print("MATCH_OVER ", JSON.stringify({"difficulty": difficulty, "winner": winner.display_name if winner else "nobody", "winner_kills": winner.kills if winner else 0,
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


func sfx(id: String, pos: Vector3) -> void:
	## Sound hook: audio.gd maps the id to a file. Vector3.INF as pos plays it non-positionally.
	audio.play(id, pos)


func _run_soundtest() -> void:
	## --soundtest: play every mapped id once and report any without a file, then quit.
	var bad: Array = []
	for id in GameAudio.SOUNDS:
		if not audio.has_sound(id):
			bad.append(id)
		audio.play(id, Vector3.INF)
	for l in GameAudio.LOOPS.values():
		if not ResourceLoader.exists(GameAudio.DIR + l + ".mp3"):
			bad.append(l)
	print("SOUNDTEST ", ("all mapped (%d ids)" % GameAudio.SOUNDS.size()) if bad.is_empty() else "MISSING " + str(bad))
	get_tree().quit()


# ----------------------------------------------------------------------------- eliminations

func on_damage_dealt(attacker: Actor, victim: Actor, amount: float, at: Vector3, headshot := false) -> void:
	stats.damage += amount
	if attacker == player:
		player_damage += amount
	if attacker == player and attacker != victim:
		sfx("hit_marker", Vector3.INF)
	if attacker == player and hud:
		hud.add_damage_number(at, amount, victim.shield > 0.0, not victim.alive(), headshot)
	if victim == player and hud and attacker:
		hud.add_damage_arc(attacker.global_position)


var xp_earned := -1                       # XP from this match once it is recorded (shown on the summary)


func _record_career() -> void:
	## Once per match, for real matches only: placement, kills and XP go into the career shown in the lobby.
	if xp_earned >= 0 or demo or autotest:
		return
	var st := get_node_or_null("/root/Settings")
	if st:
		xp_earned = st.record_match(player.placement, player.kills, actors.size())


func on_eliminated(victim: Actor, killer: Actor) -> void:
	if victim.is_npc:                                    # a hired character is not a player: no placement
		if hired == victim:
			hired = null
		kill_feed.append({"text": "%s has fallen" % victim.display_name, "time": match_time, "mine": true})
		return
	victim.placement = alive_count() + 1
	if victim == player:
		player_survived = match_time
		_record_career()
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
	if killer == player and victim != player:
		sfx("elimination", Vector3.INF)
	if victim == player:
		controller.on_player_eliminated(killer)
	elif killer != null and killer != player and killer.alive() and rng.randf() < 0.35:
		killer.start_emote(["samba", "nod", "wave"][rng.randi() % 3])    # bots celebrate now and then


# ----------------------------------------------------------------------------- pickups and containers

func spawn_pickup(it: Dictionary, pos: Vector3) -> void:
	var n := Node3D.new()
	fx_root.add_child(n)
	# rest on whatever is below (floor, ground, platform)
	var res := ray(pos + Vector3(0, 0.6, 0), pos + Vector3(0, -30, 0), null, 1)
	n.position = (res.position if not res.is_empty() else pos) + Vector3(0, 0.45, 0)
	var color: Color
	var model: Node3D
	if it.has("forage"):                               # apples and mushrooms just lie there
		model = Models.make(it.forage)
		n.add_child(model)
		n.position.y -= 0.42
		pickups.append({"node": n, "model": model, "item": it, "pos": n.position, "born": match_time, "still": true})
		return
	if it.has("gold"):
		color = Color(1.0, 0.8, 0.25)
		model = Models.make("gold_bars")
	elif it.has("ammo") or it.has("mat"):
		color = Items.AMMO_COLORS[it.ammo] if it.has("ammo") else Items.MAT_COLORS[it.mat]
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


func settle_pickups(at: Vector3, radius: float) -> void:
	## Something broke: loot that was lying on it falls to whatever is below (checked once the colliders are gone).
	await get_tree().create_timer(0.2).timeout
	for p in pickups:
		if Vector2(p.pos.x - at.x, p.pos.z - at.z).length() > radius:
			continue
		var hit := ray(p.pos + Vector3(0, 0.1, 0), p.pos - Vector3(0, 80, 0), null, 1)
		var floor_y: float = (hit.position.y if not hit.is_empty() else terrain.height(p.pos.x, p.pos.z)) + 0.3
		if p.pos.y - floor_y > 0.25:
			p["fall_to"] = floor_y
			p["fall_v"] = 0.0


func remove_pickup(p: Dictionary) -> void:
	pickups.erase(p)
	p.node.queue_free()


func _update_pickups(delta: float) -> void:
	for p in pickups:
		if not p.get("still", false):
			p.model.rotate_y(delta * 1.4)
		if p.has("fall_to"):                               # dropping off a broken floor
			p.fall_v += 22.0 * delta
			p.pos.y = maxf(p.pos.y - p.fall_v * delta, p.fall_to)
			(p.node as Node3D).position = p.pos
			if p.pos.y <= p.fall_to:
				p.erase("fall_to")
				p.erase("fall_v")
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
					sfx("pickup", Vector3.INF)
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
	if c.opened or warming_up():
		return
	c.opened = true
	sfx("chest_open", c.pos)
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
				drops.append(Items.roll_heal(rng, true))
			drops.append({"gold": 20 + rng.randi() % 26})
		"ammo_box":
			drops = [{"ammo": Items.AMMO_TYPES[rng.randi() % 4]}, {"ammo": Items.AMMO_TYPES[rng.randi() % 5]}]
		"supply_drop":
			drops = [Items.roll_weapon(rng, 0.45), Items.roll_weapon(rng, 0.45), Items.make("shield_potion", 0, 2), Items.make("mega_flask") if rng.randf() < 0.3 else Items.make("medkit"), {"gold": 120}, {"ammo": "rockets"}, {"ammo": "medium"}]
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
	_update_mythic_fx(delta)
	for pr in projectiles.duplicate():
		var n: Node3D = pr.node
		pr.life -= delta
		var from := n.global_position
		if pr.kind == "grenade":
			pr.vel.y -= 20.0 * delta
		elif pr.kind == "orb":
			pr.vel.y -= 7.0 * delta                      # a slow arc
		var to: Vector3 = from + pr.vel * delta
		var res := ray(from, to, pr.owner)
		if not res.is_empty():
			if pr.kind == "rocket" or pr.kind == "orb" or res.collider is Actor:
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
	if pr.kind == "orb":
		shock_burst(pos, pr)
		return
	for a in actors:
		if not a.alive() or a.state == Actor.State.BLIMP:
			continue
		var d := (a.global_position + Vector3(0, 0.9, 0)).distance_to(pos)
		if d < pr.radius and can_see(pos + Vector3(0, 0.3, 0), a.eye()):
			var dmg: float = pr.damage * clampf(1.15 - d / pr.radius, 0.2, 1.0) * (0.5 if a == pr.owner else 1.0)
			a.hit(dmg, pr.owner, false, pos)
			on_damage_dealt(pr.owner, a, dmg, a.eye())
	sfx("explosion", pos)
	structures.explode(pos, pr.radius, pr.damage * Structures.EXPLOSION_MULT, pr.owner)
	fx_blast(pos, pr.radius)


func fx_splash(at: Vector3, size: float) -> void:
	stats["splashes"] = stats.get("splashes", 0) + 1
	if autotest:
		return
	_fx_disc(at + Vector3(0, 0.04, 0), 0.6, 2.6 * size, 0.55, Color(0.92, 0.97, 1.0, 0.8))
	structures.burst(at + Vector3(0, 0.3, 0), Color(0.82, 0.92, 1.0), int(12 * size), 2.5 * size, 6.0 * size, 0.45)


func fx_foam(at: Vector3) -> void:
	stats["foam"] = stats.get("foam", 0) + 1
	if autotest:
		return
	_fx_disc(at, 0.3, 1.0, 1.3, Color(1, 1, 1, 0.55))


func _fx_disc(at: Vector3, r0: float, r1: float, life: float, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 0.03
	cyl.radial_segments = 20
	mi.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx_root.add_child(mi)
	mi.global_position = at
	mi.scale = Vector3(r0, 1, r0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(r1, 1, r1), life)
	tw.tween_property(mat, "albedo_color:a", 0.0, life)
	tw.chain().tween_callback(mi.queue_free)


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


# ----------------------------------------------------------------------------- mythic weapon effects
## Shockwave orb (Tinker's Shockwave Launcher), the tendril of Ravage's Grasp. The web line lives in actor.gd.

func spawn_shockwave(owner_a: Actor, pos: Vector3, dir: Vector3, d: Dictionary) -> void:
	## A slow arcing orb; it bursts on contact (or after 5 s) into shock_burst().
	var n := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.32
	sm.height = 0.64
	sm.radial_segments = 12
	sm.rings = 6
	n.mesh = sm
	n.material_override = Models.glow_material(Color(0.62, 0.9, 1.0), 3.5, 0.95)
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var halo := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.55
	hm.height = 1.1
	hm.radial_segments = 10
	hm.rings = 5
	halo.mesh = hm
	halo.material_override = Models.glow_material(Color(0.4, 0.7, 1.0), 2.0, 0.28)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(halo)
	fx_root.add_child(n)
	n.global_position = pos
	projectiles.append({"node": n, "vel": dir * 30.0, "owner": owner_a, "damage": float(d.damage), "radius": float(d.radius), "life": 5.0,
		"kind": "orb", "knock": float(d.get("knock", 34.0)), "struct": float(d.get("struct_damage", 400.0))})


func shock_burst(pos: Vector3, pr: Dictionary) -> void:
	## The shockwave: small damage and a big launch (the launch pad's launch(), plus sideways push) for every actor in
	## the radius, yourself included, and heavy damage to built structures. No fall damage from the knock.
	var radius: float = pr.radius
	for a in actors:
		if not a.alive() or a.state == Actor.State.BLIMP:
			continue
		var c := a.global_position + Vector3(0, 0.9, 0)
		var d := c.distance_to(pos)
		if d >= radius or not can_see(pos + Vector3(0, 0.4, 0), a.eye()):
			continue
		var fall := clampf(1.15 - d / radius, 0.45, 1.0)
		if a != pr.owner:
			var dmg: float = pr.damage * fall
			a.hit(dmg, pr.owner, false, pos)
			on_damage_dealt(pr.owner, a, dmg, a.eye())
		var away := Vector3(a.global_position.x - pos.x, 0, a.global_position.z - pos.z)
		if away.length() < 0.3:
			away = Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
		away = away.normalized()
		a.receive_knock(float(pr.knock) * fall, away * 20.0 * fall)
	sfx("shockwave", pos)
	structures.explode(pos, radius, float(pr.struct), pr.owner)
	fx_shockwave(pos, radius)


func fx_shockwave(pos: Vector3, radius: float) -> void:
	if autotest:
		return
	_fx_disc(pos + Vector3(0, 0.1, 0), 0.8, radius * 1.1, 0.5, Color(0.6, 0.88, 1.0, 0.7))
	_fx_disc(pos + Vector3(0, 0.6, 0), 0.5, radius * 0.8, 0.38, Color(1.0, 1.0, 1.0, 0.6))
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 14
	sm.rings = 7
	mi.mesh = sm
	var mat := Models.glow_material(Color(0.6, 0.9, 1.0), 3.0, 0.55)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx_root.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.5
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius, 0.35)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.4)
	tw.chain().tween_callback(mi.queue_free)


var tendrils: Array = []


func fx_tendril(owner_a: Actor, to, life: float, whiff := false) -> Dictionary:
	## A thick, dark red, slightly wavy tendril from the owner's hand to a point or an Actor (followed). It shoots out in
	## 0.12 s and stays for `life` seconds; set the returned dict's `life` to end it earlier.
	var mi := MeshInstance3D.new()
	mi.mesh = ImmediateMesh.new()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.36, 0.03, 0.07)
	m.emission_enabled = true
	m.emission = Color(0.5, 0.04, 0.05)
	m.emission_energy_multiplier = 0.6
	m.roughness = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	fx_root.add_child(mi)
	var fx := {"mi": mi, "owner": owner_a, "to": to, "t": 0.0, "life": life, "whiff": whiff}
	tendrils.append(fx)
	_draw_tendril(fx)
	return fx


func _update_mythic_fx(delta: float) -> void:
	for fx in tendrils.duplicate():
		fx.t += delta
		var o: Actor = fx.owner
		if fx.t >= fx.life or o == null or not is_instance_valid(o) or not o.alive():
			tendrils.erase(fx)
			fx.mi.queue_free()
			continue
		_draw_tendril(fx)


func _draw_tendril(fx: Dictionary) -> void:
	var o: Actor = fx.owner
	var a: Vector3 = o._hand_pos()
	var target = fx.to
	var b: Vector3 = (target as Actor).centre() if target is Actor else target
	var t: float = fx.t
	var reach := clampf(t / 0.12, 0.0, 1.0)
	var fade := clampf((float(fx.life) - t) / 0.18, 0.0, 1.0)
	if fx.whiff:
		reach = clampf(t / 0.2, 0.0, 1.0) if t < 0.2 else clampf(1.0 - (t - 0.2) / 0.25, 0.0, 1.0)
	var tip := a.lerp(b, reach)
	var axis := tip - a
	var len := axis.length()
	var im := fx.mi.mesh as ImmediateMesh
	im.clear_surfaces()
	if len < 0.2:
		return
	var dir := axis / len
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	var side := dir.cross(up).normalized()
	var vert := side.cross(dir).normalized()
	var segs := clampi(int(len / 1.2) + 6, 8, 28)
	var sides := 6
	var rings := []
	for i in segs + 1:
		var k := float(i) / segs
		var wob := sin(k * 11.0 - t * 22.0) * 0.16 * sin(k * PI) * (1.0 - reach * 0.35) * fade
		var wob2 := cos(k * 9.0 - t * 17.0) * 0.12 * sin(k * PI) * fade
		var c := a + axis * k + side * wob + vert * wob2
		var r := lerpf(0.11, 0.045, k) * (0.4 + 0.6 * fade)
		var ring := []
		for j in sides:
			var ang := TAU * j / sides
			ring.append(c + (side * cos(ang) + vert * sin(ang)) * r)
		rings.append(ring)
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segs:
		for j in sides:
			var j2 := (j + 1) % sides
			var p0: Vector3 = rings[i][j]
			var p1: Vector3 = rings[i][j2]
			var p2: Vector3 = rings[i + 1][j2]
			var p3: Vector3 = rings[i + 1][j]
			var n := (p1 - p0).cross(p3 - p0).normalized()
			for q in [p0, p1, p2, p0, p2, p3]:
				im.surface_set_normal(n)
				im.surface_add_vertex(q)
	im.surface_end()
	fx.mi.global_transform = Transform3D.IDENTITY
