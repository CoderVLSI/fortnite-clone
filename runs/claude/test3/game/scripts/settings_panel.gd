## The settings screen, shared by the main menu and the pause menu. Edits the Settings autoload and saves as you go.
extends Control

signal closed

var tabs: TabContainer
var key_buttons := {}                    # action -> Button
var waiting := ""                        # action waiting for a key press
var hint: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 600)
	centre.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	col.add_child(MenuUI.label("SETTINGS", 34, MenuUI.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", 20)
	col.add_child(tabs)
	_build_controls()
	_build_keys()
	_build_graphics()
	_build_audio()
	hint = MenuUI.label("", 16, MenuUI.DIM, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(hint)
	var back := MenuUI.button("Back", 22, Vector2(200, 48))
	back.pressed.connect(close)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(back)


func show_tab(i: int) -> void:
	tabs.current_tab = i


func close() -> void:
	waiting = ""
	Settings.save_file()
	closed.emit()


func _page(title: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.name = title
	v.add_theme_constant_override("separation", 14)
	tabs.add_child(v)
	return v


func _row(parent: Control, text: String, ctl: Control, value_label: Label = null) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var l := MenuUI.label(text, 20)
	l.custom_minimum_size = Vector2(230, 0)
	h.add_child(l)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ctl)
	if value_label:
		value_label.custom_minimum_size = Vector2(80, 0)
		h.add_child(value_label)
	parent.add_child(h)


func _slider(lo: float, hi: float, step: float, v: float, fmt: String, on_change: Callable) -> Array:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = v
	s.custom_minimum_size = Vector2(260, 28)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var vl := MenuUI.label(fmt % v, 20, MenuUI.ACCENT)
	s.value_changed.connect(func(x: float) -> void:
		vl.text = fmt % x
		on_change.call(x))
	return [s, vl]


func _check(text: String, v: bool, on_change: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = v
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(on_change)
	return c


func _options(items: Array, current: int, on_pick: Callable) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(it)
	o.select(current)
	o.focus_mode = Control.FOCUS_NONE
	o.item_selected.connect(on_pick)
	o.custom_minimum_size = Vector2(200, 44)
	return o


func _build_controls() -> void:
	var p := _page("Controls")
	p.add_child(MenuUI.spacer(10))
	var sv := _slider(0.2, 3.0, 0.05, Settings.sensitivity, "%.2fx", func(x: float) -> void: Settings.sensitivity = x)
	_row(p, "Mouse sensitivity", sv[0], sv[1])
	_row(p, "Invert Y axis", _check("", Settings.invert_y, func(on: bool) -> void: Settings.invert_y = on))
	var note := MenuUI.label("Sensitivity applies to mouse look; touch look scales with it too.", 16, MenuUI.DIM)
	p.add_child(note)


func _build_keys() -> void:
	var p := _page("Key bindings")
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size = Vector2(0, 340)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(grid)
	for a in Settings.ACTIONS:
		var act: String = a[0]
		var l := MenuUI.label(a[1], 18)
		l.custom_minimum_size = Vector2(130, 0)
		grid.add_child(l)
		var b := MenuUI.button(Settings.event_text(act), 17, Vector2(150, 34))
		b.pressed.connect(func() -> void: _begin_rebind(act))
		key_buttons[act] = b
		grid.add_child(b)
	var reset := MenuUI.button("Reset to defaults", 18, Vector2(220, 38))
	reset.pressed.connect(func() -> void:
		Settings.reset_bindings()
		waiting = ""
		_refresh_keys())
	reset.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.add_child(reset)


func _refresh_keys() -> void:
	for act in key_buttons:
		key_buttons[act].text = "Press a key..." if act == waiting else Settings.event_text(act)
	hint.text = "Press a key or mouse button for the highlighted action  (Esc or left click cancels)" if waiting != "" else ""


func _begin_rebind(act: String) -> void:
	waiting = act
	_refresh_keys()


func _input(e: InputEvent) -> void:
	if waiting == "" or not is_visible_in_tree():
		return
	if e is InputEventKey and e.pressed and not e.echo:
		if e.physical_keycode != KEY_ESCAPE:
			Settings.rebind(waiting, e)
		waiting = ""
		_refresh_keys()
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index != MOUSE_BUTTON_LEFT and e.button_index <= MOUSE_BUTTON_XBUTTON2:
			Settings.rebind(waiting, e)
			get_viewport().set_input_as_handled()
		waiting = ""
		_refresh_keys()


func _build_graphics() -> void:
	var p := _page("Graphics")
	p.add_child(MenuUI.spacer(4))
	_row(p, "Fullscreen", _check("", Settings.fullscreen, func(on: bool) -> void:
		Settings.fullscreen = on
		Settings.apply_graphics()))
	_row(p, "Shadows", _check("", Settings.shadows, func(on: bool) -> void:
		Settings.shadows = on
		Settings.apply_graphics()))
	_row(p, "Anti-aliasing (MSAA)", _options(["Off", "2x", "4x"], Settings.MSAA_VALUES.find(Settings.msaa), func(i: int) -> void:
		Settings.msaa = Settings.MSAA_VALUES[i]
		Settings.apply_graphics()))
	var rs := _slider(50, 100, 5, Settings.render_scale, "%d%%", func(x: float) -> void:
		Settings.render_scale = int(x)
		Settings.apply_graphics())
	_row(p, "Render scale", rs[0], rs[1])
	_row(p, "FPS limit", _options(["30", "60", "120", "Unlimited"], Settings.FPS_VALUES.find(Settings.fps_limit), func(i: int) -> void:
		Settings.fps_limit = Settings.FPS_VALUES[i]
		Settings.apply_graphics()))


func _build_audio() -> void:
	var p := _page("Audio")
	p.add_child(MenuUI.spacer(10))
	var v := _slider(0, 100, 1, Settings.volume * 100.0, "%d%%", func(x: float) -> void:
		Settings.volume = x / 100.0
		Settings.apply_volume())
	_row(p, "Master volume", v[0], v[1])
