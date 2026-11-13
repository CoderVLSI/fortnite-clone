## Host side of a remote human: attached to their Actor (a normal player slot). It applies what the client reports every
## ~33 ms (position, velocity, aim, state flags: the client owns its movement) and the controller inputs, so the host's
## copy fires, builds, heals and takes damage exactly like the local player's. Movement itself is not simulated here.
extends Node

const TELEPORT_LIMIT := 15.0            # metres per update on the ground before a position is refused
var game: Node
var a: Actor
var peer_id := 0
var last_edge := 0
var last_jump := 0
var last_crouch := 0
var fire_held := false
var use_held := false
var pending_fire := false
var have_input := false
var refused := 0
var last_pkt_t := 0.0


func setup(g: Node, actor: Actor, pid: int) -> void:
	game = g
	a = actor
	peer_id = pid
	a.peer_id = pid
	a.remote_sim = true
	a.is_player = true
	last_pkt_t = Time.get_ticks_msec() / 1000.0


## Client -> host packet; the layout is in net_match.gd (_pack_input).
func on_packet(b: PackedByteArray) -> void:
	if a == null or not is_instance_valid(a) or not a.alive():
		return
	var s := StreamPeerBuffer.new()
	s.data_array = b
	var pos := Vector3(s.get_float(), s.get_float(), s.get_float())
	var vel := Vector3(s.get_16(), s.get_16(), s.get_16()) / 20.0
	var yaw := float(s.get_16()) / 32000.0 * PI
	var pitch := float(s.get_16()) / 32000.0 * 1.6
	var st := s.get_u8()
	var fl := s.get_u16()
	var tk := float(s.get_u8()) / 255.0
	var hur := s.get_u8()
	var man := s.get_u8()
	var mv := Vector2(float(s.get_8()) / 127.0, float(s.get_8()) / 127.0)
	var edge := s.get_u8()
	var jn := s.get_u8()
	var cn := s.get_u8()
	var aim := Vector3(s.get_float(), s.get_float(), s.get_float())
	last_pkt_t = Time.get_ticks_msec() / 1000.0
	have_input = true
	# inputs
	a.aim_yaw = yaw
	a.aim_pitch = pitch
	a.in_move = mv
	a.in_sprint = fl & (1 << 7) != 0
	a.in_tsprint = fl & (1 << 8) != 0
	a.in_jump_held = fl & (1 << 9) != 0
	a.in_dive = fl & (1 << 10) != 0
	fire_held = fl & (1 << 6) != 0
	use_held = fl & (1 << 11) != 0
	if edge != last_edge:
		last_edge = edge
		pending_fire = true
	if jn != last_jump:
		last_jump = jn
		a.in_jump = true
	if cn != last_crouch:
		last_crouch = cn
		a.in_crouch = true
	a.net_aim = aim
	# movement: the client's word, within reason
	var cur: int = a.state
	if cur == Actor.State.BLIMP or cur == Actor.State.DEAD:
		return                                           # the host decides these (the jump arrives as a command)
	var new_state := clampi(st, 0, Actor.State.SWIM)
	if new_state == Actor.State.BLIMP or new_state == Actor.State.DEAD:
		new_state = cur
	var zip_on := fl & (1 << 5) != 0
	var step := pos.distance_to(a.global_position)
	var free_move: bool = new_state != Actor.State.GROUND or cur != Actor.State.GROUND or zip_on or a.stun_t > 0.0 or a.knock_t > 0.0
	if step > TELEPORT_LIMIT and not free_move:
		refused += 1
		if game.nm:
			game.nm.ev_to(peer_id, "set_pos", [a.global_position, Vector3.ZERO])
		return
	if a.stun_t > 0.0 or a.grasp_pull:
		return                                           # being yanked by the host: ignore the client's position for now
	a.global_position = pos
	a.velocity = vel
	a.state = new_state as Actor.State
	a.crouched = fl & 1 != 0
	a.sliding = fl & 2 != 0
	a.net_floor = fl & 4 != 0
	a.launched = fl & 8 != 0
	a.tsprint = fl & 16 != 0
	a.tsprint_k = tk
	a.zip = {} if zip_on else null
	a.set_meta("force_floor", a.net_floor)
	a.hurdle_dur = 1.0
	a.hurdle_t = -1.0 if hur == 255 else float(hur) / 250.0
	a.mantle_dur = 1.0
	a.mantle_t = -1.0 if man == 255 else float(man) / 250.0
	a._set_height(Actor.KNOCK_H if a.knocked else (Actor.CROUCH_H if (a.crouched or a.sliding) else Actor.STAND_H))


func _physics_process(delta: float) -> void:
	if a == null or not a.alive() or not have_input:
		return
	if game.duos:
		game.try_revive(a, use_held)                        # Duos: the host runs the revive for this human, every tick, from their held use key
	# the trigger
	var it = a.item()
	if game.warming_up() or a.state == Actor.State.BLIMP or a.state == Actor.State.DEAD:
		a.in_fire = false
		pending_fire = false
		return
	if a.build_piece != "":
		a.in_fire = false
		pending_fire = false
		a.build_cd = maxf(a.build_cd - delta, 0.0)
		if fire_held and a.build_cd <= 0.0:
			if game.structures.place(a):
				a.build_cd = 0.09
		return
	var continuous: bool = it == null or Items.is_mythic(it) or bool(Items.def(it).get("auto", false))
	if continuous:
		a.in_fire = fire_held
	else:
		if pending_fire:
			a.in_fire = true                                 # stays up until the shot goes off, like a click during the cooldown
			pending_fire = false
		elif not fire_held and a.burst_left <= 0:
			a.in_fire = false
