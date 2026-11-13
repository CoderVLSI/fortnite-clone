## In-match networking (a child node "NetMatch" of the game scene, created when a network session runs the match).
## Host-authoritative: the host simulates everything (bots, combat, items, storm); clients move their own character and
## send inputs; everything else they see arrives here:
##   host -> clients  snapshots of every actor (~20 Hz, unreliable)   _pack_actor / _unpack_actor
##   host -> a client private state of its own actor (slots, ammo, hp ...)
##   host -> clients  world events (reliable): structures, pickups, containers, feed, announcements ...
##   host -> clients  fx batches (tracers, positional sounds), unreliable
##   client -> host   inputs + own position at ~30 Hz, commands (reliable)
extends Node

const SNAP_EVERY := 3                    # physics ticks between snapshots (60 Hz / 3 = 20 Hz)
const INPUT_EVERY := 2
const INTERP_DELAY := 0.1
const NONE_U8 := 255

var game: Node
var all: Array = []                      # every actor that is snapshotted: players + bots, then bosses, then npcs (same order everywhere)
var bufs := {}                           # client: actor index -> [{t, ...}] snapshots waiting to be shown
var brains := {}                         # host: peer id -> remote_brain
var tick := 0
var fx_q: Array = []
var priv_dirty := {}
var got_snap := false
var snap := {}                           # the last header received (client)
var item_ids: Array = []
var emote_ids: Array = []
var test_in := {}                        # nettest: values the other side sent
var last_input_sent := PackedByteArray()
var jump_n := 0
var crouch_n := 0
var cmd_log: Array = []


func setup(g: Node) -> void:
	game = g
	item_ids = Items.DEFS.keys()
	emote_ids = Character.EMOTES.keys()
	all = game.actors.duplicate()
	for b in game.bosses.list:
		all.append(b.actor)
	for n in game.npcs:
		all.append(n)
	var plist: Array = game.netsvc.match_info.players
	for i in plist.size():
		(game.actors[i] as Actor).peer_id = int(plist[i].peer_id)
	if game.net_host:
		for i in plist.size():
			if int(plist[i].peer_id) != 1:
				var br := preload("res://scripts/remote_brain.gd").new()
				br.name = "RemoteBrain"
				game.actors[i].add_child(br)
				br.setup(game, game.actors[i], int(plist[i].peer_id))
				brains[int(plist[i].peer_id)] = br
		if game.mode_duos():
			var humans: Array = game.humans
			if humans.size() == 2 and game.has_method("setup_duo"):
				game.setup_duo(humans[0], humans[1])
	else:
		for a in all:
			if a != game.player:
				a.net_puppet = true
				a.set_physics_process(true)
		for n in game.npcs:
			var nb := (n as Actor).get_node_or_null("NpcBrain")
			if nb:
				nb.set_physics_process(false)
		game.netsvc.rpc_id(1, "_r_loaded")


func index_of(a: Actor) -> int:
	return all.find(a)


func actor_of_peer(peer: int) -> Actor:
	for a in game.humans:
		if a.peer_id == peer:
			return a
	return null


# ----------------------------------------------------------------------------- frame

func _physics_process(_delta: float) -> void:
	tick += 1
	if game.net_host:
		if game.net_waiting:
			return
		if tick % SNAP_EVERY == 0:
			_send_snapshot()
		if tick % 6 == 0:
			for a in game.humans:
				if a.peer_id > 1:
					_send_priv(a)
					priv_dirty.erase(a.peer_id)
		elif not priv_dirty.is_empty():
			for pid in priv_dirty.keys():
				var ha := actor_of_peer(pid)
				if ha:
					_send_priv(ha)
			priv_dirty.clear()
		if tick % 2 == 0 and not fx_q.is_empty():
			var q := fx_q
			fx_q = []
			rpc("_r_fx", q)
	else:
		if tick % INPUT_EVERY == 0 and got_snap:
			rpc_id(1, "_r_input", _pack_input(game.player))


func _process(_d: float) -> void:
	if game.net_client and got_snap:
		_show_puppets()


# ----------------------------------------------------------------------------- snapshots (host -> clients)

