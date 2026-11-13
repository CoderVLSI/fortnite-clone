## Two-process LAN test. Run the host and the client as two headless Godot processes (tools/nettest.sh does it):
##   godot --headless --path <game> -- --nettest-host      (hosts, starts the match when the client has joined)
##   godot --headless --path <game> -- --nettest-client    (joins 127.0.0.1)
## Both print PASS / FAIL lines. The two sides exchange small values over NetMatch.test_send to compare their worlds.
extends Node

var game: Node
var nm: Node
var host := false
var fails := 0
var passes := 0
var spot := Vector3.ZERO
var bot_idx := 0
var start_t := 0.0
var shot_dir := ""


func setup(g: Node) -> void:
	game = g
	nm = g.nm
	host = g.net_host
	start_t = Time.get_ticks_msec() / 1000.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--net-shot="):
			shot_dir = a.get_slice("=", 1)
	g.controller.set_physics_process(false)          # the test drives the inputs itself
	g.controller.set_process_unhandled_input(false)
	if host:
		_run_host.call_deferred()
	else:
		_run_client.call_deferred()


func check(name: String, ok: bool, detail := "") -> void:
	var tag := "HOST  " if host else "CLIENT"
	print("%s %s  %s%s" % [tag, "PASS" if ok else "FAIL", name, ("   " + detail) if detail != "" else ""])
	if ok:
		passes += 1
	else:
		fails += 1


var slow := DisplayServer.get_name() != "headless"      # a software renderer: everything takes several times longer


func wait(sec: float) -> void:
	await get_tree().create_timer(sec * (4.0 if slow else 1.0)).timeout


func until(cond: Callable, timeout: float) -> bool:
	var end := Time.get_ticks_msec() + int(timeout * (8.0 if slow else 1.0) * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func got(k: String, timeout := 20.0) -> Variant:
	await until(func() -> bool: return nm.test_in.has(k), timeout)
	return nm.test_in.get(k)


func shot(nm_: String) -> void:
	## --net-shot=<dir>: save what this side sees (needs a real renderer: run under xvfb).
	if shot_dir == "" or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(shot_dir)
	await wait(0.5)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shot_dir.path_join(nm_ + ".png"))
	print("SHOT ", nm_)


func world_hash() -> String:
	## What the world looks like after set-up: pickups, containers, npcs, bosses, structures.
	var parts: Array = []
	var ps: Array = game.pickups.duplicate()
	ps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.id) < int(b.id))
	var pk := 0
	for p in ps:
		pk = hash("%d|%s|%d|%.1f,%.1f,%.1f" % [pk, str(p.item.get("id", p.item.keys())), int(p.id), p.pos.x, p.pos.y, p.pos.z])
	parts.append("pk%d:%d" % [ps.size(), pk])
	var ck := 0
	for c in game.containers:
		ck = hash("%d|%s|%.1f,%.1f,%.1f" % [ck, c.kind, c.pos.x, c.pos.y, c.pos.z])
	parts.append("ct%d:%d" % [game.containers.size(), ck])
	var nk := 0
	for n in game.npcs:
		nk = hash("%d|%s|%.1f,%.1f" % [nk, n.display_name, n.global_position.x, n.global_position.z])
	parts.append("npc%d:%d" % [game.npcs.size(), nk])
	var bk := 0
	for b in game.bosses.list:
		bk = hash("%d|%s|%.0f|%.1f,%.1f" % [bk, b.name, b.actor.hp, b.home.x, b.home.z])
	parts.append("boss%d:%d" % [game.bosses.list.size(), bk])
	parts.append("lvl%d" % game.structures.level_count)
	parts.append("blimp%.2f,%.2f" % [game.blimp_from.x, game.blimp_from.z])
	return "|".join(parts)


func bots_pos(n: int) -> Array:
	var out: Array = []
	for i in range(2, 2 + n):
		out.append(game.actors[i].global_position)
	return out


func _freeze_bots() -> void:
	for i in range(2, game.actors.size()):
		var a: Actor = game.actors[i]
		a.in_move = Vector2.ZERO
		a.in_fire = false
		var br := a.get_child(a.get_child_count() - 1)
		if br is Node and br.get("mode") != null:
			br.set_physics_process(false)


func _dry_spot() -> Vector3:
	var c: Vector2 = game.terrain.village
	return game.events._dry_spot(c + Vector2(6, 6))


