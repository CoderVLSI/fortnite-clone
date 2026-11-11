## Automated check of crouching, sliding, mantling and swimming.  Run:
##   godot --headless --path <project> -- --movetest
extends Node

var game: Node
var a: Actor
var lines: Array = []
var fails := 0
var boxes: Array = []


func setup(g: Node) -> void:
	game = g


func check(name: String, ok: bool, detail := "") -> void:
	lines.append(("PASS  " if ok else "FAIL  ") + name + ("   " + detail if detail != "" else ""))
	if not ok:
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func snap(name: String, yaw: float, pitch: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	game.controller.yaw = yaw
	game.controller.pitch = pitch
	await frames(6)
	var dir := ProjectSettings.globalize_path("res://").path_join("../captures")
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("SNAP ", name)


func put(p: Vector3, yaw := 0.0) -> void:
	a.mantle_t = -1.0
	a.sliding = false
	a.set_crouched(false)
	a.state = Actor.State.GROUND
	a.global_position = p
	a.velocity = Vector3.ZERO
	a.aim_yaw = yaw
	a.aim_pitch = 0.0
	a.in_move = Vector2.ZERO
	a.in_jump = false
	a.fall_start = p.y
	await frames(8)


func ground(x: float, z: float) -> Vector3:
	return Vector3(x, game.terrain.height(x, z) + 0.05, z)


func box(centre_bottom: Vector3, size: Vector3) -> void:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	b.add_child(mi)
	game.add_child(b)
	b.global_position = centre_bottom + Vector3(0, size.y / 2, 0)
	boxes.append(b)


func hspeed() -> float:
	return Vector2(a.velocity.x, a.velocity.z).length()


func _ready() -> void:
	await frames(5)
	a = game.player
	game.controller.demo = true                      # inputs come from this script
	for o in game.actors:
		if o != a:
			o.process_mode = Node.PROCESS_MODE_DISABLED
	var T = game.terrain
	var base := ground(T.village.x + 22.0, T.village.y + 6.0)
	# ---------------------------------------------------------------- crouch
	await put(base)
	a.in_crouch = true
	await frames(3)
	check("crouch toggles on", a.crouched)
	check("crouching lowers the body", absf((a.shape_node.shape as CapsuleShape3D).height - Actor.CROUCH_H) < 0.01 and a.eye().y - a.global_position.y < 1.1)
	var p0 := a.global_position
	a.in_move = Vector2(0, 1)
	a.in_sprint = true
	await frames(60)
	var crouch_d := Vector2(a.global_position.x - p0.x, a.global_position.z - p0.z).length()
	check("crouched movement is slow", crouch_d > 2.0 and crouch_d < 3.4, "%.2f m in 1 s" % crouch_d)
	a.in_move = Vector2.ZERO
	a.in_crouch = true
	await frames(3)
	check("crouch toggles off", not a.crouched)
	# ---------------------------------------------------------------- slide on the flat
	await put(base, PI)
	a.in_move = Vector2(0, 1)
	a.in_sprint = true
	await frames(45)
	var run_speed := hspeed()
	a.in_crouch = true
	await frames(2)
	check("Ctrl while sprinting starts a slide", a.sliding, "running at %.1f m/s" % run_speed)
	var t := 0
	var peak := 0.0
	while a.sliding and t < 600:
		peak = maxf(peak, hspeed())
		await frames(1)
		t += 1
	check("slide slows down on flat ground", t > 60 and t < 400, "%.1f s, peak %.1f m/s" % [t / 60.0, peak])
	check("slide ends in a crouch", a.crouched and not a.sliding)
	var flat_time := t
	# ---------------------------------------------------------------- slide downhill
	var best := {}
	for th in T.towers:
		for k in 24:
			var ang := TAU * k / 24.0
			for r in [14.0, 18.0, 22.0, 26.0]:
				var x: float = th.x + cos(ang) * r
				var z: float = th.y + sin(ang) * r
				var down := Vector2(cos(ang), sin(ang))
				var drop: float = T.height(x, z) - T.height(x + down.x * 12.0, z + down.y * 12.0)
				if T.height(x, z) < 3.0 or drop < 2.5 or drop > 5.5:
					continue
				var o := ground(x, z) + Vector3(0, 1.0, 0)
				var clear := true
				for s in range(2, 25, 2):
					var q := ground(x + down.x * s, z + down.y * s) + Vector3(0, 1.0, 0)
					if not game.ray(o, q, a, 1).is_empty():
						clear = false
						break
					o = q
				if clear and (best.is_empty() or absf(drop - 4.0) < absf(best.drop - 4.0)):
					best = {"p": ground(x, z), "yaw": atan2(-down.x, -down.y), "drop": drop}
	check("found a clear hillside", not best.is_empty())
	if not best.is_empty():
		await put(best.p, best.yaw)
		a.in_move = Vector2(0, 1)
		a.in_sprint = true
		await frames(20)
		a.in_crouch = true
		await frames(2)
		var hill_peak := 0.0
		var ht := 0
		while a.sliding and ht < 90:
			hill_peak = maxf(hill_peak, hspeed())
			await frames(1)
			ht += 1
		check("slide speeds up downhill", hill_peak > peak + 0.8, "peak %.1f m/s downhill vs %.1f on the flat (%.1f m drop over 12 m)" % [hill_peak, peak, best.drop])
		a.in_move = Vector2.ZERO
		await frames(30)
	# ---------------------------------------------------------------- mantle
	var row := ground(T.village.x - 24.0, T.village.y - 8.0)
	for spec in [[1.5, true, "1.5 m ledge"], [0.9, true, "0.9 m ledge"], [2.2, true, "2.2 m ledge"], [3.0, false, "3.0 m wall (too high)"]]:
		await put(row, 0.0)
		box(row + Vector3(0, -0.3, -2.2), Vector3(2.4, spec[0] + 0.3, 2.4))
		await frames(4)
		a.in_move = Vector2(0, 1)
		await frames(10)
		a.in_jump = true
		var mantled := false
		for i in 70:
			await frames(1)
			if a.mantle_t >= 0.0:
				mantled = true
				a.in_move = Vector2.ZERO               # stop on top instead of running off the far side
		var on_top := absf(a.global_position.y - (row.y + spec[0])) < 0.35
		if spec[1]:
			check("mantles a " + spec[2], mantled and on_top, "feet %.2f m above the base" % (a.global_position.y - row.y))
		else:
			check("does not mantle a " + spec[2], not mantled and not on_top)
		if spec[0] == 1.5:
			await snap("move_01_mantle", PI * 0.75, -0.3)
		a.in_move = Vector2.ZERO
		boxes.pop_back().queue_free()
		row += Vector3(6, 0, 0)
	# ---------------------------------------------------------------- swimming in the lake
	a.add_item(Items.make("pistol", 1))
	a.select(a.find_item("pistol"))
	var lake: Vector3 = Vector3(T.lake.x, T.LAKE_LEVEL + 20.0, T.lake.y)
	var splashes: int = game.stats.get("splashes", 0)
	a.hp = 100.0
	await put(lake)
	var swam := false
	for i in 240:
		await frames(1)
		if a.state == Actor.State.SWIM:
			swam = true
			break
	check("falling into the lake starts swimming", swam)
	check("a fall into deep water does no damage", a.hp >= 100.0, "hp %.0f after a 20 m fall" % a.hp)
	check("entering the water makes a splash", game.stats.get("splashes", 0) > splashes)
	check("the weapon is put away", a.body.held_id == "")
	a.in_move = Vector2.ZERO
	await frames(60)
	var surf: float = T.water_surface(a.global_position.x, a.global_position.z)
	check("standing still treads water", hspeed() < 0.3 and absf(a.global_position.y - (surf - Actor.FLOAT_DEPTH)) < 0.25, "feet %.2f below the surface" % (surf - a.global_position.y))
	await snap("move_02_tread_water", 0.6, -0.25)
	var foam: int = game.stats.get("foam", 0)
	a.in_move = Vector2(0, 1)
	await frames(60)
	check("swimming moves at swim speed", absf(hspeed() - Actor.SWIM_SPEED) < 0.4, "%.1f m/s" % hspeed())
	check("swimming leaves foam", game.stats.get("foam", 0) > foam, "%d puffs" % (game.stats.get("foam", 0) - foam))
	await snap("move_03_swim", a.aim_yaw + 0.5, -0.3)
	# swim out towards dry land
	var shore := Vector2(T.lake.x + 40.0, T.lake.y + 40.0)
	for k in 16:
		var c: Vector2 = T.lake + Vector2(cos(TAU * k / 16.0), sin(TAU * k / 16.0)) * (T.lake_r + 14.0)
		if T.water_surface(c.x, c.y) < -999.0 and T.height(c.x, c.y) > 2.5:
			shore = c
			break
	var out := false
	for i in 1200:
		var to := Vector2(shore.x - a.global_position.x, shore.y - a.global_position.z)
		a.aim_yaw = atan2(-to.x, -to.y)
		await frames(1)
		if a.state == Actor.State.GROUND:
			out = true
			break
	check("walking out of shallow water ends swimming", out)
	check("the weapon comes back on land", a.body.held_id == "pistol", "holding '%s'" % a.body.held_id)
	a.in_move = Vector2.ZERO
	# ---------------------------------------------------------------- mantle out of the water onto a steep bank
	var wpos: Vector3 = Vector3(T.lake.x, T.LAKE_LEVEL - Actor.FLOAT_DEPTH, T.lake.y)
	await put(wpos + Vector3(0, 0.1, 0), 0.0)
	await frames(30)
	check("back in the water", a.state == Actor.State.SWIM)
	var bank_top: float = T.LAKE_LEVEL + 0.9
	box(Vector3(a.global_position.x, T.LAKE_LEVEL - 3.0, a.global_position.z - 2.0), Vector3(3.0, bank_top - (T.LAKE_LEVEL - 3.0), 2.6))
	await frames(4)
	a.in_move = Vector2(0, 1)
	await frames(12)
	a.in_jump = true
	await frames(60)
	check("mantles from the water onto a steep bank", a.state == Actor.State.GROUND and absf(a.global_position.y - bank_top) < 0.35, "feet %.2f, bank %.2f" % [a.global_position.y, bank_top])
	a.in_move = Vector2.ZERO
	boxes.pop_back().queue_free()
	# ---------------------------------------------------------------- the river
	var rp: Vector2 = T.river_point(0.5)
	await put(Vector3(rp.x, T.water_level(0.5) + 3.0, rp.y))
	await frames(90)
	check("the river is swimmable", a.state == Actor.State.SWIM)
	print("MOVETEST\n" + "\n".join(lines))
	print("MOVETEST %s  (%d checks, %d failed)" % ["OK" if fails == 0 else "FAILED", lines.size(), fails])
	get_tree().quit()
