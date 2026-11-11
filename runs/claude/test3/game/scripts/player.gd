## Player input and the third-person camera. Also runs spectating after elimination,
## and a hands-off camera when an AI is playing the character (--demo).
extends Node

const SENS := 0.0026

var game: Node
var a: Actor
var cam: Camera3D
var demo := false
var yaw := 0.0
var pitch := -0.2
var spectate: Actor
var show_map := false
var prompt := ""
var prompt_target = null
var zoom := 0.0
var touch_use := false
var look_entry = null                    # the breakable thing under the crosshair, for the HUD
var touch: Control                       # on-screen controls, only on touch devices


func setup(g: Node, actor: Actor, is_demo: bool) -> void:
	game = g
	a = actor
	demo = is_demo
	cam = Camera3D.new()
	cam.far = 2500.0
	cam.fov = 75.0
	add_child(cam)
	cam.current = true
	yaw = atan2(-game.blimp_dir.x, -game.blimp_dir.z)
	var mobile := OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--touch")
	if mobile and not demo:
		touch = preload("res://scripts/touch.gd").new()
		var layer := CanvasLayer.new()
		layer.layer = 2
		add_child(layer)
		layer.add_child(touch)
		touch.setup(game)
	elif not demo and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func on_player_eliminated(killer: Actor) -> void:
	spectate = killer if killer != null and killer.alive() else _next_alive(null)


func _next_alive(after: Actor) -> Actor:
	var list: Array = game.actors
	var start: int = list.find(after) if after != null else -1
	for i in range(1, list.size() + 1):
		var o: Actor = list[(start + i) % list.size()]
		if o.alive():
			return o
	return null


func _unhandled_input(e: InputEvent) -> void:
	if demo:
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= e.relative.x * SENS * (0.55 if zoom > 0.5 else 1.0)
		pitch = clampf(pitch - e.relative.y * SENS * (0.55 if zoom > 0.5 else 1.0), -1.45, 1.35)
	elif e is InputEventKey and e.pressed and not e.echo:
		match e.physical_keycode:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				a.select(e.physical_keycode - KEY_1)
	elif e is InputEventMouseButton and e.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif not a.alive() and e.button_index == MOUSE_BUTTON_LEFT:
			spectate = _next_alive(spectate)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			a.select(wrapi(a.active + 1, -1, Items.SLOTS))
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP:
			a.select(wrapi(a.active - 1, -1, Items.SLOTS))


func _physics_process(delta: float) -> void:
	prompt = ""
	prompt_target = null
	if a.alive() and not demo and touch != null:
		_touch_input()
	elif a.alive() and not demo:
		a.aim_yaw = yaw
		a.aim_pitch = pitch
		a.in_move = Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_back", "move_forward"))
		a.in_sprint = not Input.is_action_pressed("aim")           # run by default, walk while aiming
		if Input.is_action_just_pressed("jump"):
			a.in_jump = true
		a.in_dive = a.state == Actor.State.SKYDIVE and (pitch < -0.75 or Input.is_action_pressed("sprint"))
		for bk in [["build_wall", "wall"], ["build_floor", "floor"], ["build_stairs", "stairs"], ["build_cone", "cone"]]:
			if Input.is_action_just_pressed(bk[0]):
				a.set_build(bk[1])
		if a.build_piece != "":
			a.in_fire = false
			if Input.is_action_just_pressed("aim"):
				a.cycle_build_mat()
			_build_tick(delta, Input.is_action_pressed("fire"), Input.is_action_just_pressed("fire"))
		else:
			var it = a.item()
			var auto: bool = it != null and Items.def(it).get("auto", false)
			if Input.is_action_just_pressed("fire") or (auto and Input.is_action_pressed("fire")) or (it == null and Input.is_action_pressed("fire")):
				a.in_fire = true
			elif not Input.is_action_pressed("fire"):
				a.in_fire = false
		if Input.is_action_just_pressed("reload"):
			a.start_reload()
		if Input.is_action_just_pressed("pickaxe"):
			a.select(-1)
		if Input.is_action_just_pressed("drop_item"):
			a.drop_slot(a.active)
		if Input.is_action_just_pressed("map"):
			show_map = not show_map
		_interaction()
	elif a.alive() and demo:
		yaw = lerp_angle(yaw, a.aim_yaw, clampf(delta * 4.0, 0.0, 1.0))
		pitch = lerpf(pitch, clampf(a.aim_pitch, -0.6, 0.4) - 0.12, clampf(delta * 4.0, 0.0, 1.0))
	game.structures.update_preview(a, not demo)
	look_entry = null
	if a.alive() and a.state == Actor.State.GROUND and cam:
		look_entry = game.structures.looked_at(cam.global_position, -cam.global_transform.basis.z, 14.0, a)
	if not a.alive() and touch != null and touch.fire:
		touch.fire = false
		spectate = _next_alive(spectate)
	if not a.alive() and (spectate == null or not spectate.alive()):
		spectate = _next_alive(spectate)