func _finish() -> void:
	var tag := "HOST" if host else "CLIENT"
	print("%s NETTEST %s: %d passed, %d failed" % [tag, "OK" if fails == 0 else "FAILED", passes, fails])
	await wait(0.5)
	get_tree().quit(1 if fails > 0 else 0)


# ----------------------------------------------------------------------------- host

func _run_host() -> void:
	var me: Actor = game.actors[0]
	var cl: Actor = game.actors[1]
	check("the client connected and both are in the party", game.netsvc.peers.size() == 2 and game.humans.size() == 2 and cl.peer_id > 1,
			"peers=%d humans=%d" % [game.netsvc.peers.size(), game.humans.size()])
	var h := world_hash()
	nm.test_send("hash", h)
	var ch = await got("hash")
	check("world hash matches (pickups, containers, npcs, bosses, structures)", ch == h, "host=%s client=%s" % [h, ch])
	check("the same seed", str(await got("seed")) == str(game.netsvc.match_info.seed))
	check("49 bots + 1 other human: 48 bots", game.actors.size() == 50 and game.bosses.list.size() == 3, str(game.actors.size()))
	# warm-up: everyone is on the ground. The client walks; bots walk on the host and should follow on the client.
	await until(func() -> bool: return not game.net_waiting and game.warmup_left > 0.0, 10.0)
	var p0 := bots_pos(10)
	var wlk = await got("walked", 30.0)
	var moved := 0
	var p1 := bots_pos(10)
	for i in 10:
		if (p0[i] as Vector3).distance_to(p1[i]) > 1.0:
			moved += 1
	var cd: float = cl.global_position.distance_to(wlk) if wlk is Vector3 else 99.0
	check("the client's actor moved on the host when the client moved (within 1 m)", cd < 1.0, "off by %.2f m" % cd)
	_freeze_bots()
	await wait(0.6)
	nm.test_send("bots", bots_pos(10))
	nm.test_send("bots_moved", moved)
	# the blimp: everyone aboard, then the client jumps by command
	await until(func() -> bool: return not game.warming_up(), 20.0)
	await wait(0.1)
	check("the client is on the blimp", cl.state == Actor.State.BLIMP, str(cl.state))
	var jumped := await until(func() -> bool: return cl.state == Actor.State.SKYDIVE, 6.0)
	check("the client jumped from the blimp (command reached the host)", jumped and nm.cmd_log.has("jump"), str(nm.cmd_log))
	# put the client on dry land next to a weapon
	spot = _dry_spot()
	game.spawn_pickup(Items.make("assault_rifle", 2), spot + Vector3(1.2, 0.3, 0))
	nm.ev_to(cl.peer_id, "set_pos", [spot + Vector3(0, 0.6, 0), Vector3.ZERO])
	cl.global_position = spot + Vector3(0, 0.6, 0)
	var picked := await until(func() -> bool: return cl.find_item("assault_rifle") >= 0, 10.0)
	check("the client picked the item up (host side)", picked, str(cl.slots))
	nm.test_send("slot", cl.find_item("assault_rifle"))
	var cslot = await got("cslot")
	check("host and client agree on the slot", cslot != null and int(cslot) == cl.find_item("assault_rifle") and int(cslot) >= 0, "client=%s host=%d" % [str(cslot), cl.find_item("assault_rifle")])
	# the client shoots a bot
	await until(func() -> bool: return cl.state == Actor.State.GROUND, 8.0)
	_freeze_bots()
	var bot: Actor = game.actors[5]
	var fwd := Vector3(0, 0, -1)
	bot.global_position = cl.global_position + fwd * 12.0 + Vector3(0, 0.2, 0)
	bot.velocity = Vector3.ZERO
	bot.state = Actor.State.GROUND
	bot.hp = 100.0
	bot.shield = 0.0
	nm.test_send("target", 5)
	await wait(1.0)
	cl.active = cl.find_item("assault_rifle")
	var hp0 := bot.hp
	nm.test_send("fire", 1)
	var hurt := await until(func() -> bool: return bot.hp < hp0, 8.0)
	check("the client's shot damaged a bot on the host", hurt, "hp %.0f -> %.0f" % [hp0, bot.hp])
	var dn = await got("dmgnum", 8.0)
	check("(client) got a damage number", int(dn if dn != null else 0) > 0, str(dn))
	# building (the host's own character stands beside the client for the screenshot)
	me.state = Actor.State.GROUND
	me.global_position = cl.global_position + Vector3(-3.0, 0.3, 2.5)
	game.controller.yaw = 0.35
	game.controller.pitch = -0.15
	me.aim_yaw = 0.35
	cl.mats["wood"] = 200
	await wait(0.3)
	nm.test_send("build", 1)
	var built := await until(func() -> bool: return game.structures.pieces.size() >= 1, 8.0)
	var wid := -1
	for k in game.structures.pieces:
		wid = int(game.structures.pieces[k].id)
	check("the client built a wall (host side)", built and game.structures.pieces.size() >= 1, "pieces=%d" % game.structures.pieces.size())
	nm.test_send("wall_id", wid)
	var seen = await got("wall_seen", 8.0)
	check("(client) sees the wall under the same id", seen != null and int(seen) == wid, "host id=%d client=%s" % [wid, str(seen)])
	var we = game.structures.by_id.get(wid)
	await shot("net_host")
	game.structures.destroy(we)
	await wait(0.6)
	check("the host broke it: gone on the host", we.dead and not game.structures.by_id.has(wid))
	nm.test_send("wall_broken", wid)
	var wg = await got("wall_gone", 8.0)
	check("(client) the wall is gone there too", wg != null and int(wg) == 1)
	# a chest
	var ci := -1
	for i in game.containers.size():
		if not game.containers[i].opened and not game.containers[i].get("locked", false) and game.containers[i].kind == "chest":
			ci = i
			break
	game.open_container(game.containers[ci], me)
	nm.test_send("chest", ci)
	var co = await got("chest_open", 8.0)
	check("(client) the chest the host opened is open there", co != null and int(co) == 1)
	# storm and alive count
	game.storm.start()
	await wait(1.0)
	nm.test_send("storm", [game.storm.radius, game.alive_count(), game.storm.active])
	var sres = await got("storm_ok", 8.0)
	check("storm radius, activity and alive count match", sres != null and int(sres) == 1)
	# elimination
	var killer: Actor = me
	cl.hp = 1.0
	cl.hit(50.0, killer, false, killer.global_position)
	await wait(1.0)
	check("the client is eliminated on the host", not cl.alive() and cl.placement >= 2, "placement=%d" % cl.placement)
	var eo = await got("elim_ok", 8.0)
	check("(client) saw its elimination and placement", eo != null and int(eo) == 1)
	# the match ends: every bot falls, the host is the last one standing
	for i in range(2, game.actors.size()):
		var b: Actor = game.actors[i]
		if b.alive():
			b.die(null)
	await wait(1.0)
	check("match over on the host", game.over and game.winner == me)
	var oo = await got("over_ok", 8.0)
	check("(client) match over reached the client", oo != null and int(oo) == 1)
	nm.test_send("done", 1)
	_finish()


