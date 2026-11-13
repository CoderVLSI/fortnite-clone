## A combatant: the player or a bot. Movement states (blimp, skydive, glide, ground), health and shield,
## the five-slot inventory, ammo, firing, reloading and consumables. Input comes from player.gd or bot.gd.
class_name Actor
extends CharacterBody3D

enum State { BLIMP, SKYDIVE, GLIDE, GROUND, DEAD, SWIM }

const WALK := 5.2
const SPRINT := 7.6
const TSPRINT := 9.5                     # tactical sprint (Shift): gun lowered, no firing
const TSPRINT_WIND := 0.35               # seconds to wind up to full tactical speed
const HURDLE_MIN := 0.5                  # obstacles this high (m) are vaulted at a run, not stepped or mantled
const HURDLE_MAX := 1.3
const JUMP := 8.2
const GRAVITY := 24.0
const GLIDER_HEIGHT := 42.0
const EYE := Vector3(0, 1.55, 0)
const PICKAXE_DAMAGE := 20.0
const CROUCH_SPEED := 3.0
const SWIM_SPEED := 3.6
const STAND_H := 1.7                     # collision height: a little under the 1.8 m model, so house doors with a sill fit
const CROUCH_H := 1.2
const SWIM_IN := 1.3                     # water this deep at the feet: start swimming
const SWIM_OUT := 1.0                    # shallower than this with ground underfoot: walk again
const FLOAT_DEPTH := 1.25                # feet this far under the surface while swimming
const MANTLE_MIN := 0.75
const MANTLE_MAX := 2.3

var game: Node
var display_name := "Player"
var is_player := false
var state := State.BLIMP
var hp := 100.0
var shield := 0.0
var kills := 0
var slots: Array = [null, null, null, null, null]
var active := -1                         # 0..4 = hotbar slot, -1 = pickaxe
var ammo := {"light": 0, "medium": 0, "heavy": 0, "shells": 0, "rockets": 0, "none": 999}   # "none": the pool cooldown mythics point at
var body: Character
var spread_mul := 1.0                    # bots: aim error on top of the weapon spread
var placement := 0
var is_npc := false                     # a character for hire, not a player
var hired := false
var is_boss := false                    # a boss guarding a lair (bosses.gd): not a player, no placement
var ever_armed := false
var mats := {"wood": 0, "brick": 0, "metal": 0}
var gold := 0                            # gold bars: spent at upgrade benches and on hiring characters
var build_piece := ""                    # "" = not building, else wall / floor / stairs / cone
var build_mat := "wood"
var build_cd := 0.0
var crouched := false
var sliding := false
var slide_t := 0.0
var in_crouch := false                   # one-shot: crouch key pressed
var mantle_t := -1.0                     # >= 0 while pulling up onto a ledge
var mantle_from := Vector3.ZERO
var mantle_to := Vector3.ZERO
var mantle_dur := 0.45
var jump_air_t := 99.0                   # seconds since the last jump, for mantling mid-jump
var foam_t := 0.0
var shape_node: CollisionShape3D
var zip = null                           # {line, t, dir} while riding a zip line
var launched := false
var emote := ""                        # emote being performed (see Character.EMOTES)
var emote_t := 0.0
var bloom := 0.0                         # extra spread from firing quickly; decays                    # rising from a launch pad

# control inputs, written by the player or the bot brain every physics tick
var in_move := Vector2.ZERO              # x = right, y = forward, relative to aim_yaw
var in_sprint := false
var in_tsprint := false                  # tactical sprint wanted (player: Shift held; bots may set it too)
var in_jump_held := false                # jump key is down (mid-air it pulls you up onto a ledge)
var tsprint := false                     # tactical sprint under way
var tsprint_k := 0.0                     # 0..1 wind-up blend, for the animation, camera and speed
var tsprint_block := false               # firing, reloading or using ended it: Shift must be released first
var hurdle_t := -1.0                     # >= 0 while vaulting over a low obstacle
var hurdle_from := Vector3.ZERO
var hurdle_to := Vector3.ZERO
var hurdle_dur := 0.45
var hurdle_arc := 0.5
var hurdle_vel := Vector3.ZERO
var run_target := 0.0                    # the speed the ground controls are asking for (survives hitting a wall)
var mantle_carry := 2.0                  # horizontal speed kept when the mantle ends
var in_jump := false
var in_fire := false
var in_dive := false
var aim_yaw := 0.0
var aim_pitch := 0.0

var fire_cd := 0.0
var burst_left := 0                      # shots still to come in the burst under way
var reloading := 0.0
var using := 0.0
var use_total := 0.0
var use_slot := -1
var last_hit_from := Vector3.ZERO
var last_hit_time := -99.0
var last_attacker: Actor
var storm_time := 0.0
var fall_start := 0.0
var step_dist := 0.0
var pickup_cd := 0.0
# LAN multiplayer (all inert in single player)
var peer_id := 0                         # > 1: a remote human, simulated on the host from their inputs (remote_brain.gd)
var remote_sim := false                  # host: this human's movement comes from the client, the host runs combat/inventory
var net_puppet := false                  # client: driven by host snapshots, no simulation
var net_floor := true                    # remote_sim: the client says the feet are on the ground
var net_aim := Vector3.INF               # remote_sim: the point under the client's crosshair
var net_fire_edge := 0                   # client counts trigger pulls so the host can fire semi-auto guns once per click
var net_damage := 0.0                    # damage a remote human has dealt (their summary)
var net_held := ""                       # puppet: the item id in hand, to skip rebuilding the model
var net_build_fire := false              # client: the trigger is held while building (in_fire is off then)


func setup(g: Node, nm: String, player: bool, outfit: Color, accent: Color, body_id := "Soldier") -> void:
	game = g
	display_name = nm
	is_player = player
	collision_layer = 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(50)
	floor_snap_length = 0.4
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = STAND_H
	cs.shape = cap
	cs.position = Vector3(0, STAND_H / 2.0, 0)
	add_child(cs)
	shape_node = cs
	body = Character.new()
	add_child(body)
	body.build(outfit, accent, [Color(0.95, 0.78, 0.62), Color(0.78, 0.56, 0.4), Color(0.5, 0.34, 0.24)][nm.hash() % 3], body_id)
	body.hold("pickaxe")


func alive() -> bool:
	return state != State.DEAD


func is_head_point(p: Vector3) -> bool:
	## True when a point on this actor (a hit or what the crosshair is on) is on the head.
	return p.y > eye().y - 0.12


func eye() -> Vector3:
	return global_position + Vector3(0, 1.05 if (crouched or sliding) else EYE.y, 0)


func centre() -> Vector3:
	## Where to aim at this actor's body.
	return global_position + Vector3(0, 0.62 if (crouched or sliding) else 1.15, 0)


func aim_dir() -> Vector3:
	return Vector3(-sin(aim_yaw) * cos(aim_pitch), sin(aim_pitch), -cos(aim_yaw) * cos(aim_pitch))


func height_above_ground() -> float:
	return global_position.y - maxf(game.terrain.height(global_position.x, global_position.z), 0.0)


# ----------------------------------------------------------------------------- movement

func _physics_process(delta: float) -> void:
	if net_puppet:
		_puppet_tick(delta)
		return
	if state == State.DEAD:
		return
	if not game.profile:
		_tick(delta)
		return
	var t0 := Time.get_ticks_usec()
	_tick(delta)
	game.prof_add("actor", Time.get_ticks_usec() - t0)


