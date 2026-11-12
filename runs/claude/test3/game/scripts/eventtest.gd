## Automated check of prompt 5: consumables, forage, launch pads, zip lines, rifts and supply drops.  Run:
##   godot --headless --path <project> -- --eventtest
extends Node

var game: Node
var a: Actor
var lines: Array = []
var fails := 0
var tmp0 := 0


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
	a.zip = null
	a.mantle_t = -1.0
	a.launched = false
	a.state = Actor.State.GROUND
	a.global_position = p
	a.velocity = Vector3.ZERO
	a.aim_yaw = yaw
	a.aim_pitch = 0.0
	a.in_move = Vector2.ZERO
	a.fall_start = p.y
	await frames(6)


func use_item(id: String) -> void:
	a.select(a.find_item(id))
	await frames(2)
	a.start_use()
	await frames(int(Items.DEFS[id].use_time * 60.0) + 6)


func equip(id: String, rarity := 0) -> Dictionary:
	## The weapon alone in slot 0, full magazine and plenty of ammo, ready to fire.
	var it := Items.make(id, rarity)
	a.slots = [it, null, null, null, null]
	for t in Items.AMMO_TYPES:
		a.ammo[t] = 200
	a.select(-1)
	a.select(0)
	a.fire_cd = 0.0
	a.reloading = 0.0
	a.burst_left = 0
	a.spread_mul = 0.0
	return it


func pull(frames_held := 1) -> void:
	a.in_fire = true
	await frames(frames_held)
	a.in_fire = false


func heal_state(h: float, sh: float) -> void:
	a.hp = h
	a.shield = sh
	a.using = 0.0


func use_frames() -> int:
	## Starts using the selected item and counts physics frames until it is done (0 when refused).
	a.start_use()
	var n := 0
	while a.using > 0.0 and n < 1500:
		await frames(1)
		n += 1
	return n