func _send_snapshot() -> void:
	var s := StreamPeerBuffer.new()
	var st: Storm = game.storm
	s.put_float(game.match_time)
	s.put_float(game.warmup_left)
	s.put_u8(game.alive_count())
	s.put_u8((1 if st.active else 0) | (2 if st.shrinking else 0) | (4 if st.done else 0) | (8 if game.over else 0))
	s.put_u8(st.phase)
	s.put_float(st.timer)
	s.put_float(st.center.x)
	s.put_float(st.center.y)
	s.put_float(st.radius)
	s.put_float(st.next_center.x)
	s.put_float(st.next_center.y)
	s.put_float(st.next_radius)
	s.put_u16(all.size())
	for a in all:
		_pack_actor(s, a)
	rpc("_r_snap", s.data_array)


@rpc("authority", "unreliable_ordered")
func _r_snap(data: PackedByteArray) -> void:
	var s := StreamPeerBuffer.new()
	s.data_array = data
	var h := {}
	h["t"] = s.get_float()
	h["warm"] = s.get_float()
	h["alive"] = s.get_u8()
	var fl := s.get_u8()
	h["storm_active"] = fl & 1 != 0
	h["shrinking"] = fl & 2 != 0
	h["done"] = fl & 4 != 0
	h["over"] = fl & 8 != 0
	h["phase"] = s.get_u8()
	h["timer"] = s.get_float()
	h["c"] = Vector2(s.get_float(), s.get_float())
	h["r"] = s.get_float()
	h["nc"] = Vector2(s.get_float(), s.get_float())
	h["nr"] = s.get_float()
	snap = h
	var n := s.get_u16()
	var now := Time.get_ticks_msec() / 1000.0
	for i in n:
		var e := _unpack_actor(s)
		e["at"] = now
		var b: Array = bufs.get(i, [])
		b.append(e)
		if b.size() > 10:
			b.pop_front()
		bufs[i] = b
	_apply_header(h)


func _apply_header(h: Dictionary) -> void:
	var st: Storm = game.storm
	if not got_snap:
		got_snap = true
		game.net_waiting = false
		game.match_time = h.t
		game.warmup_left = h.warm
	if absf(game.match_time - float(h.t)) > 0.3:
		game.match_time = h.t
	else:
		game.match_time = lerpf(game.match_time, float(h.t), 0.1)
	var w: float = h.warm
	if game.warmup_left > 0.0 and w <= 0.0:
		game.warmup_left = 0.0
		game._end_warmup()
	elif w > 0.0:
		game.warmup_left = w
	st.active = h.storm_active
	st.shrinking = h.shrinking
	st.done = h.done
	st.phase = h.phase
	st.timer = h.timer
	st.center = h.c
	st.radius = h.r
	st.next_center = h.nc
	st.next_radius = h.nr


## ONE place that decides what is sent per actor, so a field is added in both functions below and nowhere else.
func _pack_actor(s: StreamPeerBuffer, a: Actor) -> void:
	s.put_float(a.global_position.x)
	s.put_float(a.global_position.y)
	s.put_float(a.global_position.z)
	s.put_16(clampi(int(a.velocity.x * 20.0), -32000, 32000))
	s.put_16(clampi(int(a.velocity.y * 20.0), -32000, 32000))
	s.put_16(clampi(int(a.velocity.z * 20.0), -32000, 32000))
	s.put_16(int(wrapf(a.aim_yaw, -PI, PI) / PI * 32000.0))
	s.put_16(int(clampf(a.aim_pitch, -1.6, 1.6) / 1.6 * 32000.0))
	s.put_u8(a.state)
	var fl := 0
	fl |= 1 if a.crouched else 0
	fl |= 2 if a.sliding else 0
	fl |= 4 if (a.net_floor if a.remote_sim else (a.is_on_floor() or bool(a.get_meta("force_floor", false)))) else 0
	fl |= 8 if a.launched else 0
	fl |= 16 if a.tsprint else 0
	fl |= 32 if a.zip != null else 0
	fl |= 64 if a.reloading > 0.0 else 0
	fl |= 128 if a.using > 0.0 else 0
	fl |= 256 if a.in_dive else 0
	s.put_u16(fl)
	s.put_u8(int(clampf(a.tsprint_k, 0.0, 1.0) * 255.0))
	s.put_u8(NONE_U8 if a.hurdle_t < 0.0 else int(clampf(a.hurdle_t / maxf(a.hurdle_dur, 0.01), 0.0, 1.0) * 250.0))
	s.put_u8(NONE_U8 if a.mantle_t < 0.0 else int(clampf(a.mantle_t / maxf(a.mantle_dur, 0.01), 0.0, 1.0) * 250.0))
	var held := 0
	var rar := 0
	if a.build_piece != "":
		held = 1
	else:
		var it = a.item()
		if it != null:
			held = 2 + item_ids.find(it.id)
			rar = int(it.rarity) if it.has("rarity") else 0
	s.put_u8(held)
	s.put_u8(rar)
	s.put_u8(0 if a.emote == "" else 1 + emote_ids.find(a.emote))
	s.put_u8(0 if a.build_piece == "" else 1 + Structures.PIECES.find(a.build_piece))
	s.put_u16(clampi(int(ceil(a.hp)), 0, 65000))
	s.put_u16(clampi(int(ceil(a.shield)), 0, 65000))
	s.put_u8(clampi(int(a.reloading * 40.0), 0, 255))
	s.put_u8(clampi(int(a.reload_total * 40.0), 0, 255))
	s.put_u8(clampi(int(a.using * 40.0), 0, 255))