func _tick(delta: float) -> void:
	fire_cd = maxf(fire_cd - delta, 0.0)
	bloom = move_toward(bloom, 0.0, delta * 2.2)
	_mythic_tick(delta)
	if emote != "":
		_emote_tick(delta)
	if remote_sim:
		pass                                                 # the client moves this human; the host only runs combat and items
	elif mantle_t >= 0.0:
		_mantle_step(delta)
	elif web_state != 0:
		_web_step(delta)
	elif grasp_pull:
		_grasp_pull_step(delta)
	elif zip != null:
		_zip_step(delta)
	else:
		match state:
			State.BLIMP:
				global_position = game.blimp_seat()
				velocity = Vector3.ZERO
				if in_jump:
					jump_from_blimp()
			State.SKYDIVE:
				if launched and velocity.y > 0.0:          # still rising from a launch pad
					var w := _wish() * 12.0
					velocity.x = move_toward(velocity.x, w.x, 20.0 * delta)
					velocity.z = move_toward(velocity.z, w.z, 20.0 * delta)
					velocity.y -= 22.0 * delta
					move_and_slide()
				else:
					launched = false
					var fall := -52.0 if in_dive else -30.0
					var steer := 9.0 if in_dive else 16.0
					_air_move(delta, fall, steer, 3.0)
					if height_above_ground() <= GLIDER_HEIGHT:
						state = State.GLIDE
						game.sfx("glide", global_position)
			State.GLIDE:
				_air_move(delta, -7.5, 14.0, 4.0)
				if depth() > SWIM_IN:
					_enter_water()
				elif is_on_floor():
					state = State.GROUND
					fall_start = global_position.y
			State.GROUND:
				_ground_move(delta)
			State.SWIM:
				_swim_move(delta)
	body.rotation.y = lerp_angle(body.rotation.y, aim_yaw, clampf(delta * 14.0, 0.0, 1.0))
	body.animate(delta, self)
	if game.net_client:                                       # the host runs the weapon and the items; just count down for the HUD
		reloading = maxf(reloading - delta, 0.0)
		using = maxf(using - delta, 0.0)
		return
	if state == State.GROUND and mantle_t < 0.0:
		_combat(delta)
	else:
		burst_left = 0
		if using > 0.0:
			cancel_use()


func _puppet_tick(delta: float) -> void:
	## A remote actor on a client: the snapshot sets position and fields, this only turns the body and animates it.
	if emote != "":
		emote_t += delta
	body.rotation.y = lerp_angle(body.rotation.y, aim_yaw, clampf(delta * 14.0, 0.0, 1.0))
	body.animate(delta, self)


func _floor() -> bool:
	## Standing on something: the client's word for a remote human on the host, physics for everyone else.
	return net_floor if remote_sim else is_on_floor()


func _cam_aim() -> Vector3:
	## The point under the crosshair: the host's camera for the local player, the client's reported point for a remote human.
	if remote_sim and net_aim != Vector3.INF:
		return net_aim
	return game.player_aim_point()


func net_set_dead() -> void:
	## A client shows an elimination the host decided (no drops, no scoring here).
	if state == State.DEAD:
		return
	hp = 0.0
	shield = 0.0
	_mythic_clear()
	state = State.DEAD
	collision_layer = 0
	collision_mask = 0
	body.visible = false
	build_piece = ""


func start_emote(name: String) -> void:
	if state != State.GROUND or not _floor() or not Character.EMOTES.has(name):
		return
	sliding = false
	set_crouched(false)
	cancel_use()
	reloading = 0.0
	build_piece = ""
	emote = name
	emote_t = 0.0
	body.hold("")


func stop_emote() -> void:
	if emote == "":
		return
	emote = ""
	_refresh_held()


func _emote_tick(delta: float) -> void:
	## Moving, jumping, firing or leaving the ground ends an emote; one-shot emotes end on their own.
	emote_t += delta
	var length: float = Character.EMOTES[emote].length
	if in_move.length() > 0.2 or in_jump or in_fire or in_crouch or state != State.GROUND or (length > 0.0 and emote_t >= length):
		stop_emote()


func launch(up: float) -> void:
	## Thrown into the air by a launch pad; the glider opens on the way down.
	zip = null
	sliding = false
	crouched = false
	_set_height(STAND_H)
	cancel_use()
	_web_cancel()
	grasp_pull = false
	state = State.SKYDIVE
	launched = true
	velocity = Vector3(velocity.x * 0.5, up, velocity.z * 0.5)
	global_position += Vector3(0, 0.3, 0)


func start_zip(line: Dictionary, from_end: float) -> void:
	zip = {"line": line, "t": from_end, "dir": 1.0 if from_end < 0.5 else -1.0}
	sliding = false
	crouched = false
	_set_height(STAND_H)
	velocity = Vector3.ZERO


func _zip_step(delta: float) -> void:
	var z: Dictionary = zip.line
	zip.t = clampf(float(zip.t) + float(zip.dir) * game.events.ZIP_SPEED * delta / float(z.length), 0.0, 1.0)
	var p: Vector3 = game.events.cable_point(z, zip.t)
	var ahead: Vector3 = game.events.cable_point(z, clampf(float(zip.t) + float(zip.dir) * 0.01, 0.0, 1.0))
	var dir := (ahead - p).normalized()
	global_position = p - Vector3(0, 1.95, 0)              # hanging under the cable
	velocity = dir * game.events.ZIP_SPEED
	var done: bool = (zip.dir > 0.0 and zip.t >= 1.0) or (zip.dir < 0.0 and zip.t <= 0.0)
	if in_jump or done:
		in_jump = false
		zip = null
		state = State.GROUND
		velocity = Vector3(dir.x, 0, dir.z) * 6.0 + Vector3(0, 3.0, 0)
		fall_start = global_position.y
		jump_air_t = 99.0
	if state == State.GROUND and zip != null:
		_combat(delta)


func deploy_glider() -> void:
	## Open the glider early (it opens by itself at GLIDER_HEIGHT).
	if state != State.SKYDIVE:
		return
	state = State.GLIDE
	game.sfx("glide", global_position)


func jump_from_blimp() -> void:
	if state != State.BLIMP:
		return
	if game.net_client and self == game.player:
		game.cmd(self, "jump")                          # the host decides; this device also starts falling at once
	state = State.SKYDIVE
	velocity = game.blimp_velocity() * 0.5 + Vector3(0, -6, 0)
	in_jump = false


func _wish() -> Vector3:
	var f := Vector3(-sin(aim_yaw), 0, -cos(aim_yaw))
	var r := Vector3(cos(aim_yaw), 0, -sin(aim_yaw))
	var w := f * in_move.y + r * in_move.x
	return w.normalized() if w.length() > 1.0 else w


func _air_move(delta: float, fall: float, speed: float, accel: float) -> void:
	var w := _wish() * speed
	velocity.x = move_toward(velocity.x, w.x, accel * speed * delta)
	velocity.z = move_toward(velocity.z, w.z, accel * speed * delta)
	velocity.y = move_toward(velocity.y, fall, 40.0 * delta)
	move_and_slide()


func depth() -> float:
	## How far the feet are below the water surface here (negative when dry or above it).
	var s: float = game.terrain.water_surface(global_position.x, global_position.z)
	return s - global_position.y if s > -999.0 else -1.0


# ----------------------------------------------------------------------------- walking, crouching, sliding

func _ground_move(delta: float) -> void:
	if hurdle_t >= 0.0:
		_hurdle_step(delta)
		in_jump = false
		return
	if in_crouch:
		in_crouch = false
		_crouch_pressed()
	_update_tsprint(delta)
	if sliding:
		_slide(delta)
	else:
		var speed := WALK
		if crouched:
			speed = CROUCH_SPEED
		elif tsprint:
			speed = lerpf(SPRINT, TSPRINT, tsprint_k)
		elif in_sprint and in_move.y > 0.1 and using <= 0.0:
			speed = SPRINT
		if using > 0.0:
			speed *= 0.6
		run_target = speed * minf(_wish().length(), 1.0)
		var w := _wish() * speed
		var acc := 60.0 if is_on_floor() else 14.0
		velocity.x = move_toward(velocity.x, w.x, acc * delta)
		velocity.z = move_toward(velocity.z, w.z, acc * delta)
	if is_on_floor():
		if in_jump:
			if not _try_hurdle() and not _try_mantle(MANTLE_MAX):
				sliding = false
				if crouched:
					set_crouched(false)
				velocity.y = JUMP
				game.sfx("jump", global_position)
				jump_air_t = 0.0
		fall_start = global_position.y
	else:
		velocity.y -= GRAVITY * delta
		jump_air_t += delta
		# jumping into a ledge (or holding jump while falling past one) pulls you up onto it
		var fresh := jump_air_t < 0.75
		if (fresh or in_jump or in_jump_held) and in_move.y > 0.3 and _try_mantle(MANTLE_MAX, fall_start if fresh else INF):
			in_jump = false
			return
	in_jump = false
	var was_air := not is_on_floor()
	if not was_air and not sliding and is_on_wall():           # only after running into something
		_step_up(Vector3(velocity.x, 0, velocity.z))
	move_and_slide()
	if is_on_floor():
		if was_air:
			var drop := fall_start - global_position.y
			if drop > 9.0:
				hit((drop - 9.0) * 7.0, null, true, global_position)
		fall_start = global_position.y
		jump_air_t = 99.0
	_audio_steps(delta, was_air)
	if depth() > SWIM_IN:
		_enter_water()