func _touch_input() -> void:
	var k := SENS * 1.6 * (0.55 if zoom > 0.5 else 1.0)
	yaw -= touch.look.x * k
	pitch = clampf(pitch - touch.look.y * k, -1.45, 1.35)
	touch.look = Vector2.ZERO
	a.aim_yaw = yaw
	a.aim_pitch = pitch
	a.in_move = touch.move
	a.in_sprint = not touch.aim
	if touch.take("jump"):
		a.in_jump = true
	a.in_dive = a.state == Actor.State.SKYDIVE and pitch < -0.75
	for bk in [["b_wall", "wall"], ["b_floor", "floor"], ["b_stairs", "stairs"], ["b_cone", "cone"]]:
		if touch.take(bk[0]):
			a.set_build(bk[1])
	if a.build_piece != "":
		a.in_fire = false
		if touch.take("mat"):
			a.cycle_build_mat()
		_build_tick(get_physics_process_delta_time(), touch.fire, false)
	else:
		a.in_fire = touch.fire
	if touch.take("reload"):
		a.start_reload()
	if touch.take("drop"):
		a.drop_slot(a.active)
	if touch.take("map"):
		show_map = not show_map
	touch_use = touch.take("use")
	_interaction()
	if not a.alive() and touch.fire:
		touch.fire = false


func _build_tick(delta: float, held: bool, just: bool) -> void:
	## Click to place; holding the button keeps placing as the target changes (turbo build).
	a.build_cd = maxf(a.build_cd - delta, 0.0)
	if (just or held) and a.build_cd <= 0.0:
		if game.structures.place(a):
			a.build_cd = 0.09


func _use_pressed() -> bool:
	if touch != null:
		var u := touch_use
		touch_use = false
		return u
	return Input.is_action_just_pressed("interact")


func _interaction() -> void:
	if a.state != Actor.State.GROUND:
		return
	var c = game.nearest_container(a.global_position, 2.8)
	if c != null:
		prompt = "[E]  Open %s" % {"chest": "chest", "ammo_box": "ammo box", "supply_drop": "supply drop"}[c.kind]
		if _use_pressed():
			game.open_container(c, a)
		return
	var p = game.nearest_pickup(a, 2.2)
	if p != null and not a.wants(p.item):
		prompt = "[E]  Swap for %s" % Items.label(p.item)
		if _use_pressed():
			var it: Dictionary = p.item
			game.remove_pickup(p)
			a.swap_with(it)


func subject() -> Actor:
	return a if a.alive() else spectate


func _process(delta: float) -> void:
	var s := subject()
	if s == null:
		return
	if not a.alive():
		yaw = lerp_angle(yaw, s.aim_yaw, clampf(delta * 5.0, 0.0, 1.0))
		pitch = lerpf(pitch, -0.18, clampf(delta * 3.0, 0.0, 1.0))
	var aiming: bool = a.alive() and not demo and a.build_piece == "" and (Input.is_action_pressed("aim") or (touch != null and touch.aim)) and a.state == Actor.State.GROUND
	zoom = move_toward(zoom, 1.0 if aiming else 0.0, delta * 7.0)
	var it = s.item()
	var scoped: bool = it != null and it.id == "sniper_rifle"
	cam.fov = lerpf(75.0, 22.0 if scoped else 48.0, zoom)
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var back := 4.6
	var up := 1.9
	var side := 0.75
	if s.state == Actor.State.BLIMP:
		back = 26.0; up = 9.0; side = 0.0
	elif s.state == Actor.State.SKYDIVE or s.state == Actor.State.GLIDE:
		back = 8.0; up = 2.6; side = 0.0
	back = lerpf(back, 2.2, zoom)
	side = lerpf(side, 0.55, zoom)
	var pivot := s.global_position + Vector3(0, up, 0) + basis.x * side
	var want := pivot + basis.z * back
	var hit = game.ray(pivot, want, s, 1)
	if not hit.is_empty():
		want = pivot + (hit.position - pivot) * 0.92
	cam.global_position = want
	cam.global_transform.basis = basis


func aim_point() -> Vector3:
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var res = game.ray(from + dir * 2.0, from + dir * 420.0, a)
	return res.position if not res.is_empty() else from + dir * 420.0
