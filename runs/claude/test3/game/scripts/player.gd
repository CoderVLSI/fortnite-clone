## Player input and the third-person camera. Also runs spectating after elimination,
## and a hands-off camera when an AI is playing the character (--demo).
extends Node

var SENS: float:                          # look speed comes from the Settings autoload
	get: return Settings.sens()

var game: Node
var a: Actor
var cam: Camera3D
var demo := false
var yaw := 0.0
var pitch := -0.2
var spectate: Actor
var show_map := false
var marker := Vector3.INF                 # a spot marked on the map (Vector3.INF = none): pin on the HUD, a beam in the world
var marker_beam: MeshInstance3D
var prompt := ""
var prompt_target = null
var zoom := 0.0
var cam_up := 1.9
var force_aim := false
const WHEEL := ["samba", "wave", "nod", "no"]      # up, right, down, left on the emote wheel
var wheel_open := false
var wheel_vec := Vector2.ZERO                   # tests: aim without the mouse button
var touch_use := false
var look_entry = null                    # the breakable thing under the crosshair, for the HUD
var touch: Control                       # on-screen controls, only on touch devices
var touch_last_build := "wall"            # the piece the touch Build button goes back to
var inv: Control                         # inventory screen (Tab); the match keeps running behind it


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
	_build_talk_ui()
	inv = preload("res://scripts/inventory_ui.gd").new()
	var inv_layer := CanvasLayer.new()
	inv_layer.layer = 5
	add_child(inv_layer)
	inv_layer.add_child(inv)
	inv.setup(game, self)
	if OS.get_cmdline_user_args().has("--invtest") or OS.get_cmdline_user_args().has("--invshot"):
		var itest := preload("res://scripts/invtest.gd").new()     # inventory screen check / screenshot run
		itest.setup(game)
		game.add_child.call_deferred(itest)


func inv_open() -> bool:
	## The inventory or a conversation has the screen: no looking, firing or building behind it.
	return (inv != null and inv.is_open) or talking != null


# ----------------------------------------------------------------------------- talking to characters for hire

var talking: Actor = null
var talk_panel: PanelContainer
var talk_name: Label
var talk_line: Label
var talk_hire: Button
var talk_note: Label