const STEP_H := 0.45                     # door sills, porch steps and stair lips are walked over, not jumped


func _step_up(v: Vector3) -> void:
	## Walking into a low ledge: lift onto it if there is room. The lift is the ledge's own height, measured
	## first, so a sill under a low door frame still fits (lifting the full STEP_H would hit the frame).
	if v.length() < 0.5:
		return
	var dir := v.normalized()
	var fwd := dir * 0.32
	var xf := global_transform
	var hit := KinematicCollision3D.new()
	if not test_move(xf, fwd, hit):
		return                                         # nothing in the way
	if hit.get_normal().y > 0.7:
		return                                         # a slope the floor handling copes with
	var probe := global_position + dir * 0.45
	var top: Dictionary = game.ray(probe + Vector3(0, STEP_H + 0.05, 0), probe - Vector3(0, 0.05, 0), self, 1)
	if top.is_empty() or (top.normal as Vector3).y < 0.35:          # bevelled tops count
		return
	var rise: float = top.position.y - global_position.y
	if rise <= 0.03 or rise > STEP_H:
		return
	var up := Vector3(0, rise + 0.03, 0)
	if test_move(xf, up):
		return                                         # no headroom
	if test_move(xf.translated(up), fwd):
		return                                         # a wall, not a step
	global_position += up + fwd * 0.5


func _audio_steps(delta: float, was_air: bool) -> void:
	## Landing thud and a footstep every ~2 m of ground travelled (sound only; cheap early-outs).
	if not is_on_floor() or not game.audio.enabled:
		return
	if was_air:
		game.sfx("land", global_position)
		return
	var hv := Vector2(velocity.x, velocity.z).length()
	if hv < 1.5 or sliding:
		return
	step_dist += hv * delta
	if step_dist >= (1.6 if crouched else 2.1):
		step_dist = 0.0
		game.audio.footstep(self, hv)


func _crouch_pressed() -> void:
	if not is_on_floor():
		return
	if sliding:
		sliding = false
		crouched = true
		return
	var hv := Vector2(velocity.x, velocity.z).length()
	if not crouched and hv > 6.2 and in_move.y > 0.3:
		# sprinting: slide instead, with a small push
		sliding = true
		slide_t = 0.0
		_set_height(CROUCH_H)
		var dir := Vector3(velocity.x, 0, velocity.z).normalized()
		var sp := maxf(hv, 9.0)
		if tsprint_k > 0.4:
			sp = maxf(hv * 1.12, 10.5)                   # sliding out of a tactical sprint keeps the extra speed
		velocity.x = dir.x * sp
		velocity.z = dir.z * sp
		return
	set_crouched(not crouched)


func set_crouched(v: bool) -> void:
	if v == crouched:
		return
	if not v and not _headroom():
		return                                          # no room to stand up here
	crouched = v
	_set_height(CROUCH_H if v else STAND_H)


func _set_height(h: float) -> void:
	var cap := shape_node.shape as CapsuleShape3D
	if absf(cap.height - h) < 0.01:
		return
	cap.height = h
	shape_node.position.y = h / 2.0


func _headroom() -> bool:
	return game.ray(global_position + Vector3(0, 1.1, 0), global_position + Vector3(0, STAND_H + 0.05, 0), self, 1).is_empty()


func _slide(delta: float) -> void:
	## Gravity along the slope speeds the slide up downhill; friction slows it on the flat.
	slide_t += delta
	var n := get_floor_normal() if is_on_floor() else Vector3.UP
	var g := Vector3(0, -GRAVITY, 0)
	var along := g - n * g.dot(n)
	var hv := Vector3(velocity.x, 0, velocity.z)
	hv += Vector3(along.x, 0, along.z) * delta * 1.1
	var spd := maxf(hv.length() - 3.2 * delta, 0.0)
	var w := _wish()
	if spd > 0.1:
		var cur := hv.normalized()
		if w.length() > 0.2:
			cur = cur.lerp(w.normalized(), clampf(delta * 1.4, 0.0, 1.0)).normalized()
		hv = cur * minf(spd, 17.0)
	velocity.x = hv.x
	velocity.z = hv.z
	if (spd < 3.2 and slide_t > 0.3) or slide_t > 6.0:
		sliding = false
		crouched = true                                  # a slide always ends in a crouch


# ----------------------------------------------------------------------------- tactical sprint and hurdling

func _update_tsprint(delta: float) -> void:
	if not in_tsprint:
		tsprint_block = false
	elif in_fire or burst_left > 0 or reloading > 0.0 or using > 0.0:
		tsprint_block = true                            # firing, reloading and using items end it
	var want := in_tsprint and not tsprint_block and in_move.y > 0.3 and not crouched and not sliding \
			and build_piece == "" and emote == "" and (is_on_floor() or tsprint)
	tsprint = want
	tsprint_k = move_toward(tsprint_k, 1.0 if want else 0.0, delta / (TSPRINT_WIND if want else 0.2))


func _try_hurdle() -> bool:
	## Jump while running at a low, thin obstacle (HURDLE_MIN..HURDLE_MAX high) with floor beyond it: vault over in one arc.
	var hv := Vector3(velocity.x, 0, velocity.z)
	if hv.length() < 4.5 or in_move.y < 0.2 or crouched or sliding:
		return false
	var fwd := hv.normalized()
	var feet := global_position
	var wall := {}
	for hgt in [0.25, 0.45, 0.7]:
		var o: Vector3 = feet + Vector3(0, hgt, 0)
		var r: Dictionary = game.ray(o, o + fwd * 1.3, self, 1)
		if not r.is_empty() and r.normal.y < 0.6:
			wall = r
			break
	if wall.is_empty():
		return false
	var d := Vector2(wall.position.x - feet.x, wall.position.z - feet.z).length()
	# the top of the obstacle, and how far it runs along our path
	var top := -INF
	var edge := d
	var s := d + 0.04
	while s < d + 1.7:
		var o: Vector3 = feet + fwd * s + Vector3(0, HURDLE_MAX + 0.4, 0)
		var r: Dictionary = game.ray(o, o - Vector3(0, HURDLE_MAX + 0.4 - 0.1, 0), self, 1)
		if r.is_empty() or r.normal.y < 0.7:
			break
		if top == -INF:
			top = r.position.y
			var h0: float = top - feet.y
			if h0 < HURDLE_MIN or h0 > HURDLE_MAX:
				return false
		elif absf(r.position.y - top) > 0.12:
			break
		edge = s + 0.08
		s += 0.08
	if top == -INF or edge - d > 1.45:
		return false                                    # not an obstacle, or too thick to clear: mantle instead
	# floor to land on, 0.6 to 2 m past the far edge, with room to stand
	var land := Vector3.ZERO
	for beyond in [0.7, 1.1, 1.6]:
		var o: Vector3 = feet + fwd * (edge + beyond) + Vector3(0, HURDLE_MAX + 0.4, 0)
		var r: Dictionary = game.ray(o, Vector3(o.x, feet.y - 1.6, o.z), self, 1)
		if r.is_empty() or r.normal.y < 0.7 or r.position.y > feet.y + 0.45 or r.position.y < feet.y - 1.5:
			continue
		var q := PhysicsShapeQueryParameters3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.3
		cap.height = 1.3
		q.shape = cap
		q.collision_mask = 1
		q.transform = Transform3D(Basis.IDENTITY, r.position + Vector3(0, 0.9, 0))
		if not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty():
			continue
		land = r.position + Vector3(0, 0.03, 0)
		break
	if land == Vector3.ZERO:
		return false
	var lift := Vector3(0, top + 0.35, 0)                # nothing in the way above the obstacle
	if not game.ray(Vector3(feet.x, 0, feet.z) + lift, Vector3(land.x, 0, land.z) + lift, self, 1).is_empty():
		return false
	hurdle_from = feet
	hurdle_to = land
	var dist := Vector2(land.x - feet.x, land.z - feet.z).length()
	var spd := maxf(hv.length(), 6.5)
	hurdle_dur = clampf(dist / spd, 0.34, 0.65)
	# arc height: enough that the feet clear the top for the whole stretch over the obstacle
	var arc := 0.45
	var k0 := d / dist
	while k0 <= minf(edge / dist + 0.05, 0.95):
		var base_y := lerpf(feet.y, land.y, k0)
		arc = maxf(arc, (top + 0.28 - base_y) / maxf(4.0 * k0 * (1.0 - k0), 0.05))
		k0 += 0.05
	hurdle_arc = minf(arc, 2.0)
	hurdle_vel = fwd * hv.length()
	hurdle_t = 0.0
	sliding = false
	cancel_use()
	game.sfx("jump", global_position)
	return true


