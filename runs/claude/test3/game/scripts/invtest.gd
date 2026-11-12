## Automated check of the inventory screen (Tab), plus a screenshot run.  Run:
##   godot --headless --path <project> -- --invtest
##   godot --path <project> -- --invshot [--touch]      (needs a display; saves PNGs into captures/)
extends Node

var game: Node
var a: Actor
var inv: Control
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


func put(p: Vector3) -> void:
	a.state = Actor.State.GROUND
	a.global_position = p
	a.velocity = Vector3.ZERO
	a.fall_start = p.y
	a.in_move = Vector2.ZERO
	await frames(6)


func key(code: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	await frames(2)


func mouse_at(i: int, off := Vector2(75, 90)) -> Vector2:
	return inv._origin() + (inv.slot_rect(i).position + off) * inv._scale()


func drag(from: int, to_pos: Vector2) -> void:
	inv.press_down(mouse_at(from))
	inv.press_move(mouse_at(from) + Vector2(30, 0))
	inv.press_move(to_pos)
	inv.press_up(to_pos)


func ids() -> Array:
	var r: Array = []
	for s in a.slots:
		r.append(s.id if s != null else "-")
	return r


func loadout() -> void:
	a.slots = [Items.make("assault_rifle", 3), Items.make("shotgun", 1), Items.make("medkit", 0, 2), Items.make("small_shield", 0, 4), Items.make("grenade", 0, 3)]
	a.slots[0].loaded = 22
	a.ammo = {"light": 120, "medium": 85, "heavy": 6, "shells": 24, "rockets": 2}
	a.mats = {"wood": 340, "brick": 120, "metal": 75}
	a.hp = 72.0
	a.shield = 45.0
	a.select(0)


func _ready() -> void:
	await frames(5)
	a = game.player
	inv = game.controller.inv
	for o in game.actors:
		if o != a:
			o.process_mode = Node.PROCESS_MODE_DISABLED
	var E: WorldEvents = game.events
	await put(E._dry_spot(game.terrain.village + Vector2(20, 8)) + Vector3(0, 0.1, 0))
	loadout()
	await frames(2)
	if OS.get_cmdline_user_args().has("--invshot"):
		await shots()
		return
	# ---------------------------------------------------------------- open / close
	check("starts closed", not inv.is_open and not game.controller.inv_open())
	await key(KEY_TAB)
	check("Tab opens it", inv.is_open and game.controller.inv_open())
	await key(KEY_TAB)
	check("Tab closes it", not inv.is_open)
	await key(KEY_TAB)
	await key(KEY_ESCAPE)
	check("Esc closes it without pausing", not inv.is_open and not game.pause_menu.is_open and not get_tree().paused)
	inv.open()
	var t0: float = game.match_time
	await frames(30)
	check("the match keeps running while open", game.match_time > t0 + 0.3 and not get_tree().paused)
	# ---------------------------------------------------------------- swap
	var held_before: Dictionary = a.slots[0]
	await drag(0, mouse_at(2))
	check("dragging slot 1 onto 3 swaps them", ids() == ["medkit", "shotgun", "assault_rifle", "small_shield", "grenade"], str(ids()))
	check("the held item stays active (slot moved 0 -> 2)", a.active == 2 and a.item() == held_before)
	await drag(1, mouse_at(3))
	check("swapping two other slots leaves the active one alone", a.active == 2 and ids()[1] == "small_shield" and ids()[3] == "shotgun")
	await drag(2, mouse_at(1))
	check("swapping onto the active slot moves it", a.active == 1 and a.item() == held_before)
	a.slots[4] = null
	await drag(0, mouse_at(4))
	check("swapping into an empty slot moves the item", ids()[0] == "-" and ids()[4] == "medkit", str(ids()))
	inv.press_down(mouse_at(3))
	inv.press_up(mouse_at(3))
	check("a plain click selects the slot", a.active == 3)
	# ---------------------------------------------------------------- drop
	var n_pick: int = game.pickups.size()
	var dropped = a.slots[3]
	await drag(3, Vector2(8, 8))
	check("dragging out of the panel drops the item", a.slots[3] == null and game.pickups.size() == n_pick + 1)
	check("the dropped pickup holds that item", game.pickups.back().item == dropped)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_RIGHT
	e.pressed = true
	e.position = mouse_at(4)
	n_pick = game.pickups.size()
	inv._input(e)                                  # headless drops synthetic mouse buttons
	await frames(2)
	check("right-click drops the slot", a.slots[4] == null and game.pickups.size() == n_pick + 1, str(ids()))
	# ---------------------------------------------------------------- touch: tap, tap, drop
	loadout()
	inv.touch_mode = true
	inv.press_down(mouse_at(0))
	inv.press_up(mouse_at(0))
	check("touch: first tap picks the slot", inv.sel == 0 and a.active == 0)
	inv.press_down(mouse_at(2))
	inv.press_up(mouse_at(2))
	check("touch: second tap swaps", ids()[0] == "medkit" and ids()[2] == "assault_rifle" and a.active == 2 and inv.sel == -1, str(ids()))
	inv.press_down(mouse_at(3))
	inv.press_up(mouse_at(3))
	var bp: Vector2 = inv._origin() + inv._btn_rect("drop").get_center() * inv._scale()
	n_pick = game.pickups.size()
	inv.press_down(bp)
	inv.press_up(bp)
	check("touch: Drop button drops the selected slot", a.slots[3] == null and game.pickups.size() == n_pick + 1 and inv.sel == -1)
	inv.touch_mode = false
	# ---------------------------------------------------------------- tooltips
	var ok := true
	for it in [Items.make("pistol", 2), Items.make("medkit"), Items.make("small_shield", 0, 2), Items.make("grenade"), Items.make("launch_pad")]:
		ok = ok and inv.tip_lines(it).size() > 0
	check("every item kind has tooltip lines", ok)
	# ---------------------------------------------------------------- input blocking
	a.select(-1)
	inv.close()
	Input.action_press("fire")
	await frames(4)
	check("fire works with the inventory closed", a.in_fire)
	inv.open()
	await frames(4)
	check("fire is ignored while open", not a.in_fire)
	var yaw0: float = game.controller.yaw
	game.controller._unhandled_input(_motion())
	check("the camera does not turn while open", is_equal_approx(yaw0, game.controller.yaw) or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)
	Input.action_release("fire")
	inv.close()
	await frames(4)
	check("closing leaves the game running normally", not a.in_fire and not inv.is_open)
	print("INVTEST\n" + "\n".join(lines))
	print("INVTEST %s (%d checks, %d failed)" % ["OK" if fails == 0 else "FAILED", lines.size(), fails])
	get_tree().quit()


func _motion() -> InputEventMouseMotion:
	var m := InputEventMouseMotion.new()
	m.relative = Vector2(200, 0)
	return m


func shots() -> void:
	## Screenshot run: opens the inventory with a loadout, hovers a slot and saves PNGs.
	var dir := ProjectSettings.globalize_path("res://").path_join("../captures")
	var tag := "%dx%d" % [get_viewport().size.x, get_viewport().size.y]
	if inv.touch_mode:
		tag += "_touch"
	var fresh := OS.get_cmdline_user_args().has("--newitems")        # --newitems: show the newest weapons and heals
	if fresh:
		a.slots = [Items.make("smg", 2), Items.make("burst_rifle", 3), Items.make("hunting_rifle", 1), Items.make("bandages", 0, 12), Items.make("mega_flask")]
		tag += "_new"
	inv.open()
	await frames(8)
	get_viewport().get_texture().get_image().save_png(dir.path_join("inv_%s.png" % tag))
	inv.hover = 0
	inv.mouse = mouse_at(0, Vector2(100, 100))
	if inv.touch_mode:
		inv.sel = 1
	else:
		get_viewport().warp_mouse(inv.mouse)
	await frames(8)
	get_viewport().get_texture().get_image().save_png(dir.path_join("inv_%s_hover.png" % tag))
	if fresh:
		inv.close()
		var ids := ["smg", "tactical_shotgun", "burst_rifle", "hunting_rifle", "bandages", "hydro_juice", "mega_flask"]
		var p0: Vector3 = a.global_position
		a.aim_yaw = 0.0
		game.controller.yaw = 0.0
		game.controller.pitch = -0.45
		for i in ids.size():
			var it := Items.make(ids[i], 1)
			game.spawn_pickup(it, p0 + Vector3((i - 3) * 0.9, 0, -3.2))
		await frames(40)
		get_viewport().get_texture().get_image().save_png(dir.path_join("ground_new.png"))
		a.slots = [Items.make("hydro_juice", 0, 2), Items.make("tactical_shotgun", 1), null, null, null]
		a.select(1)
		await frames(30)
		game.controller.yaw = 0.5
		get_viewport().get_texture().get_image().save_png(dir.path_join("held_tactical.png"))
	print("INVSHOT ", tag)
	get_tree().quit()