func _unpack_actor(s: StreamPeerBuffer) -> Dictionary:
	var e := {}
	e["pos"] = Vector3(s.get_float(), s.get_float(), s.get_float())
	e["vel"] = Vector3(s.get_16(), s.get_16(), s.get_16()) / 20.0
	e["yaw"] = float(s.get_16()) / 32000.0 * PI
	e["pitch"] = float(s.get_16()) / 32000.0 * 1.6
	e["state"] = s.get_u8()
	e["fl"] = s.get_u16()
	e["tk"] = float(s.get_u8()) / 255.0
	var hur := s.get_u8()
	e["hur"] = -1.0 if hur == NONE_U8 else float(hur) / 250.0
	var man := s.get_u8()
	e["man"] = -1.0 if man == NONE_U8 else float(man) / 250.0
	e["held"] = s.get_u8()
	e["rar"] = s.get_u8()
	e["emote"] = s.get_u8()
	e["bp"] = s.get_u8()
	e["hp"] = s.get_u16()
	e["sh"] = s.get_u16()
	e["rl"] = float(s.get_u8()) / 40.0
	e["rtot"] = float(s.get_u8()) / 40.0
	e["us"] = float(s.get_u8()) / 40.0
	return e


## Show the newest snapshots ~100 ms late, blending the two that surround that moment.
func _show_puppets() -> void:
	var now := Time.get_ticks_msec() / 1000.0 - INTERP_DELAY
	for i in all.size():
		var a: Actor = all[i]
		if not a.net_puppet:
			continue
		var b: Array = bufs.get(i, [])
		if b.is_empty():
			continue
		var k := b.size() - 1
		while k > 0 and float(b[k].at) > now:
			k -= 1
		var e0: Dictionary = b[k]
		var pos: Vector3 = e0.pos
		var yaw: float = e0.yaw
		var pitch: float = e0.pitch
		var vel: Vector3 = e0.vel
		var e: Dictionary = e0
		if k + 1 < b.size():
			var e1: Dictionary = b[k + 1]
			var span := maxf(float(e1.at) - float(e0.at), 0.001)
			var f := clampf((now - float(e0.at)) / span, 0.0, 1.0)
			if (e1.pos as Vector3).distance_to(e0.pos) < 25.0:
				pos = (e0.pos as Vector3).lerp(e1.pos, f)
			else:
				pos = e1.pos
			yaw = lerp_angle(e0.yaw, e1.yaw, f)
			pitch = lerpf(e0.pitch, e1.pitch, f)
			vel = (e0.vel as Vector3).lerp(e1.vel, f)
			e = e1 if f > 0.5 else e0
		elif now > float(e0.at):
			pos += (e0.vel as Vector3) * minf(now - float(e0.at), 0.2)
		_apply_puppet(a, e, pos, yaw, pitch, vel)