func _hurdle_step(delta: float) -> void:
	hurdle_t += delta
	var k := clampf(hurdle_t / hurdle_dur, 0.0, 1.0)
	var p := hurdle_from.lerp(hurdle_to, k)
	p.y += 4.0 * k * (1.0 - k) * hurdle_arc
	global_position = p
	velocity = hurdle_vel
	if k >= 1.0:
		hurdle_t = -1.0
		velocity = hurdle_vel                          # keeps its speed
		fall_start = global_position.y
		jump_air_t = 99.0


# ----------------------------------------------------------------------------- mantling

func _try_mantle(max_h: float, base_y := INF) -> bool:
	## Pull up onto a ledge MANTLE_MIN..max_h above base_y (the ground the jump started from).
	var fwd := _wish()
	if fwd.length() < 0.2:
		fwd = Vector3(-sin(aim_yaw), 0, -cos(aim_yaw))
	fwd = fwd.normalized()
	var feet := global_position
	var base: float = feet.y if base_y == INF else base_y
	var wall := {}
	for hgt in [0.45, 1.0, 1.6]:
		var o: Vector3 = feet + Vector3(0, hgt, 0)
		var r: Dictionary = game.ray(o, o + fwd * 1.0, self, 1)
		if not r.is_empty() and r.normal.y < 0.6:
			wall = r
			break
	if wall.is_empty():
		return false
	var d := Vector2(wall.position.x - feet.x, wall.position.z - feet.z).length()
	var probe := Vector3(feet.x, base + max_h + 0.6, feet.z) + fwd * (d + 0.5)
	var down: Dictionary = game.ray(probe, Vector3(probe.x, maxf(base + MANTLE_MIN - 0.05, feet.y + 0.15), probe.z), self, 1)
	if down.is_empty() or down.normal.y < 0.7:
		return false
	var h: float = down.position.y - feet.y
	var above_base: float = down.position.y - base
	if above_base < MANTLE_MIN or above_base > max_h:
		return false
	# the way over the edge is clear, and there is room to stand on top
	if not game.ray(feet + Vector3(0, h + 0.5, 0), down.position + Vector3(0, 0.5, 0), self, 1).is_empty():
		return false
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.2
	q.shape = cap
	q.collision_mask = 1
	q.transform = Transform3D(Basis.IDENTITY, down.position + Vector3(0, 0.68, 0))
	if not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty():
		return false
	var hv0 := Vector2(velocity.x, velocity.z).length()
	mantle_carry = clampf(maxf(hv0, run_target) * 0.75, 2.5, 6.5) if in_move.y > 0.1 else 2.0
	mantle_from = feet
	mantle_to = down.position + Vector3(0, 0.03, 0) + fwd * 0.15
	mantle_t = 0.0
	mantle_dur = 0.28 + maxf(h, 0.3) * 0.12
	velocity = Vector3.ZERO
	sliding = false
	crouched = false
	_set_height(STAND_H)
	cancel_use()
	return true


func _mantle_step(delta: float) -> void:
	mantle_t += delta
	var k := clampf(mantle_t / mantle_dur, 0.0, 1.0)
	var up := clampf(k / 0.6, 0.0, 1.0)
	var fw := clampf((k - 0.35) / 0.65, 0.0, 1.0)
	var p := mantle_from
	p.y = lerpf(mantle_from.y, mantle_to.y, 1.0 - (1.0 - up) * (1.0 - up))
	p.x = lerpf(mantle_from.x, mantle_to.x, fw)
	p.z = lerpf(mantle_from.z, mantle_to.z, fw)
	global_position = p
	if k >= 1.0:
		mantle_t = -1.0
		if state == State.SWIM:
			_leave_water()
		state = State.GROUND
		var dir := Vector3(mantle_to.x - mantle_from.x, 0, mantle_to.z - mantle_from.z).normalized()
		velocity = dir * mantle_carry                      # no dead stop at the top
		fall_start = global_position.y
		jump_air_t = 99.0


# ----------------------------------------------------------------------------- swimming

func _enter_water() -> void:
	if state == State.SWIM:
		return
	var impact := -velocity.y
	state = State.SWIM
	sliding = false
	crouched = false
	_set_height(STAND_H)
	cancel_use()
	reloading = 0.0
	in_fire = false
	build_piece = ""
	body.hold("")                                       # the weapon is put away
	fall_start = global_position.y                      # deep water: no fall damage
	var s: float = game.terrain.water_surface(global_position.x, global_position.z)
	game.sfx("splash", global_position)
	game.fx_splash(Vector3(global_position.x, s, global_position.z), clampf(impact / 10.0, 0.6, 2.5))


func _leave_water() -> void:
	state = State.GROUND
	fall_start = global_position.y
	_refresh_held()


func _swim_move(delta: float) -> void:
	var surf: float = game.terrain.water_surface(global_position.x, global_position.z)
	var d := surf - global_position.y
	if surf < -999.0 or (d < SWIM_OUT and is_on_floor()):
		_leave_water()
		return
	var w := _wish() * SWIM_SPEED
	velocity.x = move_toward(velocity.x, w.x, 10.0 * delta)
	velocity.z = move_toward(velocity.z, w.z, 10.0 * delta)
	# float with the head above water; standing still just treads water
	var want_y := surf - FLOAT_DEPTH + sin(game.match_time * 2.2) * 0.04
	velocity.y = clampf((want_y - global_position.y) * 4.0, -6.0, 3.0)
	if in_jump:
		in_jump = false
		if _try_mantle(MANTLE_MAX + 0.5):               # climb out onto a steep bank
			return
	move_and_slide()
	var hv := Vector2(velocity.x, velocity.z)
	if hv.length() > 1.0:
		foam_t -= delta
		if foam_t <= 0.0:
			foam_t = 0.14
			step_dist += 0.14
			if step_dist > 1.1:
				step_dist = 0.0
				game.sfx("swim", global_position)
			var back := Vector3(hv.x, 0, hv.y).normalized() * -0.5
			game.fx_foam(Vector3(global_position.x, surf + 0.03, global_position.z) + back)


# ----------------------------------------------------------------------------- inventory

func item() -> Variant:
	return slots[active] if active >= 0 else null


func select(i: int) -> void:
	if (i == active and build_piece == "") or i < -1 or i >= Items.SLOTS:
		return
	build_piece = ""
	active = i
	reloading = 0.0
	burst_left = 0
	cancel_use()
	fire_cd = maxf(fire_cd, 0.25)
	_refresh_held()


func set_build(piece: String) -> void:
	## Enter build mode with this piece; the same key again leaves it.
	build_piece = "" if build_piece == piece else piece
	reloading = 0.0
	cancel_use()
	in_fire = false
	if build_piece != "":
		body.hold("")
		if int(mats[build_mat]) < Structures.COST:     # start on a material there is enough of
			for m in Structures.MATS:
				if int(mats[m]) >= Structures.COST:
					build_mat = m
					break
	else:
		_refresh_held()


func cycle_build_mat() -> void:
	build_mat = Structures.MATS[(Structures.MATS.find(build_mat) + 1) % Structures.MATS.size()]


func _refresh_held() -> void:
	if build_piece != "":
		body.hold("")
		return
	var it = item()
	body.hold(Items.def(it).asset if it != null else "pickaxe")


func free_slot() -> int:
	for i in Items.SLOTS:
		if slots[i] == null:
			return i
	return -1


func wants(it: Dictionary) -> bool:
	## Would walking over this pick it up?
	if it.has("ammo") or it.has("gold"):
		return true
	if it.has("mat"):
		return int(mats[it.mat]) < Structures.MAX_MATS
	if it.has("forage"):
		return hp < 100.0 if it.forage == "apple" else shield < 100.0
	var d: Dictionary = Items.def(it)
	if d.has("stack"):
		for s in slots:
			if s != null and s.id == it.id and s.count < d.stack:
				return true
	return free_slot() >= 0


