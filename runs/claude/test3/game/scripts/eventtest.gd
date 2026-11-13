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
	check("eight zip lines and ten rifts", E.zips.size() == 8 and E.rifts.size() == 10, ", ".join(E.zips.map(func(z): return "%.0f m" % z.length)) + "; rifts %d" % E.rifts.size())
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
	# ---------------------------------------------------------------- mythic weapons
	check("mythic is rarity 5: a sixth rarity", Items.RARITY_NAMES.size() == 6 and Items.RARITY_NAMES[5] == "Mythic" and Items.RARITY_COLORS.size() == 6 and Items.RARITY_COLORS[5] != Items.RARITY_COLORS[4])
	var mythic_ok := true
	for id in Items.MYTHIC_IDS:
		var mi := Items.make(id, 2)
		mythic_ok = mythic_ok and mi.rarity == 5 and Items.DEFS[id].get("mythic", false) and Items.label(mi).begins_with("Mythic ")
	check("Items.make gives every mythic rarity 5 whatever is asked", mythic_ok)
	check("the four mythics are mapped to sounds and have models", game.audio.has_sound("web_shooters") and game.audio.has_sound("ravage_grasp") and game.audio.has_sound("charge_shotgun") and game.audio.has_sound("shockwave_launcher") and ResourceLoader.exists("res://assets/web_shooters.glb") and ResourceLoader.exists("res://assets/shockwave_launcher.glb"))
	var m_seen := 0
	var rr2 := RandomNumberGenerator.new()
	rr2.seed = 99
	for i in 5000:
		var li2 := Items.roll_floor(rr2)
		if li2.has("id") and Items.DEFS[li2.id].get("mythic", false):
			m_seen += 1
		var lw := Items.roll_weapon(rr2)
		if Items.DEFS[lw.id].get("mythic", false) or lw.rarity > 4:
			m_seen += 1
	check("mythics never come from roll_floor or roll_weapon (5000 rolls)", m_seen == 0, "%d mythics" % m_seen)
	var bench0: Dictionary = game.events.benches[1]
	await put(bench0.pos + Vector3(1.6, 0.2, 0))
	a.slots = [Items.make("charge_shotgun"), null, null, null, null]
	a.select(0)
	a.gold = 999
	check("an upgrade bench refuses a mythic", game.events.bench_near(a) != null and not game.events.upgrade(a) and a.item().rarity == 5 and a.gold == 999)
	check("mythic damage ignores rarity bonuses", absf(Items.damage(a.item()) - Items.DEFS.charge_shotgun.damage) < 0.01)
	var mp0: Vector3 = E._dry_spot(T.village + Vector2(28, -30))
	await put(mp0 + Vector3(0, 0.1, 0))
	var wh: float = a.hp
	# --- web shooters
	equip("web_shooters")
	check("web shooters never run dry: loaded stays and the HUD sees infinite ammo", Items.infinite_ammo(a.item()) and a.item().loaded == 1)
	var w_start := a.global_position
	var w_end := mp0 + Vector3(0, 34.0, -28.0)
	check("web_swing_to starts a swing", a.web_swing_to(w_end) and a.is_swinging())
	var w_max := 0.0
	var w_released := false
	var w_airborne := false
	for i in 700:
		await frames(1)
		var hd := Vector2(a.global_position.x - w_start.x, a.global_position.z - w_start.z).length()
		w_max = maxf(w_max, hd)
		if not w_released and a.is_swinging() and a.web_t > 0.9 and a.velocity.y > 2.0 and a.velocity.length() > 8.0:
			a.web_release()
			w_released = true
		if w_released and not a.is_on_floor():
			w_airborne = true
		if w_released and w_airborne and a.web_state == 0 and a.is_on_floor():
			break
	check("the web swing carries the player at least 15 m", w_max >= 15.0, "%.1f m" % w_max)
	check("and they land without fall damage after the release", w_released and a.web_state == 0 and a.hp >= wh - 0.01, "hp %.0f of %.0f, released %s" % [a.hp, wh, w_released])
	await put(mp0 + Vector3(0, 0.1, 0))
	a.is_player = false
	a.aim_pitch = -0.5
	equip("web_shooters")
	a.fire_cd = 0.0
	a.in_fire = true
	await frames(4)
	var held_swing: bool = a.is_swinging()
	await frames(30)
	var still_swinging: bool = a.is_swinging()
	a.in_fire = false
	await frames(3)
	check("firing the web at the ground ahead swings you; the swing lasts while fire is held, ends on release", held_swing and still_swinging and not a.is_swinging(), "%s %s %s" % [held_swing, still_swinging, a.is_swinging()])
	check("a short cooldown follows the release", a.fire_cd > 0.0 and a.fire_cd <= 0.4)
	await frames(240)
	a.web_state = 0
	# --- Ravage's Grasp
	var gp: Vector3 = base + Vector3(0, 0.1, 0)
	await put(gp)
	equip("ravage_grasp")
	var gvp := gp + Vector3(0, 0, -14)
	victim.process_mode = Node.PROCESS_MODE_INHERIT
	victim.state = Actor.State.GROUND
	victim.global_position = gvp
	victim.velocity = Vector3.ZERO
	victim.hp = 100.0
	victim.shield = 40.0
	victim.stun_t = 0.0
	a.aim_pitch = 0.0
	await frames(8)
	var gh0: float = victim.hp + victim.shield
	await pull(2)
	await frames(16)
	check("the grasp yanks an enemy towards you and stuns them", victim.global_position.distance_to(a.global_position) < 6.0 and victim.stun_t > 0.0, "%.1f m, stun %.2f" % [victim.global_position.distance_to(a.global_position), victim.stun_t])
	await frames(34)
	var gdist: float = victim.global_position.distance_to(a.global_position)
	var gdealt: float = gh0 - (victim.hp + victim.shield)
	check("the enemy ends up within 3 m", gdist < 3.0, "%.1f m" % gdist)
	check("and takes about 60 damage, shield first", absf(gdealt - 60.0) < 1.0 and victim.shield == 0.0 and victim.hp > 75.0, "%.0f damage, shield %.0f hp %.0f" % [gdealt, victim.shield, victim.hp])
	check("the grasp has a 3 s cooldown", a.fire_cd > 1.5 and Items.DEFS.ravage_grasp.cooldown == 3.0, "%.1f" % a.fire_cd)
	# a stunned actor cannot move
	victim.stun_t = 0.6
	victim.in_move = Vector2(0, 1)
	var sp0 := victim.global_position
	await frames(20)
	check("a stunned actor cannot walk", victim.global_position.distance_to(sp0) < 0.3, "%.2f m" % victim.global_position.distance_to(sp0))
	victim.in_move = Vector2.ZERO
	victim.stun_t = 0.0
	# grapple to a wall
	var S0: Structures = game.structures
	await put(mp0 + Vector3(0, 0.1, 6))
	a.mats = {"wood": 0, "brick": 0, "metal": 40}
	a.build_mat = "metal"
	a.set_build("wall")
	var wall_ok: bool = S0.place(a)
	a.set_build("wall")
	var wall = null
	for e in S0.pieces.values():
		wall = e
	check("a wall piece is built for the grasp and shockwave tests", wall_ok and wall != null)
	if wall != null:
		await frames(300)
		var wp: Vector3 = wall.pos
		var from_p := Vector3(wp.x, mp0.y, wp.z) + Vector3(0, 0.1, 13)
		from_p.y = T.height(from_p.x, from_p.z) + 0.1
		await put(from_p)
		a.aim_yaw = 0.0
		a.aim_pitch = atan2(wp.y - (from_p.y + 1.55), 13.0)
		equip("ravage_grasp")
		var d0 := Vector2(a.global_position.x - wp.x, a.global_position.z - wp.z).length()
		await pull(2)
		await frames(75)
		var d1 := Vector2(a.global_position.x - wp.x, a.global_position.z - wp.z).length()
		check("the grasp on a wall pulls you towards it", d1 < d0 - 7.0 and a.grasp_pull == false, "%.1f m -> %.1f m" % [d0, d1])
		# --- shockwave launcher, burst on a structure and on a bystander
		await put(from_p + Vector3(0, 0, 5))
		var burst_at := Vector3(wp.x, wp.y, wp.z + 2.0)
		victim.global_position = burst_at + Vector3(3.0, -wp.y + T.height(burst_at.x + 3.0, burst_at.z) + 0.1, 0)
		victim.state = Actor.State.GROUND
		victim.velocity = Vector3.ZERO
		victim.hp = 100.0
		victim.shield = 0.0
		victim.stun_t = 0.0
		await frames(10)
		var vy0: float = victim.global_position.y
		var wall_hp0: float = wall.hp
		game.shock_burst(burst_at, {"owner": a, "damage": 15.0, "radius": 7.5, "knock": 34.0, "struct": 400.0})
		await frames(1)
		check("the shockwave throws a nearby player up like a launch pad", victim.launched and victim.state == Actor.State.SKYDIVE and victim.velocity.y > 12.0, "vy %.1f" % victim.velocity.y)
		var vpeak := 0.0
		var vhd := 0.0
		for i in 120:
			await frames(1)
			vpeak = maxf(vpeak, victim.global_position.y - vy0)
			vhd = maxf(vhd, Vector2(victim.global_position.x - burst_at.x, victim.global_position.z - burst_at.z).length())
		check("and far up and away", vpeak > 8.0 and vhd > 6.0, "up %.1f m, out %.1f m" % [vpeak, vhd])
		check("the shockwave does small damage to players", victim.hp < 100.0 and victim.hp > 82.0, "%.1f hp" % victim.hp)
		check("and heavy damage to built structures", wall.dead or wall.hp < wall_hp0 - 100.0, "%.0f -> %.0f hp" % [wall_hp0, wall.hp])
		for i in 400:
			await frames(1)
			if victim.state == Actor.State.GROUND and victim.is_on_floor():
				break
		check("no fall damage from the knock", victim.hp > 82.0, "%.1f hp" % victim.hp)
		# a real orb: fired from the launcher it arcs, bursts and also launches the shooter standing close to the wall
		await put(Vector3(wp.x, 0, wp.z) + Vector3(0, T.height(wp.x, wp.z + 4.0) + 0.1, 4.0))
		var sw := equip("shockwave_launcher")
		a.aim_yaw = 0.0
		a.aim_pitch = 0.05
		a.fire_cd = 0.0
		var sw0: int = sw.loaded
		var orbs0: int = game.projectiles.size()
		await pull(2)
		check("the launcher fires a slow orb and uses one rocket-type round (mag 4)", sw0 - sw.loaded == 1 and game.projectiles.size() == orbs0 + 1 and sw.loaded == 3 and Items.DEFS.shockwave_launcher.mag == 4, "loaded %d" % sw.loaded)
		var orb_ok := false
		for i in 200:
			await frames(1)
			if a.launched:
				orb_ok = true
				break
		check("a burst knocks the shooter up too (no self damage)", orb_ok and a.hp >= wh - 0.01, "hp %.0f" % a.hp)
		for i in 500:
			await frames(1)
			if a.state == Actor.State.GROUND and a.is_on_floor():
				break
	# --- charge shotgun
	a.is_player = false
	await put(gp)
	var cs := equip("charge_shotgun")
	victim.global_position = gp + Vector3(0, 0, -7)
	victim.state = Actor.State.GROUND
	victim.velocity = Vector3.ZERO
	victim.stun_t = 0.0
	a.aim_pitch = 0.0
	await frames(8)
	victim.hp = 1000.0
	victim.shield = 0.0
	a.fire_cd = 0.0
	a.in_fire = true
	await frames(4)
	a.in_fire = false
	await frames(4)
	var dmg_tap: float = 1000.0 - victim.hp
	check("an uncharged shot fires on release and is weak", dmg_tap > 0.0 and cs.loaded == 5, "%.0f damage" % dmg_tap)
	await frames(60)
	victim.hp = 1000.0
	a.fire_cd = 0.0
	a.in_fire = true
	await frames(30)
	var half_charge: float = a.charge
	await frames(40)
	var full_charge: float = a.charge
	check("holding fire charges 0 to 1 in about a second", half_charge > 0.3 and half_charge < 0.7 and full_charge >= 0.99, "%.2f then %.2f" % [half_charge, full_charge])
	check("nothing fires while the trigger is held", cs.loaded == 5)
	a.in_fire = false
	await frames(4)
	var dmg_full: float = 1000.0 - victim.hp
	check("a full charge deals about 2x the damage of the base shot and more than a tap", dmg_full > dmg_tap * 2.0 and absf(dmg_full - 2.0 * 90.0) < 5.0, "%.0f vs %.0f" % [dmg_full, dmg_tap])
	check("a full charge is tighter than an uncharged shot", Items.DEFS.charge_shotgun.charge_spread < Items.DEFS.charge_shotgun.spread * 0.5 and a.charge == 0.0)
	check("the charge shotgun uses shells, mag 6", Items.DEFS.charge_shotgun.ammo == "shells" and Items.DEFS.charge_shotgun.mag == 6 and cs.loaded == 4)
	a.is_player = true
	a.spread_mul = 1.0
	a.select(-1)
	await put(base + Vector3(0, 0.1, 0))
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
	# ---------------------------------------------------------------- spare ammo and the automatic build material
	for i in Items.SLOTS:
		a.slots[i] = null
	a.active = -1
	a.ammo["heavy"] = 0
	a.add_item(Items.make("hunting_rifle"))
	check("a fresh hunting rifle brings spare heavy ammo", int(a.ammo.heavy) >= 8, "%d" % a.ammo.heavy)
	var hr_i := a.find_item("hunting_rifle")
	var fresh_rifle: Dictionary = a.slots[hr_i]
	var before_heavy := int(a.ammo.heavy)
	a.drop_slot(hr_i)
	for pk in game.pickups.duplicate():
		if pk.item == fresh_rifle:
			game.remove_pickup(pk)
	a.add_item(fresh_rifle)
	check("picking the same rifle up again brings no more", int(a.ammo.heavy) == before_heavy)
	await put(game.events._dry_spot(game.terrain.village + Vector2(26, 30)) + Vector3(0, 0.1, 0))
	a.mats = {"wood": 0, "brick": 0, "metal": 30}
	a.build_mat = "wood"
	a.set_build("wall")
	check("build mode starts on a material you have", a.build_mat == "metal", a.build_mat)
	a.build_mat = "wood"
	var placed: bool = game.structures.place(a)
	check("building with an empty material uses one you have", placed and int(a.mats.metal) == 20, "metal %d" % a.mats.metal)
	a.set_build("wall")
	# ---------------------------------------------------------------- doorway step and a house coming down
	var S: Structures = game.structures
	var shell = null
	for e in S.by_body.values():
		if e.name == "house_shell" and not e.dead and (shell == null or Vector2(e.pos.x, e.pos.z).distance_to(game.terrain.village) < Vector2(shell.pos.x, shell.pos.z).distance_to(game.terrain.village)):
			shell = e
	var house: Node3D = (shell.node as Node3D).get_parent()
	var door: Node3D = house.find_child("house_door", true, false)
	var out_dir: Vector3 = (door.global_position - house.global_position)
	out_dir.y = 0
	out_dir = out_dir.normalized()
	var start: Vector3 = door.global_position + out_dir * 2.6
	start.y = game.terrain.height(start.x, start.z) + 0.1
	await put(start, atan2(out_dir.x, out_dir.z))                 # facing the door
	a.in_move = Vector2(0, 1)
	await frames(90)
	a.in_move = Vector2.ZERO
	var d_in: float = Vector2(a.global_position.x - house.global_position.x, a.global_position.z - house.global_position.z).length()
	check("walking at the front door takes you inside (over the sill)", d_in < house.global_position.distance_to(start) - 2.5, "%.1f m from the middle" % d_in)
	# and out again, from inside every house on the island
	var stuck: Array = []
	for h in game.island.find_children("House_*", "Node3D", true, false):
		var hd: MeshInstance3D = h.find_child("house_door", true, false)
		if hd == null:
			continue
		# the door node sits at its hinge: aim at the middle of the leaf as it hangs closed
		var yaw0: float = hd.rotation.y
		for dd in game.doors:
			if dd.node == hd:
				yaw0 = dd.yaw
		var mid: Vector3 = h.global_transform * (Transform3D(Basis(Vector3.UP, yaw0), hd.position) * hd.get_aabb().get_center())
		var o: Vector3 = mid - h.global_position
		o.y = 0
		o = o.normalized()
		var inside: Vector3 = mid - o * 2.5
		var fl: Dictionary = game.ray(inside + Vector3(0, 1.5, 0), inside - Vector3(0, 3, 0), null, 1)
		await put((fl.position if not fl.is_empty() else inside) + Vector3(0, 0.1, 0), atan2(-o.x, -o.z))
		a.in_move = Vector2(0, 1)
		await frames(150)
		a.in_move = Vector2.ZERO
		if (a.global_position - mid).dot(o) < 1.0:
			var lp: Vector3 = h.global_transform.affine_inverse() * a.global_position
			var ls: Vector3 = h.global_transform.affine_inverse() * inside
			var cols := []
			a.in_move = Vector2(0, 1)
			await frames(2)
			for ci in a.get_slide_collision_count():
				var kc := a.get_slide_collision(ci)
				var co = kc.get_collider()
				var ln: Vector3 = h.global_transform.basis.inverse() * kc.get_normal()
				cols.append("%s n%s at%s" % [co.get_parent().name if co else "?", ln.snapped(Vector3(0.1, 0.1, 0.1)), (h.global_transform.affine_inverse() * kc.get_position()).snapped(Vector3(0.1, 0.1, 0.1))])
			a.in_move = Vector2.ZERO
			stuck.append("%s(end %s hits %s)" % [h.name, lp.snapped(Vector3(0.1, 0.1, 0.1)), cols])
	check("you can walk out of every house through its front door", stuck.is_empty(), "stuck in " + ", ".join(stuck))
	var up_spot: Vector3 = house.global_transform * Vector3(-0.5, 3.35, 0.4)
	game.spawn_pickup({"ammo": "light"}, up_spot)
	var loot: Dictionary = game.pickups[game.pickups.size() - 1]
	await put(start + out_dir * 6.0)
	S.destroy(shell)
	await frames(120)
	var trim: Node3D = house.find_child("house_trim", true, false)
	check("a destroyed house takes its trim and roof with it", not (shell.node as Node3D).visible and not trim.visible)
	check("loot from the upper floor falls to the ground", loot.pos.y < up_spot.y - 2.0, "%.1f -> %.1f" % [up_spot.y, loot.pos.y])
	check("house walls give wood when farmed", S.LEVEL.has("house_shell") and S.LEVEL["house_shell"][1] == "wood")
	# ---------------------------------------------------------------- gold, upgrade benches, hiring, reload animation
	await put(game.events._dry_spot(game.terrain.village + Vector2(26, 30)) + Vector3(0, 0.1, 0))
	a.gold = 0
	a.add_item({"gold": 40})
	check("gold bars add to the gold count", a.gold == 40)
	for i in Items.SLOTS:
		a.slots[i] = null
	a.active = -1
	a.add_item(Items.make("smg", 0))
	a.select(a.find_item("smg"))
	var bench: Dictionary = game.events.benches[0]
	await put(bench.pos + Vector3(1.6, 0.2, 0))
	check("standing at an upgrade bench is noticed", game.events.bench_near(a) != null)
	check("not enough gold: no upgrade", not game.events.upgrade(a) and a.item().rarity == 0)
	a.gold = 300
	check("the bench upgrades the held weapon for gold", game.events.upgrade(a) and a.item().rarity == 1 and a.gold == 200, "rarity %d gold %d" % [a.item().rarity, a.gold])
	# reload animation: the magazine drops out half way
	a.ammo["light"] = 60
	a.item().loaded = 0
	a.start_reload()
	var smg_body: Character = a.body
	await frames(int(a.reload_total * 60.0 * 0.33))
	var mag_out := false                              # watch the middle of the reload (one frame can catch a floor flicker)
	for k in int(a.reload_total * 60.0 * 0.18):
		await frames(1)
		if smg_body.mag != null and not smg_body.mag.visible:
			mag_out = true
	check("reloading drops the magazine out", mag_out, "mag %s" % [smg_body.mag != null])
	await frames(int(a.reload_total * 60.0 * 0.7))
	check("and it is back when the reload is done", smg_body.mag != null and smg_body.mag.visible and a.item().loaded > 0)
	# hiring a character
	var npc: Actor = game.npcs[0]
	await put(npc.global_position + Vector3(1.8, 0.2, 0))
	check("a character for hire can be talked to", game.npc_near(a) == npc)
	var before_alive: int = game.alive_count()
	npc.hit(80.0, game.actors[1], false, Vector3.ZERO)
	check("nobody hurts a character before they are hired", npc.hp == 100.0)
	a.gold = 500
	var cost: int = npc.get_node("NpcBrain").info.cost
	check("hiring takes the gold and the character joins you", game.hire_npc(npc) and game.hired == npc and a.gold == 500 - cost and npc.has_weapon())
	var hp_me: float = a.hp
	var hp_npc: float = npc.hp
	a.hit(30.0, npc, false, Vector3.ZERO)
	npc.hit(30.0, a, false, Vector3.ZERO)
	check("no friendly fire between you and your hire", a.hp == hp_me and npc.hp == hp_npc, "%.0f / %.0f" % [a.hp, npc.hp])
	npc.die(game.actors[1])
	await frames(2)
	check("a fallen hire is not a player: the count stays", game.hired == null and game.alive_count() == before_alive)
	print("EVENTTEST\n" + "\n".join(lines))
	print("EVENTTEST %s  (%d checks, %d failed)" % ["OK" if fails == 0 else "FAILED", lines.size(), fails])
	get_tree().quit()