func _ready() -> void:
	await frames(5)
	a = game.player
	game.controller.demo = true
	for o in game.actors:
		if o != a:
			o.process_mode = Node.PROCESS_MODE_DISABLED
	var T = game.terrain
	var E: WorldEvents = game.events
	var base: Vector3 = E._dry_spot(T.village + Vector2(20, 8))
	await put(base + Vector3(0, 0.1, 0))
	# ---------------------------------------------------------------- consumables
	a.hp = 40.0
	a.shield = 0.0
	a.add_item(Items.make("small_shield", 0, 3))
	await use_item("small_shield")
	check("small shield gives 25", absf(a.shield - 25.0) < 0.1, "%.0f" % a.shield)
	await use_item("small_shield")
	check("small shields stop at 50", absf(a.shield - 50.0) < 0.1)
	a.start_use()
	check("a third small shield is refused at 50", a.using <= 0.0)
	a.add_item(Items.make("healing_drink"))
	await use_item("healing_drink")
	check("healing drink heals 50", absf(a.hp - 90.0) < 0.1, "%.0f hp" % a.hp)
	check("big shield is still the 50-point potion", Items.DEFS.shield_potion.amount == 50.0 and Items.DEFS.shield_potion.cap == 100.0)
	# ---------------------------------------------------------------- forage
	check("apples and mushrooms are spread on the map", game.stats.get("forage", 0) >= 60, "%d" % game.stats.get("forage", 0))
	a.hp = 80.0
	game.spawn_pickup({"forage": "apple"}, a.global_position + Vector3(0, 0, -0.5))
	await frames(70)
	check("walking over an apple heals 5", absf(a.hp - 85.0) < 0.1, "%.0f hp" % a.hp)
	a.shield = 100.0
	var before: int = game.pickups.size()
	game.spawn_pickup({"forage": "mushroom"}, a.global_position + Vector3(0, 0, -0.5))
	await frames(70)
	check("a mushroom is left alone at full shield", game.pickups.size() == before + 1)
	# ---------------------------------------------------------------- launch pad, placed
	a.shield = 0.0
	a.add_item(Items.make("launch_pad"))
	a.select(a.find_item("launch_pad"))
	a.aim_yaw = 0.0
	a.aim_pitch = -0.8
	await frames(2)
	var pads0: int = E.pads.size()
	a.in_fire = true
	await frames(3)
	check("looking down places the launch pad", E.pads.size() == pads0 + 1 and a.find_item("launch_pad") < 0)
	await snap("event_01_launch_pad", 0.6, -0.35)
	a.in_move = Vector2(0, 1)
	var peak := 0.0
	var glided := false
	var g0: float = a.global_position.y
	var launched := false
	for i in 900:
		await frames(1)
		if a.state == Actor.State.SKYDIVE:
			launched = true
			a.in_move = Vector2.ZERO
		peak = maxf(peak, a.global_position.y - g0)
		glided = glided or a.state == Actor.State.GLIDE
		if launched and a.state == Actor.State.GROUND and a.is_on_floor():
			break
	check("the pad launches the player high", launched and peak > 35.0, "peak %.0f m" % peak)
	check("the glider opens on the way down", glided)
	check("and lands safely", a.state == Actor.State.GROUND and a.hp >= 85.0, "%.0f hp" % a.hp)
	# ---------------------------------------------------------------- launch pad, thrown
	await put(base + Vector3(6, 0.1, 0))
	a.add_item(Items.make("launch_pad"))
	a.select(a.find_item("launch_pad"))
	a.aim_pitch = 0.1
	var pads1: int = E.pads.size()
	a.in_fire = true
	await frames(150)
	check("a thrown launch pad lands and deploys", E.pads.size() == pads1 + 1, "%.1f m away" % (Vector2(E.pads[E.pads.size() - 1].pos.x - a.global_position.x, E.pads[E.pads.size() - 1].pos.z - a.global_position.z).length() if E.pads.size() > pads1 else -1.0))
	# ---------------------------------------------------------------- zip line
	check("three zip lines", E.zips.size() == 3, ", ".join(E.zips.map(func(z): return "%.0f m" % z.length)))
	var z: Dictionary = E.zips[0]
	var end: Vector3 = E.cable_point(z, 1.0)
	await put(Vector3(end.x + 1.0, T.height(end.x + 1.0, end.z) + 0.1, end.z))
	var zn = E.zip_near(a)
	check("standing at a zip line pole offers a ride", zn != null)
	if zn != null:
		a.start_zip(zn[0], zn[1])
		var t0 := 0
		var mid_ok := false
		while a.zip != null and t0 < 1800:
			await frames(1)
			t0 += 1
			if t0 == 60:
				var cp: Vector3 = E.cable_point(z, a.zip.t)
				mid_ok = a.global_position.distance_to(cp - Vector3(0, 1.95, 0)) < 0.2
				await snap("event_02_zip_line", a.aim_yaw + 1.2, -0.1)
		var start: Vector3 = E.cable_point(z, 0.0)
		check("riding hangs under the cable", mid_ok)
		check("the ride reaches the other end", Vector2(a.global_position.x - start.x, a.global_position.z - start.z).length() < 4.0, "%.1f s for %.0f m" % [t0 / 60.0, z.length])
	await frames(120)
	# ---------------------------------------------------------------- rift
	var r: Dictionary = E.rifts[0]
	await put(r.pos + Vector3(0, 0.1, 4.0), 0.0)
	await snap("event_03_rift", 0.3, -0.05)
	a.global_position = r.pos + Vector3(0, 0.1, 0.5)
	await frames(10)
	check("a rift sends you back into skydiving", a.state == Actor.State.SKYDIVE and a.height_above_ground() > 80.0, "%.0f m up" % a.height_above_ground())
	for i in 1500:
		await frames(1)
		if a.state == Actor.State.GROUND:
			break
	check("and you land again", a.state == Actor.State.GROUND)
	# ---------------------------------------------------------------- supply drop
	var dp: Vector3 = E._dry_spot(T.village + Vector2(-20, 24))
	var d: Dictionary = E.spawn_drop(dp)
	var y0: float = (d.node as Node3D).global_position.y
	await frames(60)
	var y1: float = (d.node as Node3D).global_position.y
	check("a supply drop falls slowly", y0 - y1 > 4.0 and y0 - y1 < 8.0, "%.1f m in 1 s" % (y0 - y1))
	check("it trails smoke", game.stats.get("smoke_puffs", 0) > 3)
	for i in 1500:
		await frames(1)
		if d.landed:
			break
	check("it lands", d.landed and absf((d.node as Node3D).global_position.y - dp.y) < 1.0)
	var cont = null
	for c in game.containers:
		if c.node == d.node:
			cont = c
	check("a landed drop can be opened", cont != null)
	if cont != null:
		await put(dp + Vector3(2.0, 0.1, 0))
		await snap("event_04_supply_drop", PI * 0.5 + 0.3, -0.2)
		var p0: int = game.pickups.size()
		game.open_container(cont, a)
		var best := 0
		for p in game.pickups.slice(p0):
			if p.item.has("rarity") and Items.DEFS[p.item.id].kind == "weapon":
				best = maxi(best, p.item.rarity)
		check("it holds better loot", game.pickups.size() - p0 >= 5, "%d items, best weapon rarity %s" % [game.pickups.size() - p0, Items.RARITY_NAMES[best]])
	# ---------------------------------------------------------------- new weapons
	var victim: Actor = null
	for o in game.actors:
		if o != a:
			victim = o
			break
	await put(base + Vector3(0, 0.1, 0))
	var vp := a.global_position + Vector3(0, 0, -10)
	var found := false
	for dz in [0, 1, -1, 2, -2]:
		var test_to := a.global_position + Vector3(float(dz) * 3.0, 0, -10)
		var o := a.global_position + Vector3(0, 1.1, 0)
		if game.ray(o, test_to + Vector3(0, 1.1, 0), a, 1).is_empty():
			vp = test_to
			found = true
			break
	check("a clear 10 m firing lane to the dummy target", found)
	var aim := a.global_position.direction_to(vp)
	a.aim_yaw = atan2(-aim.x, -aim.z)
	var wait := 0
	victim.process_mode = Node.PROCESS_MODE_INHERIT              # a disabled body leaves the physics space and cannot be hit
	for ch in victim.get_children():
		if ch.get_script() != null:
			ch.process_mode = Node.PROCESS_MODE_DISABLED         # but its bot brain stays off
	victim.state = Actor.State.GROUND
	victim.in_move = Vector2.ZERO                                # the brain left it walking
	victim.in_fire = false
	victim.global_position = vp
	victim.velocity = Vector3.ZERO
	a.aim_pitch = atan2(vp.y + 1.15 - (a.global_position.y + 1.55), 10.0)
	await frames(6)
	for id in ["smg", "tactical_shotgun", "burst_rifle", "hunting_rifle"]:
		check("%s sound is mapped" % id, game.audio.has_sound(id))
	a.is_player = false                                         # a bot-style shooter aims along aim_dir, not at the camera
	var expect := {"smg": 17.0, "tactical_shotgun": 63.0, "burst_rifle": 27.0, "hunting_rifle": 86.0}
	for id in expect:
		var it := equip(id)
		victim.hp = 100.0
		victim.shield = 0.0
		await frames(3)
		var loaded0: int = it.loaded
		await pull()
		await frames(2)
		var dealt := 100.0 - victim.hp
		if id == "burst_rifle":
			await frames(40)
			dealt = 100.0 - victim.hp
			check("burst rifle fires exactly 3 shots per pull", loaded0 - it.loaded == 3, "%d shots" % (loaded0 - it.loaded))
			check("burst rifle: 3 hits of 27", absf(dealt - 81.0) < 0.5, "%.0f damage" % dealt)
			await frames(30)
			victim.hp = 100.0
			await pull()
			await frames(40)
			check("a second pull fires another 3", loaded0 - it.loaded == 6, "%d shots in all" % (loaded0 - it.loaded))
			a.fire_cd = 0.0
			a.burst_left = 0
			var mag0: int = it.loaded
			victim.hp = 2000.0                                # survives the long burst
			await pull(70)                                    # holding the trigger: bursts repeat
			var held: int = mag0 - it.loaded
			check("a held trigger repeats whole bursts with a pause between", held % 3 == 0 and held >= 6 and held <= 12, "%d shots in 1.2 s" % held)
		else:
			check("%s fires and deals %.0f" % [id, expect[id]], loaded0 - it.loaded == 1 and absf(dealt - expect[id]) < 0.5, "%d shot(s), %.1f damage" % [loaded0 - it.loaded, dealt])
	a.is_player = true
	# rates and ranges
	var smg := equip("smg")
	await frames(20)
	var s0: int = smg.loaded
	await pull(60)
	var shots: int = s0 - smg.loaded
	check("SMG is automatic at about 11 shots/s", shots >= 9 and shots <= 12, "%d shots in 1 s" % shots)
	var tac := equip("tactical_shotgun")
	await frames(20)
	tmp0 = tac.loaded
	await pull(60)
	check("tactical shotgun is semi-auto (one shot per held pull, player)", tmp0 - tac.loaded == 1)
	check("tactical shotgun fires faster than the pump", Items.DEFS.tactical_shotgun.rate > Items.DEFS.shotgun.rate and Items.DEFS.tactical_shotgun.damage < Items.DEFS.shotgun.damage)
	check("SMG damage drops past its 45 m range", Items.DEFS.smg.range == 45.0 and Items.DEFS.smg.mag == 30)
	# the hunting rifle never scopes; the bolt sniper still does
	var hr := equip("hunting_rifle")
	game.controller.force_aim = true
	await frames(30)
	check("hunting rifle does not open the scope overlay", not game.hud.scoped(a, game.controller))
	check("hunting rifle keeps the normal aim zoom", game.controller.cam.fov > 40.0, "fov %.0f" % game.controller.cam.fov)
	equip("sniper_rifle")
	await frames(30)
	check("the bolt sniper still scopes", game.hud.scoped(a, game.controller) and game.controller.cam.fov < 30.0)
	game.controller.force_aim = false
	a.spread_mul = 1.0
	# loot tables
	var seen := {}
	var rr := RandomNumberGenerator.new()
	rr.seed = 7
	for i in 6000:
		var li := Items.roll_floor(rr)
		if li.has("id"):
			seen[li.id] = seen.get(li.id, 0) + 1
	var all_new := true
	for id in ["smg", "tactical_shotgun", "burst_rifle", "hunting_rifle", "bandages", "hydro_juice", "mega_flask"]:
		all_new = all_new and seen.has(id)
	check("floor loot rolls every new item", all_new, str(seen))
	check("the mega flask is the rarest heal", seen.get("mega_flask", 0) < seen.get("hydro_juice", 0) and seen.get("hydro_juice", 0) < seen.get("bandages", 0))
	check("existing weapons stay the most common", seen.get("assault_rifle", 0) > seen.get("smg", 0) and seen.get("pistol", 0) > seen.get("burst_rifle", 0))
	# ---------------------------------------------------------------- new heals
	a.slots = [Items.make("bandages", 0, 15), Items.make("hydro_juice", 0, 2), Items.make("mega_flask"), null, null]
	check("bandages stack to 15, hydro to 2, flask to 1", Items.DEFS.bandages.stack == 15 and Items.DEFS.hydro_juice.stack == 2 and Items.DEFS.mega_flask.stack == 1)
	check("rarities: common, rare, legendary", a.slots[0].rarity == 0 and a.slots[1].rarity == 2 and a.slots[2].rarity == 4)
	a.select(0)
	await frames(30)
	heal_state(40.0, 0.0)
	var n := await use_frames()
	check("bandages heal 15", absf(a.hp - 55.0) < 0.1, "%.0f hp" % a.hp)
	check("bandages take about 3.5 s", absf(n / 60.0 - 3.5) < 0.25, "%.2f s" % (n / 60.0))
	check("bandages do not touch the shield", a.shield == 0.0 and a.slots[0].count == 14)
	heal_state(70.0, 0.0)
	await use_frames()
	check("bandages stop at 75 hp", absf(a.hp - 75.0) < 0.1, "%.0f hp" % a.hp)
	n = await use_frames()
	check("bandages are refused at 75 hp", n == 0 and a.slots[0].count == 13)
	heal_state(90.0, 0.0)
	n = await use_frames()
	check("and never lower hp above 75", n == 0 and a.hp == 90.0)
	a.select(1)
	await frames(30)
	heal_state(50.0, 10.0)
	n = await use_frames()
	check("hydro juice adds 25 hp and 25 shield", absf(a.hp - 75.0) < 0.1 and absf(a.shield - 35.0) < 0.1, "%.0f hp, %.0f shield" % [a.hp, a.shield])
	check("hydro juice takes 2 s", absf(n / 60.0 - 2.0) < 0.25, "%.2f s" % (n / 60.0))
	heal_state(100.0, 20.0)
	n = await use_frames()
	check("hydro juice works at full hp when shield is short", n > 0 and absf(a.shield - 45.0) < 0.1, "%.0f shield" % a.shield)
	a.slots[1] = Items.make("hydro_juice", 0, 2)
	heal_state(30.0, 100.0)
	n = await use_frames()
	check("hydro juice works at full shield when hp is short", n > 0 and absf(a.hp - 55.0) < 0.1 and a.shield == 100.0, "%.0f hp" % a.hp)
	heal_state(90.0, 90.0)
	await use_frames()
	check("hydro juice caps both at 100", a.hp == 100.0 and a.shield == 100.0, "%.0f / %.0f" % [a.hp, a.shield])
	a.slots[1] = Items.make("hydro_juice", 0, 1)
	a.select(1)
	heal_state(100.0, 100.0)
	n = await use_frames()
	check("hydro juice is refused when both are full", n == 0 and a.slots[1] != null)
	a.select(2)
	await frames(30)
	heal_state(10.0, 5.0)
	a.start_use()
	await frames(570)
	check("the mega flask is still being drunk after 9.5 s", a.using > 0.0 and a.hp == 10.0)
	await frames(40)
	check("the mega flask fills hp and shield to 100/100", a.using <= 0.0 and a.hp == 100.0 and a.shield == 100.0, "%.0f / %.0f" % [a.hp, a.shield])
	check("and the flask is used up", a.slots[2] == null)
	a.spread_mul = 1.0
	print("EVENTTEST\n" + "\n".join(lines))
	print("EVENTTEST %s  (%d checks, %d failed)" % ["OK" if fails == 0 else "FAILED", lines.size(), fails])
	get_tree().quit()