func add_item(it: Dictionary) -> bool:
	if it.has("ammo"):
		ammo[it.ammo] += it.get("count", Items.AMMO_PICKUP[it.ammo])
		return true
	if it.has("mat"):
		mats[it.mat] = mini(int(mats[it.mat]) + int(it.count), Structures.MAX_MATS)
		return true
	if it.has("gold"):
		gold += int(it.gold)
		return true
	if it.has("forage"):                               # eaten on the spot
		if it.forage == "apple":
			hp = minf(hp + 5.0, 100.0)
		else:
			shield = minf(shield + 5.0, 100.0)
		return true
	var d: Dictionary = Items.def(it)
	if d.has("stack"):
		for s in slots:
			if s != null and s.id == it.id and s.count < d.stack:
				var take: int = mini(d.stack - s.count, it.count)
				s.count += take
				it.count -= take
				if it.count <= 0:
					return true
	var f := free_slot()
	if f < 0:
		return false
	_spare_ammo(it)
	slots[f] = it
	if active == -1 and d.kind == "weapon":
		select(f)
	elif f == active:
		_refresh_held()
	return true


func _spare_ammo(it: Dictionary) -> void:
	## A weapon picked up for the first time comes with spare ammo of its type (two magazines, at least a box).
	if not it.has("id") or Items.def(it).kind != "weapon" or it.get("used", false):
		return
	it["used"] = true                                  # dropped and picked up again, it brings nothing more
	var d: Dictionary = Items.def(it)
	if d.ammo == "none":
		return
	ammo[d.ammo] += maxi(int(d.mag) * 2, int(Items.AMMO_PICKUP[d.ammo]))


func swap_slots(i: int, j: int) -> void:
	## Inventory screen: two hotbar slots trade places (the held one follows its item).
	var t = slots[i]
	slots[i] = slots[j]
	slots[j] = t
	if using > 0.0 and (use_slot == i or use_slot == j):
		cancel_use()
	if active == i:
		active = j
	elif active == j:
		active = i
	_refresh_held()


func drop_slot(i: int) -> void:
	if i < 0 or slots[i] == null:
		return
	var it: Dictionary = slots[i]
	slots[i] = null
	game.spawn_pickup(it, global_position + Vector3(-sin(aim_yaw), 0.4, -cos(aim_yaw)) * 1.4)
	if i == active:
		reloading = 0.0
		burst_left = 0
		cancel_use()
		_refresh_held()


func swap_with(it: Dictionary) -> void:
	## Inventory full: the held slot is dropped and replaced.
	var i := active if active >= 0 else 0
	drop_slot(i)
	_spare_ammo(it)
	slots[i] = it
	select(i)
	_refresh_held()


func best_weapon_slot(dist: float) -> int:
	var best := -1
	var best_score := -1.0
	for i in Items.SLOTS:
		var it = slots[i]
		if it == null or Items.def(it).kind != "weapon":
			continue
		var d: Dictionary = Items.def(it)
		if it.loaded <= 0 and ammo[d.ammo] <= 0:
			continue
		var score = 1.0 + it.rarity * 0.15
		match it.id:
			"shotgun": score *= 3.0 if dist < 12.0 else (1.0 if dist < 25.0 else 0.1)
			"tactical_shotgun": score *= 3.0 if dist < 12.0 else (1.0 if dist < 22.0 else 0.1)
			"smg": score *= 2.6 if dist < 22.0 else (1.2 if dist < 45.0 else 0.4)
			"burst_rifle": score *= 2.1 if (dist >= 12.0 and dist < 85.0) else 1.0
			"hunting_rifle": score *= 2.6 if dist > 45.0 else (0.6 if dist > 20.0 else 0.2)
			"pistol": score *= 1.3 if dist < 30.0 else 0.6
			"assault_rifle": score *= 2.2 if dist < 90.0 else 1.0
			"sniper_rifle": score *= 3.0 if dist > 55.0 else (0.5 if dist > 20.0 else 0.2)
			"rocket_launcher": score *= 2.4 if (dist > 14.0 and dist < 90.0) else 0.05
			"web_shooters": score *= 0.02
			"ravage_grasp": score *= 1.5 if dist < 26.0 else 0.05
			"charge_shotgun": score *= 3.0 if dist < 14.0 else (1.2 if dist < 28.0 else 0.1)
			"shockwave_launcher": score *= 1.4 if (dist > 6.0 and dist < 60.0) else 0.05
		if score > best_score:
			best_score = score
			best = i
	return best


func has_weapon() -> bool:
	return best_weapon_slot(30.0) >= 0


func find_item(id: String) -> int:
	for i in Items.SLOTS:
		if slots[i] != null and slots[i].id == id:
			return i
	return -1


# ----------------------------------------------------------------------------- combat

func _combat(delta: float) -> void:
	if (tsprint or hurdle_t >= 0.0) and using <= 0.0 and reloading <= 0.0:
		burst_left = 0                                 # gun lowered while sprinting or vaulting
		return
	var it = item()
	if using > 0.0:
		using -= delta
		if using <= 0.0:
			_finish_use()
		return
	if reloading > 0.0:
		reloading -= delta
		if reloading <= 0.0 and it != null and Items.def(it).kind == "weapon":
			var d: Dictionary = Items.def(it)
			var take: int = mini(d.mag - it.loaded, ammo[d.ammo])
			it.loaded += take
			ammo[d.ammo] -= take
		return
	if build_piece != "":
		return                                         # placing pieces is driven by the controller
	if it != null and Items.is_mythic(it) and _mythic_combat(it, delta):
		return
	if fire_cd > 0.0 or not (in_fire or burst_left > 0):      # a burst under way finishes without the trigger
		return
	if it == null:
		_swing_pickaxe()
		return
	var d2: Dictionary = Items.def(it)
	match d2.kind:
		"weapon":
			if _mythic_shot(d2):
				return
			if it.loaded <= 0:
				start_reload()
				if reloading <= 0.0 and is_player:
					game.sfx("empty", global_position)
					fire_cd = 0.3
				return
			_shoot(it, d2)
			if d2.has("burst"):
				burst_left = burst_left - 1 if burst_left > 0 else int(d2.burst) - 1
				if burst_left <= 0:
					fire_cd = float(d2.burst_gap)
			if not d2.auto and is_player:
				in_fire = false
		"throwable":
			_throw(it, d2)
			in_fire = false
		"heal", "shield":
			start_use()
			in_fire = false
		"launcher":
			in_fire = false
			fire_cd = 0.6
			if game.events.deploy_pad(self):
				it.count -= 1
				if it.count <= 0:
					slots[active] = null
					_refresh_held()


func start_reload() -> void:
	var it = item()
	if it == null or reloading > 0.0 or Items.def(it).kind != "weapon":
		return
	var d: Dictionary = Items.def(it)
	if it.loaded >= d.mag or ammo[d.ammo] <= 0:
		return
	burst_left = 0
	reloading = Items.reload_time(it)
	reload_total = reloading
	game.sfx({"shotgun": "reload_pump", "sniper_rifle": "reload_heavy", "rocket_launcher": "reload_heavy"}.get(it.id, "reload"), global_position)


func start_use() -> void:
	var it = item()
	if it == null or using > 0.0:
		return
	var d: Dictionary = Items.def(it)
	if not _needs_use(d):
		return
	using = d.use_time
	use_total = d.use_time
	use_slot = active


func _needs_use(d: Dictionary) -> bool:
	## Would this consumable do anything now? A heal that also gives shield counts if either is short.
	if d.kind == "shield":
		return shield < d.cap
	return hp < d.cap or (d.has("shield_amount") and shield < d.shield_cap)


func cancel_use() -> void:
	using = 0.0
	use_slot = -1


func _finish_use() -> void:
	using = 0.0
	if use_slot < 0 or slots[use_slot] == null:
		return
	var it: Dictionary = slots[use_slot]
	var d: Dictionary = Items.def(it)
	if d.kind == "heal":
		hp = maxf(hp, minf(hp + d.amount, d.cap))                      # never lowers hp that is above the cap
		if d.has("shield_amount"):
			shield = maxf(shield, minf(shield + d.shield_amount, d.shield_cap))
	else:
		shield = minf(shield + d.amount, d.cap)
	it.count -= 1
	if it.count <= 0:
		slots[use_slot] = null
		_refresh_held()
	use_slot = -1
	game.sfx("use_heal" if d.kind == "heal" else "use_shield", global_position)


func _swing_pickaxe() -> void:
	fire_cd = 0.55
	body.swing = 1.0
	var from := eye()
	var dir := aim_dir()
	if is_player:                                      # the pickaxe hits the point under the crosshair
		dir = (_cam_aim() - from).normalized()
	var hitp = game.ray(from, from + dir * 3.2, self)
	if hitp.is_empty():
		return
	if hitp.collider is Actor:
		(hitp.collider as Actor).hit(PICKAXE_DAMAGE, self, false, global_position)
		game.on_damage_dealt(self, hitp.collider, PICKAXE_DAMAGE, hitp.position)
	else:
		game.structures.pickaxe_hit(self, hitp)