func _apply_puppet(a: Actor, e: Dictionary, pos: Vector3, yaw: float, pitch: float, vel: Vector3) -> void:
	var st: int = e.state
	if st == Actor.State.DEAD:
		a.net_set_dead()
		if a.is_boss:
			game.bosses.net_boss_down(a)
		return
	a.global_position = pos
	a.velocity = vel
	a.aim_yaw = yaw
	a.aim_pitch = pitch
	a.state = st as Actor.State
	var fl: int = e.fl
	a.crouched = fl & 1 != 0
	a.sliding = fl & 2 != 0
	a.set_meta("force_floor", fl & 4 != 0)
	a.launched = fl & 8 != 0
	a.tsprint = fl & 16 != 0
	a.in_dive = fl & 256 != 0
	a.tsprint_k = e.tk
	a.hurdle_dur = 1.0
	a.hurdle_t = e.hur
	a.mantle_dur = 1.0
	a.mantle_t = e.man
	a.hp = float(e.hp)
	a.shield = float(e.sh)
	a.reloading = e.rl
	a.reload_total = maxf(e.rtot, 0.1)
	a.using = e.us
	var h: int = e.held
	var want := ""
	if h == 0:
		want = "pickaxe"
	elif h >= 2 and h - 2 < item_ids.size():
		want = String(Items.DEFS[item_ids[h - 2]].asset)
	if want != a.net_held:
		a.net_held = want
		a.body.hold(want)
	var em: int = e.emote
	var ename := "" if em == 0 or em - 1 >= emote_ids.size() else String(emote_ids[em - 1])
	if ename != a.emote:
		a.emote = ename
		a.emote_t = 0.0
	var bpi: int = e.bp
	a.build_piece = "" if bpi == 0 or bpi - 1 >= Structures.PIECES.size() else String(Structures.PIECES[bpi - 1])
	a.visible = true


# ----------------------------------------------------------------------------- client -> host

func _pack_input(a: Actor) -> PackedByteArray:
	var s := StreamPeerBuffer.new()
	s.put_float(a.global_position.x)
	s.put_float(a.global_position.y)
	s.put_float(a.global_position.z)
	s.put_16(clampi(int(a.velocity.x * 20.0), -32000, 32000))
	s.put_16(clampi(int(a.velocity.y * 20.0), -32000, 32000))
	s.put_16(clampi(int(a.velocity.z * 20.0), -32000, 32000))
	s.put_16(int(wrapf(a.aim_yaw, -PI, PI) / PI * 32000.0))
	s.put_16(int(clampf(a.aim_pitch, -1.6, 1.6) / 1.6 * 32000.0))
	s.put_u8(a.state)
	var fl := 0
	fl |= 1 if a.crouched else 0
	fl |= 2 if a.sliding else 0
	fl |= 4 if a.is_on_floor() else 0
	fl |= 8 if a.launched else 0
	fl |= 16 if a.tsprint else 0
	fl |= 32 if a.zip != null else 0
	fl |= 64 if (a.in_fire or a.net_build_fire) else 0
	fl |= 128 if a.in_sprint else 0
	fl |= 256 if a.in_tsprint else 0
	fl |= 512 if a.in_jump_held else 0
	fl |= 1024 if a.in_dive else 0
	s.put_u16(fl)
	s.put_u8(int(clampf(a.tsprint_k, 0.0, 1.0) * 255.0))
	s.put_u8(NONE_U8 if a.hurdle_t < 0.0 else int(clampf(a.hurdle_t / maxf(a.hurdle_dur, 0.01), 0.0, 1.0) * 250.0))
	s.put_u8(NONE_U8 if a.mantle_t < 0.0 else int(clampf(a.mantle_t / maxf(a.mantle_dur, 0.01), 0.0, 1.0) * 250.0))
	s.put_8(int(clampf(a.in_move.x, -1.0, 1.0) * 127.0))
	s.put_8(int(clampf(a.in_move.y, -1.0, 1.0) * 127.0))
	if a.in_jump:
		jump_n = (jump_n + 1) & 255
	if a.in_crouch:
		crouch_n = (crouch_n + 1) & 255
	s.put_u8(a.net_fire_edge & 255)
	s.put_u8(jump_n)
	s.put_u8(crouch_n)
	var ap: Vector3 = game.player_aim_point() if game.controller != null and game.controller.cam != null else a.global_position
	s.put_float(ap.x)
	s.put_float(ap.y)
	s.put_float(ap.z)
	return s.data_array


@rpc("any_peer", "unreliable_ordered")
func _r_input(data: PackedByteArray) -> void:
	if not game.net_host:
		return
	var br = brains.get(multiplayer.get_remote_sender_id())
	if br:
		br.on_packet(data)


# ----------------------------------------------------------------------------- commands (client -> host)

