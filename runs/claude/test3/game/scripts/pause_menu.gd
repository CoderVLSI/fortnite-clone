## In-match pause overlay: Resume, Settings, Leave match. Pauses the tree and frees the mouse while open.
extends CanvasLayer

var game: Node
var root: Control
var buttons: Control
var settings: Control
var is_open := false


func setup(g: Node) -> void:
	game = g
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	root = Control.new()
	root.theme = MenuUI.make_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	buttons = CenterContainer.new()
	buttons.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(buttons)
	var panel := PanelContainer.new()
	buttons.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	col.add_child(MenuUI.label("PAUSED", 44, MenuUI.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(MenuUI.spacer(6))
	for item in [["Resume", resume], ["Settings", _open_settings], ["Leave match", _leave]]:
		var b := MenuUI.button(item[0], 26, Vector2(340, 60))
		b.pressed.connect(item[1])
		col.add_child(b)
	settings = preload("res://scripts/settings_panel.gd").new()
	settings.visible = false
	settings.closed.connect(func() -> void:
		settings.visible = false
		buttons.visible = true)
	root.add_child(settings)


func open() -> void:
	if is_open or game.over:
		return
	is_open = true
	root.visible = true
	buttons.visible = true
	settings.visible = false
	get_tree().paused = not game.net_active                # a LAN match keeps running for the others
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func resume() -> void:
	if not is_open:
		return
	is_open = false
	root.visible = false
	get_tree().paused = false
	var c = game.controller
	if c and not c.demo and c.touch == null and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _open_settings() -> void:
	buttons.visible = false
	settings.visible = true


func _leave() -> void:
	get_tree().paused = false
	if game.net_active:
		game.netsvc.leave("You left the match")           # the host's copy of you is eliminated; a host leaving ends it for the client
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _input(e: InputEvent) -> void:
	if not is_open:
		return
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_ESCAPE:
		if settings.visible:
			if settings.waiting == "":                   # while rebinding, Esc only cancels the rebind
				settings.close()
		else:
			resume()
		get_viewport().set_input_as_handled()