var reload_total := 1.0                  # how long the current reload takes (for the animation)
const FIRST_SHOT_REST := 0.45             # seconds without firing before the next shot is a perfect first shot
var last_shot_t := -99.0


func first_shot_ready(d: Dictionary) -> bool:
	## First-shot accuracy: a single-bullet gun fired from a standstill after a short pause goes dead centre.
	if int(d.get("pellets", 1)) != 1 or d.get("rocket", false) or not _floor():
		return false
	if Vector2(velocity.x, velocity.z).length() > 1.0:
		return false
	return game.match_time - last_shot_t > FIRST_SHOT_REST and bloom < 0.05


func spread_deg(d: Dictionary) -> float:
	## The weapon's current cone: wider moving, in the air and after rapid fire; tighter crouched.
	if first_shot_ready(d):
		return 0.0
	var moving := Vector2(velocity.x, velocity.z).length() > 1.0
	return d.spread * (1.35 if moving else 1.0) * (1.6 if not _floor() else 1.0) * (0.7 if crouched else 1.0) * (1.0 + bloom) * spread_mul


func _shoot(it: Dictionary, d: Dictionary) -> void:
	it.loaded -= 1
	fire_cd = 1.0 / d.rate
	var from := eye()
	var moving := Vector2(velocity.x, velocity.z).length() > 1.0
	var spread := deg_to_rad(spread_deg(d))
	last_shot_t = game.match_time
	bloom = minf(bloom + float(d.get("bloom", 0.0)), 1.5)
	var base := aim_dir()
	if is_player:
		# aim where the camera looks, then shoot from the eye towards that point
		var target: Vector3 = _cam_aim()
		base = (target - from).normalized()
	game.sfx(it.id, global_position)
	if d.get("rocket", false):
		game.spawn_rocket(self, from + base * 1.2, base, Items.damage(it), d.radius)
		return
	if d.get("orb", false):
		game.spawn_shockwave(self, from + base * 1.2, base, d)
		return
	for p in d.pellets:
		var dir := _jitter(base, spread)
		var to := from + dir * 400.0
		var res = game.ray(from, to, self)
		var endp: Vector3 = res.position if res.has("position") else to
		if res.has("collider") and res.collider is Actor:
			var victim: Actor = res.collider
			var dist := from.distance_to(endp)
			var dmg := Items.damage(it) * (1.0 if dist <= d.range else clampf(1.0 - (dist - d.range) / d.range, 0.35, 1.0))
			var head := victim.is_head_point(endp)
			if head and d.pellets == 1:
				dmg *= 1.5                                    # headshot
			victim.hit(dmg, self, false, global_position)
			game.on_damage_dealt(self, victim, dmg, endp, head)
		elif res.has("collider"):
			game.structures.damage_at(res.collider, res.get("shape", 0), Items.damage(it), self, endp)
		game.fx_tracer(from + dir * 1.0 + Vector3(0, -0.2, 0), endp, it.rarity)


func _jitter(dir: Vector3, spread: float) -> Vector3:
	var a = game.rng.randf() * TAU
	var r := sqrt(game.rng.randf()) * spread
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	var x := dir.cross(up).normalized()
	var y := x.cross(dir).normalized()
	return (dir + (x * cos(a) + y * sin(a)) * tan(r)).normalized()


func _throw(it: Dictionary, d: Dictionary) -> void:
	fire_cd = 0.9
	var dir := (aim_dir() + Vector3(0, 0.28, 0)).normalized()
	game.sfx("throw", global_position)
	game.spawn_grenade(self, eye() + dir * 0.8, dir * 19.0 + velocity * 0.5, d.damage, d.radius)
	it.count -= 1
	if it.count <= 0:
		slots[active] = null
		_refresh_held()


# ----------------------------------------------------------------------------- damage

func hit(amount: float, attacker: Actor, bypass_shield: bool, from: Vector3) -> void:
	if state == State.DEAD or state == State.BLIMP or amount <= 0.0 or game.warming_up():
		return
	if game.net_client:                                # damage is the host's call; a fall is reported to it
		if self == game.player and attacker == null and bypass_shield and from == global_position:
			game.cmd(self, "fall", [amount])
		return
	if is_npc and (not hired or attacker == game.player):
		return                                         # nobody hurts them before they are hired, and no friendly fire
	if is_player and attacker != null and attacker == game.hired:
		return
	stop_emote()
	if attacker != null and attacker != self:
		last_attacker = attacker
		last_hit_from = from
		last_hit_time = game.match_time
		cancel_use()
	var left := amount
	if not bypass_shield and shield > 0.0:
		var s := minf(shield, left)
		shield -= s
		left -= s
	hp -= left
	if self == game.player:
		game.sfx("hurt", Vector3.INF)
	elif peer_id > 1 and game.nm:
		game.nm.ev_to(peer_id, "ui_sfx", ["hurt"])
	if hp <= 0.0:
		die(attacker if attacker != null else (last_attacker if game.match_time - last_hit_time < 8.0 else null))


func die(killer: Actor) -> void:
	if state == State.DEAD:
		return
	hp = 0.0
	shield = 0.0
	_mythic_clear()
	state = State.DEAD
	collision_layer = 0
	collision_mask = 0
	body.visible = false
	# eliminated players drop everything they carried
	var p := global_position + Vector3(0, 0.3, 0)
	var n := 0
	for i in Items.SLOTS:
		if slots[i] != null:
			game.spawn_pickup(slots[i], p + Vector3(cos(n * 1.3), 0, sin(n * 1.3)) * 1.1)
			slots[i] = null
			n += 1
	for m in Structures.MATS:
		if int(mats[m]) > 0:
			game.spawn_pickup({"mat": m, "count": mats[m]}, p + Vector3(cos(n * 1.3), 0, sin(n * 1.3)) * 2.2)
			mats[m] = 0
			n += 1
	if gold > 0:                                       # and their gold
		game.spawn_pickup({"gold": gold}, p + Vector3(cos(n * 1.3), 0, sin(n * 1.3)) * 2.2)
		gold = 0
	build_piece = ""
	for t in Items.AMMO_TYPES:
		if ammo[t] > 0:
			game.spawn_pickup({"ammo": t, "count": ammo[t]}, p + Vector3(cos(n * 1.3), 0, sin(n * 1.3)) * 1.7)
			ammo[t] = 0
			n += 1
	game.on_eliminated(self, killer)


# ----------------------------------------------------------------------------- mythic weapons
## Four boss weapons (Items.MYTHIC_IDS, rarity 5). All of them work from the normal inputs, so a bot or boss brain only
## needs aim_yaw / aim_pitch plus in_fire while the item is held (see the direct calls below for use without the item):
##   web_shooters       in_fire rising edge shoots a web (70 m, terrain / trees / buildings) and starts a swing; keep in_fire
##                      held to swing, in_fire = false (or in_jump) lets go and keeps the momentum. 0.4 s cooldown.
##                      Direct: web_swing_to(point) -> bool, web_release(), is_swinging().
##   ravage_grasp       in_fire (one pulse) lashes a tendril, 30 m: an enemy is yanked to you and slammed (60 damage,
##                      shield first, stun 0.6 s), a surface pulls YOU there. 3 s cooldown (1 s after a miss).
##                      Direct: grasp_at(target: Actor or Vector3) -> bool.
##   charge_shotgun     hold in_fire to charge (0..1 in 1 s, `charge`), in_fire = false fires with that charge. Uses shells.
##                      Direct: charge_fire(c: float) fires at once with charge c.
##   shockwave_launcher in_fire pulse lobs a slow orb that bursts into a launching shockwave (rockets, mag 4).
##                      Direct: shockwave_fire(dir: Vector3) -> bool, no item or ammo needed.
## `fire_cd` is the cooldown for all of them (the HUD reads it). Stunned actors (stun_t > 0) cannot move, fire or jump.

const WEB_RANGE := 70.0
const WEB_CD := 0.4
const WEB_GRAVITY := 20.0
const GRASP_RANGE := 30.0
const KNOCK_TIME := 1.5
const YANK_TIME := 0.22