# ----------------------------------------------------------------------------- client

func _run_client() -> void:
	var me: Actor = game.player
	var host_actor: Actor = game.actors[0]
	check("in the party with the host", game.netsvc.peers.size() == 2 and game.my_idx == 1 and me.peer_id > 1,
			"peers=%d idx=%d" % [game.netsvc.peers.size(), game.my_idx])
	nm.test_send("hash", world_hash())
	nm.test_send("seed", game.netsvc.match_info.seed)
	check("the host's character is shown with its name", host_actor.display_name == game.netsvc.peers[0].name, host_actor.display_name)
	await until(func() -> bool: return nm.got_snap, 15.0)
	check("snapshots are arriving", nm.got_snap)
	# walk forward on the ground during the warm-up
	await until(func() -> bool: return game.warmup_left > 0.0, 10.0)
	await wait(0.3)
	var y0 := me.global_position
	me.aim_yaw = 0.0
	me.in_move = Vector2(0, 1)
	me.in_sprint = true
	await wait(1.5)
	me.in_move = Vector2.ZERO
	await wait(0.8)
	check("the client's own character really moved", me.global_position.distance_to(y0) > 4.0, "%.1f m" % me.global_position.distance_to(y0))
	nm.test_send("walked", me.global_position)
	var hb = await got("bots", 30.0)
	var near := 0
	var cnt := 0
	for i in 10:
		var pp: Vector3 = game.actors[2 + i].global_position
		cnt += 1
		if pp.distance_to(hb[i]) < 2.0:
			near += 1
	check("bots on the client are within 2 m of the host's", near >= 9, "%d/%d" % [near, cnt])
	var moved = await got("bots_moved", 5.0)
	check("bots moved during the warm-up", int(moved) >= 3, "host saw %s of 10 move" % str(moved))
	# the blimp
	await until(func() -> bool: return not game.warming_up() and me.state == Actor.State.BLIMP, 25.0)
	await wait(1.0)
	me.in_jump = true                                # the blimp tick turns this into the jump command
	await until(func() -> bool: return me.state == Actor.State.SKYDIVE, 3.0)
	check("jumped from the blimp", me.state == Actor.State.SKYDIVE)
	# landed next to the item: the host picks it up and tells us
	var ok := await until(func() -> bool: return me.find_item("assault_rifle") >= 0, 12.0)
	check("the private state shows the picked-up item", ok, str(me.slots))
	nm.test_send("cslot", me.find_item("assault_rifle"))
	await until(func() -> bool: return me.state == Actor.State.GROUND, 8.0)
	# shoot the bot the host put in front of us
	var ti = await got("target", 15.0)
	var bot: Actor = game.actors[int(ti)]
	await wait(1.2)
	await got("fire", 15.0)
	var cam: Camera3D = game.controller.cam
	for k in 4:
		var d: Vector3 = (bot.centre() - cam.global_position).normalized()
		game.controller.yaw = atan2(-d.x, -d.z)
		game.controller.pitch = asin(d.y)
		game.controller._process(0.016)
	var f := (bot.centre() - me.eye())
	me.aim_yaw = atan2(-f.x, -f.z)
	me.aim_pitch = asin(f.normalized().y)
	me.in_fire = true
	me.net_fire_edge += 1
	await wait(0.7)
	me.in_fire = false
	await wait(0.5)
	nm.test_send("dmgnum", int(nm.test_counts.get("dmg", 0)))
	# build a wall
	await got("build", 15.0)
	game.cmd(me, "build", ["wall"])
	await until(func() -> bool: return me.build_piece == "wall", 3.0)
	me.net_build_fire = true
	await wait(0.6)
	me.net_build_fire = false
	var wid := -1
	var S: Structures = game.structures
	await until(func() -> bool: return S.pieces.size() >= 1, 5.0)
	for k in S.pieces:
		wid = int(S.pieces[k].id)
	var hid = await got("wall_id", 8.0)
	check("the wall exists on the client with the host's id", S.by_id.has(int(hid)) and S.by_id[int(hid)].kind == "build" and S.by_id[int(hid)].owner == me, "id=%s" % str(hid))
	await shot("net_client")
	nm.test_send("wall_seen", wid)
	var broken = await got("wall_broken", 10.0)
	await until(func() -> bool: return not S.by_id.has(int(broken)), 4.0)
	check("the wall is gone after the host broke it", not S.by_id.has(int(broken)))
	nm.test_send("wall_gone", 1 if not S.by_id.has(int(broken)) else 0)
	var ci = await got("chest", 10.0)
	await until(func() -> bool: return game.containers[int(ci)].opened, 4.0)
	check("the chest the host opened is open here", game.containers[int(ci)].opened)
	nm.test_send("chest_open", 1 if game.containers[int(ci)].opened else 0)
	var st = await got("storm", 10.0)
	await wait(0.5)
	var same: bool = absf(game.storm.radius - float(st[0])) < 1.0 and bool(st[2]) == game.storm.active and game.alive_count() == int(st[1])
	check("storm radius and alive count match the host", same, "r=%.1f/%.1f alive=%d/%d" % [game.storm.radius, float(st[0]), game.alive_count(), int(st[1])])
	nm.test_send("storm_ok", 1 if same else 0)
	await until(func() -> bool: return not me.alive(), 8.0)
	var el: bool = not me.alive() and me.placement >= 2
	check("eliminated, and sees its placement", el, "placement=%d" % me.placement)
	nm.test_send("elim_ok", 1 if el else 0)
	await until(func() -> bool: return game.over, 10.0)
	check("match over reached the client", game.over and game.winner == host_actor)
	nm.test_send("over_ok", 1 if game.over else 0)
	await got("done", 10.0)
	_finish()