func _build_talk_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = MenuUI.make_theme()
	layer.add_child(root)
	talk_panel = PanelContainer.new()
	talk_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	talk_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	talk_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	talk_panel.offset_left = -330
	talk_panel.offset_right = 330
	talk_panel.offset_bottom = -150
	talk_panel.visible = false
	root.add_child(talk_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	talk_panel.add_child(v)
	talk_name = MenuUI.label("", 26, MenuUI.ACCENT)
	v.add_child(talk_name)
	talk_line = MenuUI.label("", 19, MenuUI.TEXT)
	talk_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	talk_line.custom_minimum_size = Vector2(600, 0)
	v.add_child(talk_line)
	talk_note = MenuUI.label("", 15, MenuUI.DIM)
	v.add_child(talk_note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	talk_hire = MenuUI.button("", 22, Vector2(300, 54))
	talk_hire.pressed.connect(func() -> void:
		if talking and game.hire_npc(talking):
			close_talk())
	row.add_child(talk_hire)
	var bye := MenuUI.button("Not now", 20, Vector2(160, 54))
	bye.pressed.connect(close_talk)
	row.add_child(bye)


func open_talk(n: Actor) -> void:
	var brain: Node = n.get_node("NpcBrain")
	talking = n
	talk_name.text = brain.info.name
	talk_line.text = "\"%s\"" % brain.info.line
	var cost: int = brain.info.cost
	talk_hire.text = "Hire  ·  %d gold" % cost
	talk_hire.disabled = a.gold < cost or game.hired != null or game.warming_up()
	talk_note.text = ("You have %d gold." % a.gold) if not talk_hire.disabled else (
			"Hiring opens once the match starts." if game.warming_up() else (
			"You already have someone with you." if game.hired != null else "You have %d gold: not enough yet." % a.gold))
	talk_panel.visible = true
	if touch == null:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_talk() -> void:
	talking = null
	if talk_panel:
		talk_panel.visible = false
	if touch == null and not demo and DisplayServer.get_name() != "headless" and not (inv != null and inv.is_open):
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
	if e is InputEventMouseMotion and wheel_open:
		wheel_vec = (wheel_vec + e.relative).limit_length(140.0)     # the mouse picks a slice instead of looking
	elif e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= e.relative.x * SENS * (0.55 if zoom > 0.5 else 1.0)
		pitch = clampf(pitch - e.relative.y * SENS * (0.55 if zoom > 0.5 else 1.0) * (-1.0 if Settings.invert_y else 1.0), -1.45, 1.35)
	elif e is InputEventKey and e.pressed and not e.echo:
		match e.physical_keycode:
			KEY_ESCAPE:
				game.pause_menu.open()                     # Esc pauses (was: toggle mouse capture)
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				a.select(e.physical_keycode - KEY_1)
	elif e is InputEventMouseButton and e.pressed and show_map:
		if e.button_index == MOUSE_BUTTON_LEFT:
			map_tap(e.position)
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			clear_marker()
	elif e is InputEventMouseButton and e.pressed:
		if inv_open():
			pass                                       # the inventory owns the mouse
		elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			if not game.over:                          # the end-of-match summary keeps the mouse free for its buttons
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
		a.in_tsprint = Input.is_action_pressed("sprint") and not Input.is_action_pressed("aim") and not Input.is_action_pressed("fire") and a.state == Actor.State.GROUND
		a.in_jump_held = Input.is_action_pressed("jump")
		if Input.is_action_just_pressed("jump"):
			a.in_jump = true
		if Input.is_action_just_pressed("crouch"):
			a.in_crouch = true
		if Input.is_action_just_pressed("emote"):
			wheel_open = true
			wheel_vec = Vector2.ZERO
		elif wheel_open and not Input.is_action_pressed("emote"):
			wheel_open = false
			var pick := wheel_pick()
			if pick >= 0:
				a.start_emote(WHEEL[pick])
		a.in_dive = a.state == Actor.State.SKYDIVE and (pitch < -0.75 or Input.is_action_pressed("sprint"))
		for bk in [["build_wall", "wall"], ["build_floor", "floor"], ["build_stairs", "stairs"], ["build_cone", "cone"]]:
			if Input.is_action_just_pressed(bk[0]) and not inv_open():
				game.structures.cancel_edit()
				a.set_build(bk[1])
		if Input.is_action_just_pressed("edit"):
			_edit_key()
		if inv_open():
			a.in_fire = false                          # no firing or building behind the inventory
		elif editing():
			a.in_fire = false
			_edit_tick(Input.is_action_pressed("fire"), Input.is_action_just_pressed("fire"))
			if Input.is_action_just_pressed("reload"):
				game.structures.reset_edit()
		elif a.build_piece != "":
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
		if Input.is_action_just_pressed("reload") and not editing() and not inv_open():
			a.start_reload()
		if Input.is_action_just_pressed("pickaxe"):
			a.select(-1)
		if Input.is_action_just_pressed("drop_item"):
			a.drop_slot(a.active)
		if Input.is_action_just_pressed("map"):
			toggle_map()
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
	if touch.take("inv"):
		inv.toggle()
	if inv_open():
		touch.look = Vector2.ZERO
	var k := SENS * 1.6 * (0.55 if zoom > 0.5 else 1.0)
	yaw -= touch.look.x * k
	pitch = clampf(pitch - touch.look.y * k * (-1.0 if Settings.invert_y else 1.0), -1.45, 1.35)
	touch.look = Vector2.ZERO
	a.aim_yaw = yaw
	a.aim_pitch = pitch
	a.in_move = touch.move
	a.in_sprint = not touch.aim
	if touch.fire or touch.aim:
		touch.tsprint = false
	a.in_tsprint = touch.tsprint and not touch.aim and not touch.fire and a.state == Actor.State.GROUND
	if touch.take("jump"):
		a.in_jump = true
	if touch.take("crouch"):
		a.in_crouch = true
	if touch.take("emote"):                        # first tap opens the wheel, drag towards an emote, tap again to play it
		if wheel_open:
			var tp := wheel_pick()
			if tp >= 0:
				a.start_emote(WHEEL[tp])
		wheel_open = not wheel_open
		wheel_vec = Vector2.ZERO
	if wheel_open:
		wheel_vec = (wheel_vec + touch.look).limit_length(140.0)
		touch.look = Vector2.ZERO
	a.in_dive = a.state == Actor.State.SKYDIVE and pitch < -0.75
	if touch.take("build") and not inv_open():        # one button in and out of build mode, like mobile shooters
		var was_editing := editing()
		game.structures.cancel_edit()
		if a.build_piece == "" and not was_editing:
			a.set_build(touch_last_build)
		elif a.build_piece != "":
			touch_last_build = a.build_piece
			a.set_build(a.build_piece)                     # the same piece again leaves build mode
	for bk in [["b_wall", "wall"], ["b_floor", "floor"], ["b_stairs", "stairs"], ["b_cone", "cone"]]:
		if touch.take(bk[0]) and not inv_open() and a.build_piece != bk[1]:
			game.structures.cancel_edit()
			a.set_build(bk[1])
			touch_last_build = bk[1]
	if touch.take("edit"):
		_edit_key()
	if inv_open():
		a.in_fire = false
	elif editing():
		a.in_fire = false
		_edit_tick(touch.fire, touch.take("fire_down"))
		if touch.take("reload"):
			game.structures.reset_edit()
	elif a.build_piece != "":
		a.in_fire = false
		if touch.take("mat"):
			a.cycle_build_mat()
		_build_tick(get_physics_process_delta_time(), touch.fire, false)
	else:
		a.in_fire = touch.fire or (Settings.auto_fire and _enemy_in_sights())
	if touch.take("auto"):
		Settings.auto_fire = not Settings.auto_fire
		Settings.save_file()
		game.announce("Auto fire " + ("on" if Settings.auto_fire else "off"))
	if touch.take("reload"):
		a.start_reload()
	if touch.take("drop"):
		a.drop_slot(a.active)
	if touch.take("map"):
		toggle_map()
	touch_use = touch.take("use")
	_interaction()
	if not a.alive() and touch.fire:
		touch.fire = false


func wheel_pick() -> int:
	## The emote slice the wheel points at, or -1 near the centre.
	if wheel_vec.length() < 25.0:
		return -1
	var ang := fposmod(atan2(wheel_vec.x, -wheel_vec.y) + PI / 4.0, TAU)
	return int(ang / (PI / 2.0)) % 4


func editing() -> bool:
	return game.structures.edit_entry != null


func _edit_key() -> void:
	## G opens the edit grid on the piece you are looking at; G again confirms the edit.
	var S: Structures = game.structures
	if S.edit_entry != null:
		S.confirm_edit()
		return
	if look_entry != null and S.begin_edit(a, look_entry):
		a.build_piece = ""
		a.in_fire = false
		a._refresh_held()


func _edit_tick(held: bool, just: bool) -> void:
	game.structures.update_edit(a, cam.global_position, -cam.global_transform.basis.z, held, just)


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


func _key_hint() -> String:
	## The interact key as the player has it bound ("USE" on a touch screen).
	return "USE " if touch != null else "[%s] " % Settings.event_text("interact")


func _interaction() -> void:
	if a.state == Actor.State.SKYDIVE and not a.launched:
		if a.height_above_ground() > 8.0:
			prompt = _key_hint() + " Deploy glider"
			if _use_pressed():
				a.deploy_glider()
		return
	if a.state != Actor.State.GROUND:
		return
	if talking != null:
		if a.global_position.distance_to(talking.global_position) > 4.0 or _use_pressed() or Input.is_action_just_pressed("ui_cancel"):
			close_talk()
		return
	var who = game.npc_near(a)
	if who != null:
		prompt = _key_hint() + " Talk to %s" % who.display_name
		if _use_pressed():
			open_talk(who)
		return
	if game.warming_up():                               # warm-up: zip lines yes, loot no
		var wz = game.events.zip_near(a)
		if wz != null:
			prompt = _key_hint() + " Ride the zip line"
			if _use_pressed():
				a.start_zip(wz[0], wz[1])
		return
	var vault = game.bosses.vault_near(a) if game.bosses != null else null
	if vault != null:                                   # a keycard vault door
		var has: bool = game.bosses.keycard_slot(a, vault) >= 0
		prompt = (_key_hint() + " Open vault") if has else ("Needs " + Items.DEFS[vault.card].name)
		if has and _use_pressed():
			game.bosses.open_vault(vault, a)
		return
	var c = game.nearest_container(a.global_position, 2.8)
	if c != null:
		prompt = _key_hint() + " Open %s" % {"chest": "chest", "ammo_box": "ammo box", "supply_drop": "supply drop"}[c.kind]
		if _use_pressed():
			game.open_container(c, a)
		return
	var bench = game.events.bench_near(a)
	if bench != null:
		var it = a.item()
		if it == null or Items.def(it).kind != "weapon":
			prompt = "Hold a weapon to upgrade it here"
		elif it.rarity >= 4:
			prompt = "%s is already %s" % [Items.def(it).name, Items.RARITY_NAMES[it.rarity]]
		else:
			var cost: int = game.events.upgrade_cost(it.rarity)
			prompt = _key_hint() + " Upgrade to %s  ·  %d gold%s" % [Items.RARITY_NAMES[it.rarity + 1], cost, "" if a.gold >= cost else "  (you have %d)" % a.gold]
			if _use_pressed():
				game.events.upgrade(a)
		return
	var zl = game.events.zip_near(a)
	if zl != null:
		prompt = _key_hint() + " Ride the zip line"
		if _use_pressed():
			a.start_zip(zl[0], zl[1])
		return
	var p = game.nearest_pickup(a, 2.2)
	if p != null and p.item.has("id") and not a.wants(p.item):
		prompt = _key_hint() + " Swap for %s" % Items.label(p.item)
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
	if marker_beam != null and marker_beam.visible:          # the beam fades as you get close, so it never blinds you
		var md := Vector2(marker.x - s.global_position.x, marker.z - s.global_position.z).length()
		(marker_beam.material_override as StandardMaterial3D).albedo_color.a = clampf(md / 160.0, 0.08, 0.45)
	if not a.alive():
		yaw = lerp_angle(yaw, s.aim_yaw, clampf(delta * 5.0, 0.0, 1.0))
		pitch = lerpf(pitch, -0.18, clampf(delta * 3.0, 0.0, 1.0))
	var aiming: bool = a.alive() and (not demo or force_aim) and a.build_piece == "" and (Input.is_action_pressed("aim") or (touch != null and touch.aim) or force_aim) and a.state == Actor.State.GROUND
	zoom = move_toward(zoom, 1.0 if aiming else 0.0, delta * 7.0)
	var it = s.item()
	var scoped: bool = it != null and it.id == "sniper_rifle"
	cam.fov = lerpf(75.0, 22.0 if scoped else 48.0, zoom) + 9.0 * s.tsprint_k * (1.0 - zoom)     # tactical sprint kicks the FOV out
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var back := 4.6
	cam_up = lerpf(cam_up, 1.4 if (s.crouched or s.sliding) else 1.9, clampf(delta * 9.0, 0.0, 1.0))
	var up := cam_up
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


func _enemy_in_sights() -> bool:
	## Auto fire: a gun with ammo out and an enemy under the crosshair, within the gun's range.
	var it = a.item()
	if it == null or Items.def(it).kind != "weapon" or a.reloading > 0.0 or game.warming_up():
		return false
	var d: Dictionary = Items.def(it)
	if it.loaded <= 0 and int(a.ammo[d.ammo]) <= 0:
		return false
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var res = game.ray(from + dir * 2.0, from + dir * float(d.range), a)
	if res.is_empty() or not (res.collider is Actor):
		return false
	var o: Actor = res.collider
	return o.alive() and o != game.hired and not o.is_npc


func aim_point() -> Vector3:
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var res = game.ray(from + dir * 2.0, from + dir * 420.0, a)
	return res.position if not res.is_empty() else from + dir * 420.0


# ----------------------------------------------------------------------------- the map and its marker

func toggle_map() -> void:
	## The full map frees the mouse so a spot can be clicked; closing it gives the mouse back to the camera.
	show_map = not show_map
	if touch != null or demo:
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if show_map else Input.MOUSE_MODE_CAPTURED


func map_tap(screen: Vector2) -> void:
	## Click or tap on the full map: mark that spot, or clear the mark when the tap lands on it.
	var hud = game.hud
	if hud == null or not hud.fullmap_rect.has_point(screen):
		return
	var w: Vector2 = hud.map_screen_to_world(screen)
	if marker != Vector3.INF and Vector2(marker.x, marker.z).distance_to(w) < 14.0:
		clear_marker()
		return
	set_marker(w)


func set_marker(w: Vector2) -> void:
	marker = Vector3(w.x, game.terrain.height(w.x, w.y), w.y)
	if marker_beam == null:
		# a tall, thin, glowing column so the spot is easy to steer to from the blimp and while skydiving
		marker_beam = MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.5
		cyl.bottom_radius = 1.5
		cyl.height = 300.0
		cyl.radial_segments = 10
		cyl.rings = 1
		marker_beam.mesh = cyl
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1.0, 0.82, 0.18, 0.45)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		marker_beam.material_override = mat
		marker_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		game.add_child(marker_beam)
	marker_beam.global_position = marker + Vector3(0, 150.0, 0)
	marker_beam.visible = true
	game.sfx("hit_marker", Vector3.INF)


func clear_marker() -> void:
	marker = Vector3.INF
	if marker_beam != null:
		marker_beam.visible = false