var stun_t := 0.0
var charge := 0.0                        # charge shotgun: 0..1 while the trigger is held
var web_state := 0                       # 0 = none, 1 = swinging on the web, 2 = airborne after letting go
var web_anchor := Vector3.ZERO
var web_len := 10.0
var web_len_goal := 10.0
var web_t := 0.0
var web_free_t := 0.0
var web_hold := false                    # the swing was started by the held trigger, so letting go of it ends the swing
var web_max := 6.0
var _web_prev_fire := false
var _web_node: MeshInstance3D
var grasp_pull := false                  # being pulled to a surface by the tendril
var grasp_to := Vector3.ZERO
var grasp_t := 0.0
var grasp_fx = null
var yank_victim: Actor
var yank_t := 0.0
var yank_from := Vector3.ZERO
var yank_to := Vector3.ZERO
var knock_vel := Vector3.ZERO
var knock_t := 0.0


func _mythic_tick(delta: float) -> void:
	if stun_t > 0.0:
		stun_t -= delta
		in_move = Vector2.ZERO
		in_fire = false
		in_jump = false
		in_crouch = false
		reloading = 0.0
		burst_left = 0
	var it = item()
	if charge > 0.0 and not (it != null and it.id == "charge_shotgun" and state == State.GROUND):
		charge = 0.0
	var rising := in_fire and not _web_prev_fire
	_web_prev_fire = in_fire
	if rising and it != null and it.id == "web_shooters" and fire_cd <= 0.0 and build_piece == "" and emote == "" and using <= 0.0 and mantle_t < 0.0 and not remote_sim:
		_web_fire()
	if yank_victim != null:
		_grasp_yank_step(delta)
	if knock_t > 0.0:
		knock_t -= delta
		if state == State.SKYDIVE or state == State.GLIDE:
			var k := clampf(knock_t / KNOCK_TIME, 0.0, 1.0)
			velocity.x = knock_vel.x * k
			velocity.z = knock_vel.z * k
		if is_on_floor() and knock_t < KNOCK_TIME - 0.3:
			knock_t = 0.0


func _mythic_combat(it: Dictionary, delta: float) -> bool:
	## Called from _combat before the trigger check. True when this frame was handled here.
	var d: Dictionary = Items.def(it)
	if d.get("web", false):
		return true                                # the swing itself is handled in _tick (it works in the air too)
	if d.has("charge"):
		_charge_combat(it, d, delta)
		return true
	return false


func _mythic_shot(d: Dictionary) -> bool:
	## The fire branch of _combat for a mythic that fires on a pulse (grasp). True if handled.
	if d.get("grasp", false):
		_grasp_fire()
		if is_player:
			in_fire = false
		return true
	return false


func mythic_cooldown_frac() -> float:
	## 0 = ready, 1 = just fired (the HUD shows this for cooldown mythics).
	var it = item()
	if it == null or not Items.is_mythic(it):
		return 0.0
	var d: Dictionary = Items.def(it)
	return clampf(fire_cd / float(d.get("cooldown", 1.0 / float(d.rate))), 0.0, 1.0)


func _aim_from(from: Vector3) -> Vector3:
	var dir := aim_dir()
	if is_player:
		dir = (_cam_aim() - from).normalized()
	return dir


func _hand_pos() -> Vector3:
	if body != null and body.holder != null and body.held != null:
		return body.holder.global_position
	return global_position + Vector3(0, 1.2, 0)


# ---- web shooters

func is_swinging() -> bool:
	return web_state == 1


func _web_fire() -> void:
	var from := eye()
	var dir := _aim_from(from)
	var res: Dictionary = game.ray(from, from + dir * WEB_RANGE, self, 1)
	if res.is_empty():
		fire_cd = 0.25
		game.sfx("empty", global_position)
		return
	web_swing_to(res.position, true)


func web_swing_to(point: Vector3, held_fire := false) -> bool:
	## Start swinging from `point` (anywhere, any range). Without held_fire the swing ends by web_release(), a jump,
	## or after 4 seconds.
	if state == State.DEAD or state == State.BLIMP or state == State.SWIM or stun_t > 0.0:
		return false
	zip = null
	mantle_t = -1.0
	sliding = false
	crouched = false
	_set_height(STAND_H)
	cancel_use()
	reloading = 0.0
	stop_emote()
	grasp_pull = false
	launched = false
	knock_t = 0.0
	state = State.GROUND
	var hand := global_position + Vector3(0, 1.2, 0)
	web_anchor = point
	web_len = maxf(hand.distance_to(point), 5.0)
	web_len_goal = clampf(web_len * 0.72, 6.0, 55.0)
	web_t = 0.0
	web_hold = held_fire
	web_max = 6.0 if held_fire else 4.0
	web_state = 1
	if is_on_floor():
		velocity.y = maxf(velocity.y, 6.0)
		global_position += Vector3(0, 0.12, 0)
	game.sfx("web_shooters", global_position)
	_web_line_update()
	return true


func web_release() -> void:
	if web_state != 1:
		return
	web_state = 2
	web_free_t = 0.0
	in_jump = false
	fire_cd = maxf(fire_cd, WEB_CD)
	_web_line_hide()


func _web_cancel() -> void:
	web_state = 0
	_web_line_hide()


func _web_step(delta: float) -> void:
	if web_state == 1:
		web_t += delta
		if in_jump or (web_hold and not in_fire) or web_t > web_max:
			web_release()
	if web_state == 1:
		var pos0 := global_position
		var hand := pos0 + Vector3(0, 1.2, 0)
		var out := hand - web_anchor
		var dist := maxf(out.length(), 0.01)
		web_len = move_toward(web_len, web_len_goal, 24.0 * delta)
		velocity.y -= WEB_GRAVITY * delta
		var w := _wish()
		if w.length() > 0.1 and Vector2(velocity.x, velocity.z).dot(Vector2(w.x, w.z)) < 26.0:
			velocity.x += w.x * 14.0 * delta
			velocity.z += w.z * 14.0 * delta
		if dist >= web_len - 0.05:
			var n := out / dist
			var vr := velocity.dot(n)
			if vr > 0.0:
				velocity -= n * vr                       # the web is taut: no moving away from the anchor
		move_and_slide()
		hand = global_position + Vector3(0, 1.2, 0)
		var o2 := hand - web_anchor
		if o2.length() > web_len:
			var fix := web_anchor + o2.normalized() * web_len - hand
			move_and_collide(fix)
			velocity += fix / maxf(delta, 0.001)
		if velocity.length() > 48.0:
			velocity = velocity.normalized() * 48.0
		fall_start = global_position.y
		jump_air_t = 99.0
		if is_on_floor() and web_t > 0.6 and Vector2(velocity.x, velocity.z).length() < 3.0:
			web_release()
		if depth() > SWIM_IN:
			_web_cancel()
			_enter_water()
			return
		_web_line_update()
		return
	# airborne after letting go: keep the momentum, steer a little, no fall damage for a while
	web_free_t += delta
	velocity.y -= GRAVITY * delta
	var w2 := _wish()
	if w2.length() > 0.1 and Vector2(velocity.x, velocity.z).dot(Vector2(w2.x, w2.z)) < 14.0:
		velocity.x += w2.x * 7.0 * delta
		velocity.z += w2.z * 7.0 * delta
	in_jump = false
	move_and_slide()
	if web_free_t < 2.5:
		fall_start = global_position.y
	if is_on_floor():
		web_state = 0
		fall_start = global_position.y
		jump_air_t = 99.0
		game.sfx("land", global_position)
	elif depth() > SWIM_IN:
		web_state = 0
		_enter_water()


func _web_line_update() -> void:
	if _web_node == null:
		_web_node = MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.022, 0.022, 1.0)
		_web_node.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1, 1, 1)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_web_node.material_override = m
		_web_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		game.fx_root.add_child(_web_node)
	var a := _hand_pos()
	var len := a.distance_to(web_anchor)
	if len < 0.05:
		return
	_web_node.visible = true
	_web_node.global_position = (a + web_anchor) / 2.0
	var up := Vector3.UP if absf((web_anchor - a).normalized().y) < 0.98 else Vector3.RIGHT
	_web_node.look_at(web_anchor, up)
	_web_node.scale = Vector3(1, 1, len)


func _web_line_hide() -> void:
	if _web_node != null:
		_web_node.visible = false


# ---- Ravage's Grasp

func _grasp_fire() -> void:
	var from := eye()
	var dir := _aim_from(from)
	var res: Dictionary = game.ray(from, from + dir * GRASP_RANGE, self)
	game.sfx("ravage_grasp", global_position)
	body.swing = 1.0
	if res.is_empty():
		fire_cd = 1.0
		game.fx_tendril(self, from + dir * GRASP_RANGE, 0.45, true)
		return
	if res.collider is Actor:
		grasp_at(res.collider)
	else:
		grasp_at(res.position)


