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


func _bosses_section() -> void:
	var T = game.terrain
	var E: WorldEvents = game.events
	# ---------------------------------------------------------------- named places, bosses and keycard vaults
	var B: Bosses = game.bosses
	var want_names := ["Oakmoor Village", "Gearworks Yard", "Hayfield Farm", "Mirror Lake", "Frostpeak", "Sunscorch", "Sandbar Depot",
			"Willow Hamlet", "Gull Cove", "Red Mesas"]
	var have_names: Array = E.poi_names()
	var all_named := have_names.size() == 10
	for nm in want_names:
		all_named = all_named and have_names.has(nm)
	check("all 10 places have names", all_named, str(have_names))
	check("a place is found from its centre", E.poi_at(T.village) == "Oakmoor Village" and E.poi_at(T.east_cove) == "Gull Cove" and E.poi_at(Vector2(T.mesas[2][0])) == "Red Mesas")
	E.poi_current = ""
	E.poi_banner = {}
	a.state = Actor.State.SKYDIVE
	a.global_position = Vector3(T.snow_town.x, 200.0, T.snow_town.y)
	await frames(14)
	check("no banner while skydiving over a place", E.poi_banner.is_empty() and E.poi_current == "")
	await put(E._dry_spot(T.snow_town + Vector2(3, 3)) + Vector3(0, 0.1, 0))
	await frames(14)
	check("walking into Frostpeak shows its banner with the boss named", E.poi_banner.get("name", "") == "Frostpeak" and String(E.poi_banner.get("sub", "")).contains("Weaver"), str(E.poi_banner))
	# bosses
	check("three bosses stand guard, one vault each", B.list.size() == 3 and B.vaults.size() == 3)
	var alive0: int = game.alive_count()
	for b in B.list:
		var act: Actor = b.actor
		var lair: Vector2 = T.get(Bosses.SPEC[b.id].lair)
		var lair_d := Vector2(act.global_position.x, act.global_position.z).distance_to(lair)
		check("%s guards its lair" % b.name, lair_d < 55.0 and act.is_boss and act.alive(), "%.0f m from the centre" % lair_d)
		check("%s has boss health" % b.name, act.hp > 100.0 and act.shield > 0.0, "%.0f + %.0f" % [act.hp, act.shield])
		check("%s is not one of the players" % b.name, not game.actors.has(act))
	var players_alive := 0
	for o in game.actors:
		players_alive += 1 if o.alive() else 0
	check("bosses are not counted as alive players", alive0 == players_alive and B.alive_actors().size() == 3, "%d players, %d bosses" % [alive0, B.alive_actors().size()])
	var storm: Storm = game.storm
	if not storm.active:
		storm.start()
	var sv := [storm.active, storm.center, storm.radius, storm.tick]
	storm.active = true
	storm.center = Vector2(3000, 3000)
	storm.radius = 20.0
	storm.tick = 0.95
	var bot1: Actor = game.actors[1]
	var bot_hp: float = bot1.hp
	var bot_state: int = bot1.state
	bot1.state = Actor.State.GROUND                     # (a bot still on the blimp is not hurt)
	var boss_hps: Array = []
	for b in B.list:
		boss_hps.append(b.actor.hp + b.actor.shield)
	await frames(20)
	var unhurt := true
	for i in B.list.size():
		unhurt = unhurt and absf(B.list[i].actor.hp + B.list[i].actor.shield - float(boss_hps[i])) < 0.01
	check("the storm does not touch a boss (and does hurt a bot)", unhurt and bot1.hp < bot_hp, "bot %.0f -> %.0f" % [bot_hp, bot1.hp])
	bot1.state = bot_state as Actor.State
	storm.active = sv[0]
	storm.center = sv[1]
	storm.radius = sv[2]
	storm.tick = sv[3]
	bot1.hp = 100.0
	# a boss fights back when a player comes close
	var tink: Dictionary = B.list[2]
	var ta: Actor = tink.actor
	var tbrain: Node = ta.get_child(ta.get_child_count() - 1)
	var tdir := Vector3(-sin(ta.aim_yaw), 0, -cos(ta.aim_yaw))
	await put(ta.global_position + tdir * 16.0 + Vector3(0, 0.2, 0), ta.aim_yaw + PI)
	ta.process_mode = Node.PROCESS_MODE_INHERIT
	a.hp = 99999.0
	a.shield = 0.0
	await frames(300)
	check("a boss fights a player who comes within its reach", tbrain.mode == "fight" and a.hp < 99999.0, "mode %s, damage %.0f" % [tbrain.mode, 99999.0 - a.hp])
	ta.process_mode = Node.PROCESS_MODE_DISABLED
	a.hp = 100.0
	# bots keep clear of bosses unless well equipped
	var bbrain: Node = bot1.get_child(bot1.get_child_count() - 1)
	var old_pos := bot1.global_position
	bot1.global_position = ta.global_position + Vector3(20, 0, 0)
	for i in Items.SLOTS:
		bot1.slots[i] = null
	bot1.slots[0] = Items.make("assault_rifle", 1)
	bot1.shield = 100.0
	check("a poorly armed bot avoids a boss", not bbrain._engages(ta))
	bot1.slots[0] = Items.make("assault_rifle", 4)
	bot1.shield = 0.0
	check("a bot with no shield avoids a boss", not bbrain._engages(ta))
	bot1.shield = 75.0
	check("a bot with a shield and a legendary gun takes it on", bbrain._engages(ta))
	bot1.global_position = old_pos
	for i in Items.SLOTS:
		bot1.slots[i] = null
	bot1.shield = 0.0
	# screenshots: each boss at its lair, bar showing
	for b in B.list:
		var ba: Actor = b.actor
		var spot := Vector3.INF
		for dist in [7.0, 9.0, 11.0]:
			for k in 16:
				var ang: float = ba.aim_yaw + k * TAU / 16.0
				var dirv := Vector3(-sin(ang), 0, -cos(ang))
				var p: Vector3 = ba.global_position + dirv * dist
				p.y = T.height(p.x, p.z) + 0.2
				var cam: Vector3 = p + dirv * 4.6 + Vector3(0, 1.9, 0)
				if spot == Vector3.INF and game.nav.walkable(p) and game.can_see(p + Vector3(0, 1.5, 0), ba.eye()) and game.can_see(cam, ba.eye()):
					spot = p
		if spot == Vector3.INF:
			spot = ba.global_position + Vector3(0, 0, 9.0)
		await put(spot)
		var dd: Vector3 = ba.global_position - a.global_position
		var yaw := atan2(-dd.x, -dd.z)
		a.aim_yaw = yaw
		ba.shield -= 120.0                                # (not hit(): a boss that is shot at builds cover)
		B.note_damage(ba, a)
		ba.process_mode = Node.PROCESS_MODE_INHERIT       # awake, so it is drawn and animated (it notices us, too)
		a.hp = 99999.0
		await frames(12)
		a.aim_yaw = yaw
		await snap("boss_" + b.id, yaw, -0.05)
		ba.process_mode = Node.PROCESS_MODE_DISABLED
		a.hp = 100.0
	# killing a boss: gold, its keycard and its gear drop; the alive count does not move
	var weaver: Dictionary = B.list[0]
	var wa: Actor = weaver.actor
	var alive1: int = game.alive_count()
	wa.hit(9000.0, a, true, Vector3.ZERO)
	await frames(3)
	var card_pk = null
	var gold_ok := false
	for pk in game.pickups:
		if pk.item.get("id", "") == "keycard_weaver":
			card_pk = pk
		if pk.item.has("gold") and int(pk.item.gold) == 150:
			gold_ok = true
	check("a defeated boss is dead and drops about 150 gold", not wa.alive() and gold_ok)
	check("a defeated boss drops its keycard", card_pk != null)
	var gear_ok := false
	for pk in game.pickups:
		if pk.item.has("id") and Items.def(pk.item).kind == "weapon" and int(pk.item.rarity) == 4 and pk.pos.distance_to(wa.global_position) < 4.0:
			gear_ok = true
	check("and its legendary gear", gear_ok)
	check("a dead boss leaves the alive count alone", game.alive_count() == alive1 and not weaver.alive)
	# vaults
	var v: Dictionary = B.vaults["weaver"]
	for i in Items.SLOTS:
		a.slots[i] = null
	a.active = -1
	await put(card_pk.pos + Vector3(0, 0.1, 0))
	await frames(70)
	check("walking over the keycard picks it up", a.find_item("keycard_weaver") >= 0)
	var face_yaw := atan2(-(v.pos.x - v.front.x), -(v.pos.z - v.front.z))
	var back_off: Vector3 = (v.front - v.pos)
	back_off.y = 0.0
	await put(v.front + back_off.normalized() * 1.6 + Vector3(0, 0.2, 0), face_yaw)
	var door_cell: Vector3 = (v.root as Node3D).global_transform * Vector3(0, 0.5, 2.75)
	check("the vault door is blocked on the bots' grid", not game.nav.walkable(door_cell))
	check("the vault is noticed from its door", B.vault_near(a) == v)
	check("the wrong keycard does not open a vault", not B.open_vault(B.vaults["ravage"], a) and not B.vaults["ravage"].opened)
	var carried: int = a.find_item("keycard_weaver")
	a.slots[carried] = null
	check("the vault door stays shut without the keycard", not B.open_vault(v, a) and not v.opened and not (v.door_shape as CollisionShape3D).disabled)
	var locked_chest: Dictionary = v.chests[0]
	game.open_container(locked_chest, a)
	check("the golden chests are locked behind the door", not locked_chest.opened and game.nearest_container(locked_chest.pos, 2.0) == null)
	a.slots[carried] = Items.make("keycard_weaver")
	await frames(10)
	await snap("vault_door_locked", face_yaw, -0.1)
	check("the matching keycard opens it and is used up", B.open_vault(v, a) and v.opened and a.find_item("keycard_weaver") < 0)
	await frames(90)
	check("the door slides open and stops blocking", (v.door as Node3D).position.x > 2.5 and (v.door_shape as CollisionShape3D).disabled)
	check("the bots' grid opens with the door", game.nav.walkable(door_cell))
	await snap("vault_door_open", face_yaw, -0.1)
	var epic_all := true
	var chest_n := 0
	for c in v.chests:
		var n0: int = game.pickups.size()
		game.open_container(c, a)
		var epic := false
		var gold100 := false
		for k in range(n0, game.pickups.size()):
			var it: Dictionary = game.pickups[k].item
			if it.has("id") and Items.def(it).kind == "weapon" and int(it.rarity) >= 3:
				epic = true
			if it.has("gold") and int(it.gold) == 100:
				gold100 = true
		epic_all = epic_all and epic and gold100 and c.opened
		chest_n += 1
	check("all three vault chests give an epic or better gun and 100 gold", epic_all and chest_n == 3)
	# a bot that holds a keycard heads for its vault
	var rv: Dictionary = B.vaults["ravage"]
	bot1.slots[0] = Items.make("keycard_ravage")
	bot1.global_position = rv.front + Vector3(25, 0.3, 0)
	bbrain.target = null
	bbrain.has_goal = false
	var storm_was: bool = game.storm.active
	game.storm.active = false                           # (the storm comes first in a bot's mind)
	bbrain._decide()
	game.storm.active = storm_was
	check("a bot carrying a keycard heads for its vault", bbrain.mode == "vault" and bbrain.goal.distance_to(rv.front) < 1.0, "mode %s" % bbrain.mode)
	bot1.global_position = old_pos
	bot1.slots[0] = null
	bbrain.has_goal = false
	# the walls stand against pickaxe, bullets and blasts
	var wall_pos: Vector3 = (v.root as Node3D).global_transform * Vector3(-3.75, 2.0, 0.0)
	var outside_pos: Vector3 = (v.root as Node3D).global_transform * Vector3(-9.0, 2.0, 0.0)
	var wall_hit: Dictionary = game.ray(outside_pos, wall_pos, null, 1)
	var destroyed0: int = game.structures.destroyed
	var hit_back = null
	if not wall_hit.is_empty():
		hit_back = game.structures.damage_at(wall_hit.collider, wall_hit.get("shape", 0), 9999.0, a, wall_hit.position)
		game.structures.pickaxe_hit(a, wall_hit)
	game.structures.explode(wall_pos, 12.0, 99999.0, a)
	await frames(10)
	var wall_ok: bool = not wall_hit.is_empty() and wall_hit.collider == v.body and hit_back == null and game.structures.lookup(v.body, 0) == null
	check("vault walls cannot be damaged by bullets, the pickaxe or explosions", wall_ok and v.root.is_inside_tree() and (v.root as Node3D).visible and not game.nav.walkable(wall_pos),
			"hit %s, collider is vault %s, hit_back %s, destroyed %d->%d, cell walkable %s" % [not wall_hit.is_empty(), not wall_hit.is_empty() and wall_hit.collider == v.body, hit_back, destroyed0, game.structures.destroyed, game.nav.walkable(wall_pos)])
	await put(E._dry_spot(T.desert_town) + Vector3(0, 0.1, 0))
	await frames(14)
	game.controller.show_map = true
	await snap("map_pois", 0.0, 0.0)
	game.controller.show_map = false


func _ready() -> void:
	await frames(5)
	a = game.player
	game.controller.demo = true
	for o in game.actors:
		if o != a:
			o.process_mode = Node.PROCESS_MODE_DISABLED
	for b in game.bosses.list:                          # the bosses stand still unless a test wakes them
		b.actor.process_mode = Node.PROCESS_MODE_DISABLED
	if OS.get_cmdline_user_args().has("--bossshots"):            # only the boss and vault checks (and their screenshots)
		await _bosses_section()
		print("EVENTTEST\n" + "\n".join(lines))
		print("EVENTTEST %s  (%d checks, %d failed)" % ["OK" if fails == 0 else "FAILED", lines.size(), fails])
		get_tree().quit()
		return
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
	await frames(int(a.reload_total * 60.0 * 0.45))
	check("reloading drops the magazine out", smg_body.mag != null and not smg_body.mag.visible, "mag %s" % [smg_body.mag != null])
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
	await _bosses_section()
	print("EVENTTEST\n" + "\n".join(lines))
	print("EVENTTEST %s  (%d checks, %d failed)" % ["OK" if fails == 0 else "FAILED", lines.size(), fails])
	get_tree().quit()
