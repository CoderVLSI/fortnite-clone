## Autoload "Settings": player options saved to user://settings.cfg and applied on start.
## Mouse sensitivity, invert Y, key bindings, graphics (fullscreen, shadows, MSAA, render scale, FPS cap), master volume, bot difficulty.
extends Node

const PATH := "user://settings.cfg"
const BASE_SENS := 0.0026
## Rebindable actions, in the order shown in the settings panel: [action, label].
const ACTIONS := [
	["move_forward", "Move forward"], ["move_back", "Move back"], ["move_left", "Move left"], ["move_right", "Move right"],
	["jump", "Jump"], ["sprint", "Sprint"], ["crouch", "Crouch / slide"], ["interact", "Interact / loot"],
	["reload", "Reload"], ["map", "Map"], ["pickaxe", "Pickaxe"], ["drop_item", "Drop item"],
	["edit", "Edit building"], ["build_wall", "Build wall"], ["build_floor", "Build floor"],
	["build_stairs", "Build stairs"], ["build_cone", "Build cone"], ["emote", "Emote wheel"], ["inventory", "Inventory"], ["fire", "Fire"], ["aim", "Aim"],
]
const MSAA_VALUES := [0, 2, 4]
const FPS_VALUES := [30, 60, 120, 0]
const DIFFICULTIES := ["easy", "normal", "sweaty"]

var sensitivity := 1.0                   # multiplier on BASE_SENS
var invert_y := false
var fullscreen := false
var shadows := true
var msaa := 2
var render_scale := 100
var fps_limit := 0
var volume := 1.0
var bot_difficulty := "normal"           # one of DIFFICULTIES; --difficulty=<value> overrides it for a run without saving
var bindings := {}                       # action -> {"k": physical keycode} or {"m": mouse button}
var defaults := {}                       # action -> Array[InputEvent], captured from project.godot
var _sun: DirectionalLight3D
var _saved_difficulty := "normal"        # what the file holds while a --difficulty= override is active
var _cli_difficulty := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in ACTIONS:
		defaults[a[0]] = InputMap.action_get_events(a[0]).duplicate()
	load_file()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--difficulty=") and a.get_slice("=", 1) in DIFFICULTIES:
			_cli_difficulty = a.get_slice("=", 1)
			bot_difficulty = _cli_difficulty
	apply_all()
	get_tree().node_added.connect(_on_node_added)


static func difficulty_label(d: String) -> String:
	return d.capitalize() if d in DIFFICULTIES else "Normal"


func sens() -> float:
	return BASE_SENS * sensitivity


func _on_node_added(n: Node) -> void:
	if n is DirectionalLight3D and n.name == "Sun":                # the island's sun appears when a match loads
		_sun = n
		_apply_shadows()


# ----------------------------------------------------------------------------- persistence

func load_file() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	var d := str(cf.get_value("gameplay", "bot_difficulty", "normal"))
	bot_difficulty = d if d in DIFFICULTIES else "normal"
	_saved_difficulty = bot_difficulty
	sensitivity = clampf(float(cf.get_value("controls", "sensitivity", 1.0)), 0.1, 4.0)
	invert_y = bool(cf.get_value("controls", "invert_y", false))
	fullscreen = bool(cf.get_value("graphics", "fullscreen", false))
	shadows = bool(cf.get_value("graphics", "shadows", true))
	var m := int(cf.get_value("graphics", "msaa", 2))
	msaa = m if m in MSAA_VALUES else 2
	render_scale = clampi(int(cf.get_value("graphics", "render_scale", 100)), 50, 100)
	var f := int(cf.get_value("graphics", "fps_limit", 0))
	fps_limit = f if f in FPS_VALUES else 0
	volume = clampf(float(cf.get_value("audio", "volume", 1.0)), 0.0, 1.0)
	var b = cf.get_value("controls", "bindings", {})
	if b is Dictionary:
		bindings = b
		for act in bindings:
			if InputMap.has_action(act):
				_set_event(act, _event_from(bindings[act]))


func save_file() -> void:
	var cf := ConfigFile.new()
	cf.set_value("controls", "sensitivity", sensitivity)
	cf.set_value("controls", "invert_y", invert_y)
	cf.set_value("controls", "bindings", bindings)
	cf.set_value("graphics", "fullscreen", fullscreen)
	cf.set_value("graphics", "shadows", shadows)
	cf.set_value("graphics", "msaa", msaa)
	cf.set_value("graphics", "render_scale", render_scale)
	cf.set_value("graphics", "fps_limit", fps_limit)
	cf.set_value("audio", "volume", volume)
	if _cli_difficulty != "" and bot_difficulty == _cli_difficulty:
		cf.set_value("gameplay", "bot_difficulty", _saved_difficulty)
	else:
		_saved_difficulty = bot_difficulty
		_cli_difficulty = ""
		cf.set_value("gameplay", "bot_difficulty", bot_difficulty)
	cf.save(PATH)


# ----------------------------------------------------------------------------- bindings

func _event_from(d: Dictionary) -> InputEvent:
	if d.has("m"):
		var m := InputEventMouseButton.new()
		m.button_index = int(d.m) as MouseButton
		return m
	var k := InputEventKey.new()
	k.physical_keycode = int(d.get("k", 0)) as Key
	return k


func _set_event(action: String, ev: InputEvent) -> void:
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, ev)


func event_text(action: String) -> String:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var code: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
			return OS.get_keycode_string(code)
		if ev is InputEventMouseButton:
			match ev.button_index:
				MOUSE_BUTTON_LEFT: return "Left mouse"
				MOUSE_BUTTON_RIGHT: return "Right mouse"
				MOUSE_BUTTON_MIDDLE: return "Middle mouse"
				_: return "Mouse %d" % ev.button_index
	return "-"


func _dict_of(ev: InputEvent) -> Dictionary:
	if ev is InputEventMouseButton:
		return {"m": int(ev.button_index)}
	return {"k": int(ev.physical_keycode)}


func rebind(action: String, ev: InputEvent) -> void:
	## Accepts a key press or mouse button; an action already using that input gets this action's old input (a swap).
	var d := {}
	if ev is InputEventKey:
		d = {"k": int(ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode)}
	elif ev is InputEventMouseButton:
		d = {"m": int(ev.button_index)}
	else:
		return
	var new_ev := _event_from(d)
	var old: Array = InputMap.action_get_events(action)
	for a in ACTIONS:
		var other: String = a[0]
		if other != action and InputMap.action_has_event(other, new_ev) and old.size() > 0:
			_set_event(other, old[0])
			bindings[other] = _dict_of(old[0])
	_set_event(action, new_ev)
	bindings[action] = d
	save_file()


func reset_bindings() -> void:
	bindings.clear()
	for act in defaults:
		InputMap.action_erase_events(act)
		for ev in defaults[act]:
			InputMap.action_add_event(act, ev)
	save_file()


# ----------------------------------------------------------------------------- applying

func apply_all() -> void:
	apply_graphics()
	apply_volume()


func apply_graphics() -> void:
	if DisplayServer.get_name() != "headless":
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want:
			DisplayServer.window_set_mode(want)
	var vp := get_tree().root
	if not OS.has_feature("mobile"):                               # phones keep the game's own no-MSAA setting
		vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][MSAA_VALUES.find(msaa)]
	vp.scaling_3d_scale = render_scale / 100.0
	Engine.max_fps = fps_limit
	_apply_shadows()


func _apply_shadows() -> void:
	if is_instance_valid(_sun) and not OS.has_feature("mobile"):
		_sun.shadow_enabled = shadows


func apply_volume() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(volume) if volume > 0.001 else -80.0)