func grasp_at(target) -> bool:
	## Lash at an Actor (yank and slam it) or a Vector3 surface point (pull yourself to it).
	var d: Dictionary = Items.DEFS["ravage_grasp"]
	if state == State.DEAD or state == State.BLIMP or stun_t > 0.0:
		return false
	if target is Actor:
		var v: Actor = target
		if v == self or not v.alive() or v.state == State.BLIMP:
			return false
		fire_cd = float(d.cooldown)
		yank_victim = v
		yank_t = 0.0
		yank_from = v.global_position
		var flat := Vector3(global_position.x - v.global_position.x, 0, global_position.z - v.global_position.z)
		flat = flat.normalized() if flat.length() > 0.1 else Vector3.BACK
		var spot := global_position - flat * 1.7
		var dn: Dictionary = game.ray(spot + Vector3(0, 2.0, 0), spot - Vector3(0, 4.0, 0), self, 1)
		yank_to = Vector3(spot.x, dn.position.y if not dn.is_empty() else global_position.y, spot.z)
		v.stun_t = maxf(v.stun_t, YANK_TIME + 0.1)
		if v.peer_id > 1 and game.nm:
			game.nm.ev_to(v.peer_id, "stun", [YANK_TIME + 0.1])
		v.zip = null
		v.mantle_t = -1.0
		v._web_cancel()
		v.grasp_pull = false
		game.fx_tendril(self, v, YANK_TIME + 0.25, false)
		return true
	if state == State.SWIM:
		return false
	fire_cd = float(d.cooldown)
	var pt: Vector3 = target
	var from := eye()
	var nrm := Vector3.UP
	var hitp: Dictionary = game.ray(from, from + (pt - from).normalized() * (from.distance_to(pt) + 0.6), self, 1)
	if not hitp.is_empty():
		pt = hitp.position
		nrm = hitp.normal
	if state == State.SKYDIVE or state == State.GLIDE:
		state = State.GROUND
	zip = null
	mantle_t = -1.0
	sliding = false
	crouched = false
	_set_height(STAND_H)
	cancel_use()
	stop_emote()
	_web_cancel()
	launched = false
	knock_t = 0.0
	grasp_to = pt + nrm * 0.9
	grasp_t = 0.0
	grasp_pull = true
	if peer_id > 1 and game.nm:                         # that human moves on their own device
		grasp_pull = false
		game.nm.ev_to(peer_id, "grasp_pull", [grasp_to])
	if is_on_floor():
		velocity.y = maxf(velocity.y, 4.0)
		global_position += Vector3(0, 0.1, 0)
	grasp_fx = game.fx_tendril(self, pt, 1.8, false)
	return true


func _grasp_yank_step(delta: float) -> void:
	var v := yank_victim
	if v == null or not v.alive():
		yank_victim = null
		return
	yank_t += delta
	var k := clampf(yank_t / YANK_TIME, 0.0, 1.0)
	v.global_position = yank_from.lerp(yank_to, k * k * (3.0 - 2.0 * k))
	v.velocity = Vector3.ZERO
	v.fall_start = v.global_position.y
	if k < 1.0:
		return
	yank_victim = null
	if v.peer_id > 1 and game.nm:
		game.nm.ev_to(v.peer_id, "set_pos", [v.global_position, Vector3.ZERO])
	var d: Dictionary = Items.DEFS["ravage_grasp"]
	var dmg := float(d.damage)
	v.hit(dmg, self, false, global_position)
	v.stun_t = maxf(v.stun_t, float(d.stun))
	game.on_damage_dealt(self, v, dmg, v.centre())
	game.sfx("land", v.global_position)
	game.fx_blast(v.centre(), 2.2)


func _grasp_pull_step(delta: float) -> void:
	grasp_t += delta
	var to := grasp_to - (global_position + Vector3(0, 0.9, 0))
	var dist := to.length()
	var stuck := grasp_t > 0.2 and get_real_velocity().length() < 2.0
	if dist < 1.3 or grasp_t > 1.7 or stuck:
		grasp_pull = false
		if grasp_fx != null:
			grasp_fx.life = float(grasp_fx.t) + 0.15
			grasp_fx = null
		var dir := to / maxf(dist, 0.01)
		velocity = dir * minf(9.0, dist * 4.0) + Vector3(0, 3.0, 0)
		fall_start = global_position.y
		jump_air_t = 99.0
		if is_on_wall():
			_try_mantle(MANTLE_MAX + 1.0)
		return
	velocity = to / dist * clampf(dist * 6.0, 9.0, 34.0)
	move_and_slide()
	fall_start = global_position.y
	jump_air_t = 99.0
	if depth() > SWIM_IN:
		grasp_pull = false
		_enter_water()


# ---- charge shotgun

func _charge_combat(it: Dictionary, d: Dictionary, delta: float) -> void:
	if fire_cd > 0.0:
		return
	if in_fire and it.loaded > 0:
		if charge <= 0.0:
			game.sfx("charge_up_ui" if is_player else "charge_up", global_position)
		var was := charge
		charge = minf(charge + delta / float(d.charge), 1.0)
		if charge >= 1.0 and was < 1.0:
			game.sfx("charge_full", global_position)
		return
	if charge > 0.0:
		charge_fire(charge)
		return
	if in_fire and it.loaded <= 0:
		start_reload()
		if reloading <= 0.0 and is_player:
			game.sfx("empty", global_position)
			fire_cd = 0.3


func charge_fire(c := 1.0) -> bool:
	var it = item()
	if it == null or it.id != "charge_shotgun" or it.loaded <= 0:
		charge = 0.0
		return false
	var d: Dictionary = Items.def(it)
	c = clampf(c, 0.0, 1.0)
	charge = 0.0
	it.loaded -= 1
	fire_cd = 1.0 / float(d.rate)
	if is_player:
		in_fire = false
	var from := eye()
	var dd: Dictionary = d.duplicate()
	dd["spread"] = lerpf(float(d.spread), float(d.charge_spread), c)
	var spread := deg_to_rad(spread_deg(dd))
	last_shot_t = game.match_time
	bloom = minf(bloom + 0.3, 1.5)
	var base := _aim_from(from)
	game.sfx("charge_shotgun", global_position)
	var per := Items.damage(it) * lerpf(float(d.charge_min_mul), float(d.charge_max_mul), c)
	for p in int(d.pellets):
		var dir := _jitter(base, spread)
		var to := from + dir * 400.0
		var res = game.ray(from, to, self)
		var endp: Vector3 = res.position if res.has("position") else to
		if res.has("collider") and res.collider is Actor:
			var victim: Actor = res.collider
			var dist := from.distance_to(endp)
			var dmg := per * (1.0 if dist <= d.range else clampf(1.0 - (dist - d.range) / d.range, 0.35, 1.0))
			victim.hit(dmg, self, false, global_position)
			game.on_damage_dealt(self, victim, dmg, endp)
		elif res.has("collider"):
			game.structures.damage_at(res.collider, res.get("shape", 0), per, self, endp)
		game.fx_tracer(from + dir * 1.0 + Vector3(0, -0.2, 0), endp, 5 if c > 0.95 else 3)
	return true


# ---- shockwave launcher

func shockwave_fire(dir: Vector3) -> bool:
	## Lob a shockwave orb from the eye along dir, with or without the item.
	var d: Dictionary = Items.DEFS["shockwave_launcher"]
	if state == State.DEAD or state == State.BLIMP or stun_t > 0.0:
		return false
	game.sfx("shockwave_launcher", global_position)
	game.spawn_shockwave(self, eye() + dir * 1.2, dir.normalized(), d)
	return true


func receive_knock(up: float, push: Vector3) -> void:
	if peer_id > 1 and game.nm:                         # a remote human moves on their own device
		game.nm.ev_to(peer_id, "knock", [up, push])
		return
	## Thrown up and away by a shockwave: the launch pad's launch(), plus sideways momentum, and no fall damage.
	launch(up)
	knock_vel = push
	knock_t = KNOCK_TIME
	velocity.x = push.x
	velocity.z = push.z


func _mythic_clear() -> void:
	web_state = 0
	grasp_pull = false
	yank_victim = null
	charge = 0.0
	if _web_node != null:
		_web_node.queue_free()
		_web_node = null