func send_cmd(cname: String, args: Array) -> void:
	rpc_id(1, "_r_cmd", cname, args)


@rpc("any_peer", "reliable")
func _r_cmd(cname: String, args: Array) -> void:
	if not game.net_host:
		return
	var pid := multiplayer.get_remote_sender_id()
	var a := actor_of_peer(pid)
	if a == null or not a.alive() and cname != "noop":
		return
	cmd_log.append(cname)
	game.exec_cmd(a, cname, args)
	priv_dirty[pid] = true


# ----------------------------------------------------------------------------- private state (host -> the owner)

func _send_priv(a: Actor) -> void:
	var d := {"sl": a.slots, "ac": a.active, "am": a.ammo, "mt": a.mats, "gd": a.gold, "hp": a.hp, "sh": a.shield, "rl": a.reloading,
			"rt": a.reload_total, "us": a.using, "ut": a.use_total, "usl": a.use_slot, "bp": a.build_piece, "bm": a.build_mat, "fc": a.fire_cd,
			"bl": a.bloom, "k": a.kills, "pl": a.placement, "em": a.emote, "dead": not a.alive(), "ch": a.charge, "gl": game.hired != null}
	rpc_id(a.peer_id, "_r_priv", d)


@rpc("authority", "unreliable_ordered")
func _r_priv(d: Dictionary) -> void:
	var a: Actor = game.player
	var sig_before := "%d|%s|%s" % [a.active, a.build_piece, str(a.item().get("id", "") if a.item() != null else "")]
	a.slots = d.sl
	a.active = d.ac
	for k in d.am:
		a.ammo[k] = d.am[k]
	a.mats = d.mt
	a.gold = d.gd
	a.hp = d.hp
	a.shield = d.sh
	a.reloading = d.rl
	a.reload_total = d.rt
	a.using = d.us
	a.use_total = d.ut
	a.use_slot = d.usl
	a.build_piece = d.bp
	a.build_mat = d.bm
	a.fire_cd = d.fc
	a.bloom = d.bl
	a.kills = d.k
	a.placement = d.pl
	a.charge = d.ch
	if d.em != a.emote:
		if d.em == "":
			a.stop_emote()
		else:
			a.emote = d.em
			a.emote_t = 0.0
			a.body.hold("")
	if d.dead:
		a.net_set_dead()
	var sig_after := "%d|%s|%s" % [a.active, a.build_piece, str(a.item().get("id", "") if a.item() != null else "")]
	if sig_after != sig_before:
		a._refresh_held()


# ----------------------------------------------------------------------------- fx and events (host -> clients)

func fx_add(e: Array) -> void:
	if fx_q.size() < 200:
		fx_q.append(e)


@rpc("authority", "unreliable_ordered")
func _r_fx(q: Array) -> void:
	for e in q:
		match e[0]:
			"s":
				game.audio.play(e[1], e[2])
			"t":
				game.fx_tracer(e[1], e[2], e[3])


func ev(ename: String, args: Array) -> void:
	if game.net_host and multiplayer.get_peers().size() > 0:
		rpc("_r_ev", ename, args)


func ev_to(peer: int, ename: String, args: Array) -> void:
	if game.net_host and peer > 1 and multiplayer.get_peers().has(peer):
		rpc_id(peer, "_r_ev", ename, args)


@rpc("authority", "reliable")
func _r_ev(ename: String, args: Array) -> void:
	_handle(ename, args)


func _actor_at(i: int) -> Actor:
	return all[i] if i >= 0 and i < all.size() else null


var test_counts := {}


