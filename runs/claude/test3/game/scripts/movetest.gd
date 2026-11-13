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
	a.hurdle_t = -1.0
	a.in_tsprint = false
	a.tsprint_k = 0.0
	a.tsprint_block = false
	a.in_fire = false
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
	# ---------------------------------------------------------------- tactical sprint
	await put(base, PI)
	a.add_item(Items.make("pistol", 1))
	a.select(a.find_item("pistol"))
	var pis = a.item()
	a.in_move = Vector2(0, 1)
	a.in_sprint = true
	await frames(60)
	var run_v := hspeed()
	a.in_tsprint = true
	await frames(10)
	var early_v := hspeed()
	await frames(50)
	var ts_v := hspeed()
	check("tactical sprint is faster than the normal run", a.tsprint and ts_v > run_v + 1.2 and ts_v > Actor.SPRINT + 1.2, "%.1f m/s vs %.1f running" % [ts_v, run_v])
	check("tactical sprint winds up", early_v < ts_v - 0.1 and a.tsprint_k > 0.95, "%.1f m/s after 0.17 s" % early_v)
	var loaded0: int = pis.loaded
	a.in_fire = true
	a._combat(0.016)
	check("no firing during a tactical sprint", pis.loaded == loaded0 and a.fire_cd <= 0.0, "%d rounds" % pis.loaded)
	await frames(3)
	check("firing ends the tactical sprint", not a.tsprint and pis.loaded < loaded0)
	a.in_fire = false
	await frames(30)
	check("it stays off until Shift is released", not a.tsprint)
	a.in_tsprint = false
	await frames(3)
	a.in_tsprint = true
	await frames(40)
	check("releasing and pressing Shift starts it again", a.tsprint)
	a.in_crouch = true
	await frames(2)
	var ts_slide := 0.0
	var tt := 0
	while a.sliding and tt < 120:
		ts_slide = maxf(ts_slide, hspeed())
		await frames(1)
		tt += 1
	check("sliding out of a tactical sprint carries the extra speed", ts_slide > peak + 0.5, "peak %.1f m/s vs %.1f from a normal sprint" % [ts_slide, peak])
	a.in_tsprint = false
	a.in_move = Vector2.ZERO
	await frames(60)
	# ---------------------------------------------------------------- hurdle
	var hrow := ground(T.village.x - 17.0, T.village.y - 24.0)
	for spec in [[1.0, 0.5, true, "a 1 m crate"], [1.0, 2.6, false, "a 2.6 m thick block (mantles instead)"], [1.6, 0.5, false, "a 1.6 m wall (too high)"]]:
		await put(hrow + Vector3(0, 0, 8.0), 0.0)
		box(hrow + Vector3(0, -0.4, 2.0), Vector3(3.0, spec[0] + 0.4, spec[1]))
		await frames(4)
		a.in_move = Vector2(0, 1)
		a.in_sprint = true
		var before := 0.0
		var z_box := hrow.z + 2.0
		for i in 200:
			await frames(1)
			if a.global_position.z - z_box < spec[1] / 2.0 + 1.0:
				break
		before = hspeed()
		a.in_jump = true
		var vaulted := false
		var pk_y := a.global_position.y
		for i in 90:
			await frames(1)
			if a.hurdle_t >= 0.0:
				vaulted = true
				pk_y = maxf(pk_y, a.global_position.y)
				if spec[2] and a.hurdle_t > a.hurdle_dur * 0.4 and a.hurdle_t < a.hurdle_dur * 0.4 + 0.03:
					await snap("move_06_hurdle", PI * 0.7, -0.15)
			if vaulted and a.hurdle_t < 0.0 and i > 4:
				break
		await frames(6)
		var after := hspeed()
		var beyond: bool = a.global_position.z < z_box - spec[1] / 2.0 + 0.1
		if spec[2]:
			check("hurdles " + spec[3] + " and lands on the far side", vaulted and beyond and absf(a.global_position.y - hrow.y) < 0.4, "z %.2f vs box %.2f, feet %.2f above the start" % [a.global_position.z, z_box, a.global_position.y - hrow.y])
			check("a hurdle keeps its speed", after > before * 0.7, "%.1f m/s after, %.1f before" % [after, before])
			check("the vault clears the top", pk_y > hrow.y + spec[0] + 0.15, "peak %.2f m over a %.1f m box" % [pk_y - hrow.y, spec[0]])
		else:
			check("does not hurdle " + spec[3], not vaulted)
		a.in_move = Vector2.ZERO
		boxes.pop_back().queue_free()
		hrow += Vector3(7, 0, 0)
	# ---------------------------------------------------------------- mantle
	var row := ground(T.village.x - 24.0, T.village.y - 8.0)
	for spec in [[1.5, true, "1.5 m ledge"], [1.8, true, "1.8 m box"], [0.9, true, "0.9 m ledge"], [2.2, true, "2.2 m ledge"], [3.0, false, "3.0 m wall (too high)"]]:
		await put(row, 0.0)
		box(row + Vector3(0, -0.3, -2.2), Vector3(2.4, spec[0] + 0.3, 2.4))
		await frames(4)
		a.in_move = Vector2(0, 1)
		await frames(10)
		a.in_jump = true
		var mantled := false
		var mantle_exit := 0.0
		var was_m := false
		for i in 70:
			await frames(1)
			if was_m and a.mantle_t < 0.0:
				mantle_exit = hspeed()
				was_m = false
			if a.mantle_t >= 0.0:
				mantled = true
				was_m = true
				if spec[0] != 1.8:
					a.in_move = Vector2.ZERO           # stop on top instead of running off the far side
			if spec[0] == 1.8 and mantle_exit > 0.0:
				a.in_move = Vector2.ZERO
		var on_top := absf(a.global_position.y - (row.y + spec[0])) < 0.35
		if spec[1]:
			check("mantles a " + spec[2], mantled and on_top, "feet %.2f m above the base" % (a.global_position.y - row.y))
		else:
			check("does not mantle a " + spec[2], not mantled and not on_top)
		if spec[0] == 1.5:
			await snap("move_01_mantle", PI * 0.75, -0.3)
		if spec[0] == 1.8:
			check("a mantle keeps forward momentum", mantle_exit > 2.5, "%.1f m/s leaving the mantle" % mantle_exit)
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
	# ---------------------------------------------------------------- emotes
	await put(base, PI * 0.25)
	await frames(20)
	a.start_emote("samba")
	await frames(30)
	check("samba starts the Mixamo dance", a.emote == "samba" and a.body.clip == "x/Michelle_SambaDance", a.body.clip)
	check("the held item is put away while dancing", a.body.held_id == "")
	await frames(90)
	await snap("move_04_emote_samba", PI * 1.25, -0.15)
	a.in_move = Vector2(0, 1)
	await frames(3)
	check("moving ends the emote", a.emote == "")
	a.in_move = Vector2.ZERO
	await frames(20)
	a.start_emote("nod")
	await frames(int(Character.EMOTES.nod.length * 60.0) + 15)
	check("a one-shot emote ends by itself", a.emote == "")
	a.start_emote("wave")
	await frames(40)
	check("the wave uses the arm override", a.emote == "wave" and a.body.pose.arms_w > 0.5)
	a.stop_emote()
	var ctl = game.controller
	var picks := []
	for v in [Vector2(0, -60), Vector2(60, 0), Vector2(0, 60), Vector2(-60, 0), Vector2(5, 5)]:
		ctl.wheel_vec = v
		picks.append(ctl.wheel_pick())
	check("the wheel picks up, right, down, left and nothing at the centre", picks == [0, 1, 2, 3, -1], str(picks))
	ctl.wheel_open = true
	ctl.wheel_vec = Vector2(70, -10)
	await snap("move_05_emote_wheel", PI * 1.25, -0.15)
	ctl.wheel_open = false
	print("MOVETEST\n" + "\n".join(lines))
	print("MOVETEST %s  (%d checks, %d failed)" % ["OK" if fails == 0 else "FAILED", lines.size(), fails])
	get_tree().quit()
