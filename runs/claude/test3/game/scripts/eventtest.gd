## Automated check of prompt 5: consumables, forage, launch pads, zip lines, rifts and supply drops.  Run:
##   godot --headless --path <project> -- --eventtest
extends Node

var game: Node
var a: Actor
var lines: Array = []
var fails := 0


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
	print("EVENTTEST\n" + "\n".join(lines))
	print("EVENTTEST %s  (%d checks, %d failed)" % ["OK" if fails == 0 else "FAILED", lines.size(), fails])
	get_tree().quit()