func _handle(ename: String, a: Array) -> void:
	## World events as they arrive on a client. Each one calls the same function the host ran, with its mutation skipped.
	test_counts[ename] = int(test_counts.get(ename, 0)) + 1
	var S: Structures = game.structures
	match ename:
		"announce":
			game.announce_text = a[0]
			game.announce_time = game.match_time
		"feed":
			game.kill_feed.append({"text": a[0], "time": game.match_time, "mine": int(a[1]) == game.my_idx or int(a[2]) == game.my_idx})
			if game.kill_feed.size() > 6:
				game.kill_feed.pop_front()
		"dmg":
			game.audio.play("hit_marker", Vector3.INF)
			if game.hud:
				game.hud.add_damage_number(a[0], a[1], a[2], a[3], a[4])
			if int(a[5]) >= 0 and int(a[5]) < game.bosses.list.size():
				game.bosses.list[int(a[5])].dmg_t = game.match_time
		"arc":
			if game.hud:
				game.hud.add_damage_arc(a[0])
		"ui_sfx":
			game.audio.play(a[0], Vector3.INF)
		"pickup":
			if game.hud:
				game.hud.add_pickup_note(a[0])
			game.audio.play("pickup", Vector3.INF)
		"matnote":
			if game.hud:
				game.hud.add_mat_note(a[0], a[1], a[2])
		"snum":
			if game.hud:
				game.hud.add_structure_number(a[0], a[1])
		"pk_add":
			game.spawn_pickup(a[1], a[2], int(a[0]), true)
		"pk_rm":
			var p = game.pickup_by_id.get(int(a[0]))
			if p != null:
				game.remove_pickup(p)
		"ct_open":
			if int(a[0]) >= 0 and int(a[0]) < game.containers.size():
				game.open_container(game.containers[int(a[0])], null, true)
		"vault_open":
			game.bosses.net_open_vault(String(a[0]))
		"st_new":
			S.net_spawn(int(a[0]), String(a[1]), a[2], _actor_at(int(a[3])))
		"st_hp":
			var e = S.by_id.get(int(a[0]))
			if e != null and not e.dead:
				e.hp = float(a[1])
				S._wobble(e)
		"st_del":
			var e2 = S.by_id.get(int(a[0]))
			if e2 != null and not e2.dead:
				S.destroy(e2)
		"st_edit":
			var e3 = S.by_id.get(int(a[0]))
			if e3 != null and not e3.dead:
				e3.edit = a[1]
				e3.dir = int(a[2])
				S._rebuild(e3)
		"drop":
			game.events.spawn_drop(a[0])
		"pad":
			game.events.place_pad(a[0])
		"proj":
			var o := _actor_at(int(a[1]))
			match String(a[0]):
				"r":
					game.spawn_rocket(o, a[2], a[3], a[4], a[5])
				"g":
					game.spawn_grenade(o, a[2], a[3], a[4], a[5])
				"o":
					game.spawn_shockwave(o, a[2], a[3], a[4])
		"knock":
			game.player.receive_knock(a[0], a[1])
		"set_pos":
			game.player.global_position = a[0]
			game.player.velocity = a[1]
		"stun":
			game.player.stun_t = maxf(game.player.stun_t, float(a[0]))
		"grasp_pull":
			game.player.grasp_to = a[0]
			game.player.grasp_t = 0.0
			game.player.grasp_pull = true
		"npc_hired":
			game.net_npc_hired(int(a[0]))
		"elim":
			var pl: Actor = game.player
			pl.placement = int(a[1])
			game.player_survived = float(a[2])
			pl.net_set_dead()
			game._record_career()
			game.controller.on_player_eliminated(_actor_at(int(a[0])))
		"over":
			game.over = true
			game.over_time = game.match_time
			game.winner = _actor_at(int(a[0]))
			if game.player.alive():
				game.player_survived = game.match_time
				game.audio.play("victory", Vector3.INF)
				game._record_career()
			print("MATCH_OVER_CLIENT place=%d" % game.player.placement)
		"over_stats":
			game.player.placement = int(a[0])
			game.player.kills = int(a[1])
			game.player_damage = float(a[2])


# ----------------------------------------------------------------------------- disconnects and end of match

func on_peer_left(id: int) -> void:
	## A client dropped: its character is eliminated on the host (bots and the other player carry on).
	var a := actor_of_peer(id)
	brains.erase(id)
	if a != null and a.alive() and is_instance_valid(a):
		game.announce("%s left the match" % a.display_name)
		a.remote_sim = false
		a.die(null)


func on_eliminated(victim: Actor, killer: Actor) -> void:
	if victim.peer_id > 1:
		ev_to(victim.peer_id, "elim", [all.find(killer), victim.placement, game.match_time])
		_send_priv(victim)


func on_match_over() -> void:
	ev("over", [all.find(game.winner)])
	for a in game.humans:
		if a.peer_id > 1:
			ev_to(a.peer_id, "over_stats", [a.placement, a.kills, a.net_damage])


func test_send(k: String, v) -> void:
	rpc("_r_test", k, v)


@rpc("any_peer", "reliable")
func _r_test(k: String, v) -> void:
	test_in[k] = v
