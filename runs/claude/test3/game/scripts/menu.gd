## The lobby: a battle-royale front end. Your character stands on a lit stage in the middle (drag to spin it); a top
## bar has the tabs (PLAY, LOCKER, CAREER, SETTINGS), your level and quit; the PLAY page has the mode card, the bot
## difficulty and a big PLAY button that matchmakes and counts down into the match. The lobby music plays throughout.
## Test / tool flags (--autotest, --buildtest, --demo, --shots=, ...) skip all of this and start the match directly.
## --menushot=<dir> saves lobby / locker / career / settings / matchmaking captures and quits.
extends Node3D

const GAME_SCENE := "res://scenes/game.tscn"
const SKIP_FLAGS := ["--demo", "--autotest", "--buildtest", "--movetest", "--eventtest", "--poses", "--crosshairs", "--soundtest", "--invtest", "--invshot", "--profile"]
const SKIP_PREFIXES := ["--shots=", "--summarytest="]
const NEWS := ["Snowy mountains and a desert with mesas: the island is now 800 m across",
	"50 players per match", "New guns: SMG, tactical shotgun, burst rifle, hunting rifle",
	"New heals: bandages, hydro juice and the Mega Flask", "Zip lines up onto the mesas, and rifts in every town"]

var pivot: Node3D
var stage_char: Character
var ui: Control
var lobby_box: Control                  # the PLAY page
var locker_box: Control
var career_box: Control
var settings: Control
var tabs := {}                          # name -> tab button
var tab_bar: HBoxContainer
var ready_btn: Button
var back_btn: Button                    # the LOCKER tab: like every other way out of PLAY, locked while matchmaking
var bots_btn: Button
var status_label: Label
var level_label: Label
var xp_bar: ProgressBar
var name_plate: Label3D
var countdown := -1.0
var matchmaking := -1.0
var shot_dir := ""
var drag := false
var spin := 0.0
var emote_t := 6.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a in SKIP_FLAGS or SKIP_PREFIXES.any(func(p: String) -> bool: return a.begins_with(p)):
			get_tree().change_scene_to_file.call_deferred(GAME_SCENE)
			return
		if a.begins_with("--menushot="):
			shot_dir = a.get_slice("=", 1)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_stage()
	_build_ui()
	_show_lobby()
	Settings.play_music("lobby", -4.0, 1.5)
	if shot_dir != "":
		_run_shots()


# ----------------------------------------------------------------------------- the stage

func _mat(c: Color, metal := 0.0, rough := 0.6, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m


func _cyl(parent: Node3D, r_top: float, r_bot: float, h: float, y: float, mat: Material, segs := 64) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = segs
	cm.material = mat
	mi.mesh = cm
	mi.position.y = y
	parent.add_child(mi)
	return mi


func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.1, 0.22, 0.5)
	sm.sky_horizon_color = Color(0.55, 0.62, 0.95)
	sm.ground_horizon_color = Color(0.4, 0.42, 0.7)
	sm.ground_bottom_color = Color(0.08, 0.1, 0.2)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()                          # warm key light from the front left
	key.rotation_degrees = Vector3(-32, 28, 0)
	key.light_color = Color(1.0, 0.9, 0.78)
	key.light_energy = 1.0
	key.shadow_enabled = true
	add_child(key)
	var rim := DirectionalLight3D.new()                          # cool rim light so the silhouette reads
	rim.rotation_degrees = Vector3(-18, 200, 0)
	rim.light_color = Color(0.45, 0.65, 1.0)
	rim.light_energy = 1.1
	add_child(rim)
	var spot := SpotLight3D.new()                                # a spotlight on the stage
	spot.position = Vector3(0, 6.5, 2.5)
	spot.rotation_degrees = Vector3(-68, 0, 0)
	spot.spot_range = 12.0
	spot.spot_angle = 24.0
	spot.light_energy = 3.0
	spot.light_color = Color(1.0, 0.95, 0.85)
	add_child(spot)
	# the floor: a dark disc with light rings, and the stage
	_cyl(self, 22, 22, 0.2, -0.75, _mat(Color(0.07, 0.08, 0.16), 0.0, 0.9))
	for r in [3.4, 5.2, 7.6]:
		var ring := _cyl(self, r, r, 0.03, -0.63, _mat(Color(0.35, 0.45, 1.0), 0.0, 0.4, 1.4))
		ring.scale = Vector3(1, 1, 1)
		var hole := _cyl(self, r - 0.06, r - 0.06, 0.04, -0.62, _mat(Color(0.07, 0.08, 0.16), 0.0, 0.9))
		hole.name = "ring_gap"
	pivot = Node3D.new()
	add_child(pivot)
	_cyl(pivot, 1.9, 2.05, 0.35, -0.5, _mat(Color(0.16, 0.18, 0.26), 0.2, 0.6))
	_cyl(pivot, 1.84, 1.84, 0.06, -0.3, _mat(MenuUI.ACCENT, 0.0, 0.4, 2.2))
	_cyl(pivot, 1.6, 1.7, 0.28, -0.16, _mat(Color(0.24, 0.26, 0.34), 0.1, 0.7))
	_cyl(pivot, 1.35, 1.4, 0.06, 0.0, _mat(Color(0.32, 0.34, 0.42), 0.0, 0.8))
	# drifting light motes behind the stage
	var motes := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(7, 3, 2)
	pm.direction = Vector3(0, 1, 0)
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.35
	pm.gravity = Vector3.ZERO
	motes.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.06, 0.06)
	qm.material = _mat(Color(0.7, 0.8, 1.0), 0.0, 1.0, 3.0)
	(qm.material as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	motes.draw_pass_1 = qm
	motes.amount = 60
	motes.lifetime = 8.0
	motes.position = Vector3(0, 2.5, -3.5)
	add_child(motes)
	_dress_character()
	name_plate = Label3D.new()
	name_plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_plate.font_size = 46
	name_plate.outline_size = 12
	name_plate.position = Vector3(0, 1.98, 0)
	name_plate.font_size = 26
	name_plate.no_depth_test = true
	add_child(name_plate)
	var cam := Camera3D.new()
	cam.fov = 36.0
	add_child(cam)
	cam.position = Vector3(0.35, 1.3, 4.3)                        # close, so the character fills the stage
	cam.look_at(Vector3(0.35, 0.95, 0.0))
	cam.current = true


func _dress_character() -> void:
	## The player's own body, in the outfit picked in the locker (the same Character the match uses).
	if stage_char:
		stage_char.queue_free()
	var o: Array = Settings.OUTFITS[Settings.outfit]
	stage_char = Character.new()
	pivot.add_child(stage_char)
	stage_char.build(o[1], o[2], Color.WHITE, o[3])
	stage_char.position.y = 0.04
	stage_char.rotation.y = PI                                  # the body faces -Z; turn it to the camera
	stage_char.hold("")
	stage_char._play("Idle", 1.0)
	emote_t = 6.0


func _process(delta: float) -> void:
	if pivot and not drag:
		spin = lerpf(spin, 0.0, delta * 2.0)
		pivot.rotation.y = lerp_angle(pivot.rotation.y, 0.0, delta * 1.5) + spin * delta
	# now and then the character dances or nods while you wait
	if stage_char:
		emote_t -= delta
		if emote_t <= 0.0:
			if stage_char.clip == stage_char.clip_map.get("Idle", "Idle"):
				var e: String = ["x/Michelle_SambaDance", "x/Xbot_agree"][randi() % 2]
				stage_char._play(e, 1.0)
				emote_t = 5.0 if e.ends_with("Dance") else 2.0
			else:
				stage_char._play("Idle", 1.0)
				emote_t = randf_range(8.0, 14.0)
	if name_plate:
		name_plate.text = "You  ·  LV %d" % Settings.level()
	if matchmaking > 0.0:
		matchmaking -= delta
		status_label.text = "Finding a match%s  %d/50" % [".".repeat(1 + int(Time.get_ticks_msec() / 400) % 3), mini(50, 50 - int(matchmaking * 14.0))]
		if matchmaking <= 0.0:
			matchmaking = -1.0
			countdown = 3.0
	if countdown > 0.0:
		countdown -= delta
		status_label.text = "MATCH STARTS IN  %d" % maxi(ceili(countdown), 1)
		if countdown <= 0.0:
			countdown = -1.0
			get_tree().change_scene_to_file(GAME_SCENE)


func _unhandled_input(e: InputEvent) -> void:
	## Drag on the stage to spin the character.
	if not lobby_box or not (lobby_box.visible or locker_box.visible):
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		drag = e.pressed
	elif e is InputEventScreenTouch:
		drag = e.pressed
	elif drag and (e is InputEventMouseMotion or e is InputEventScreenDrag):
		pivot.rotation.y += e.relative.x * 0.01
		spin = e.relative.x * 0.6


# ----------------------------------------------------------------------------- UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.theme = MenuUI.make_theme()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	_build_top_bar()
	_build_play_page()
	_build_locker_page()
	_build_career_page()
	settings = preload("res://scripts/settings_panel.gd").new()
	settings.visible = false
	settings.closed.connect(func() -> void:
		settings.visible = false
		_show_lobby())
	ui.add_child(settings)


func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 72
	bar.add_theme_stylebox_override("panel", MenuUI.box(Color(0.03, 0.05, 0.1, 0.82), Color(0, 0, 0, 0), 0, 8.0))
	ui.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)
	var logo := HBoxContainer.new()
	logo.add_theme_constant_override("separation", 6)
	logo.add_child(MenuUI.label("ISLAND", 30, Color.WHITE))
	logo.add_child(MenuUI.label("ROYALE", 30, MenuUI.ACCENT))
	row.add_child(logo)
	row.add_child(_gap(28))
	tab_bar = HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 4)
	row.add_child(tab_bar)
	for t in [["PLAY", _show_lobby], ["LOCKER", _show_locker], ["CAREER", _show_career], ["SETTINGS", _show_settings]]:
		var b := Button.new()
		b.text = t[0]
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(130, 52)
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(t[1])
		tab_bar.add_child(b)
		tabs[t[0]] = b
	back_btn = tabs["LOCKER"]
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(fill)
	# level badge with XP progress
	var lv := VBoxContainer.new()
	lv.custom_minimum_size = Vector2(170, 0)
	lv.alignment = BoxContainer.ALIGNMENT_CENTER
	level_label = MenuUI.label("", 20, Color.WHITE)
	lv.add_child(level_label)
	xp_bar = ProgressBar.new()
	xp_bar.show_percentage = false
	xp_bar.custom_minimum_size = Vector2(160, 8)
	xp_bar.max_value = Settings.XP_PER_LEVEL
	var fg := StyleBoxFlat.new()
	fg.bg_color = MenuUI.ACCENT
	fg.set_corner_radius_all(4)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.15)
	bg.set_corner_radius_all(4)
	xp_bar.add_theme_stylebox_override("fill", fg)
	xp_bar.add_theme_stylebox_override("background", bg)
	lv.add_child(xp_bar)
	row.add_child(lv)
	var quit := MenuUI.button("Quit", 18, Vector2(90, 46))
	quit.pressed.connect(func() -> void: get_tree().quit())
	row.add_child(quit)
	_refresh_level()


func _gap(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	return c


func _refresh_level() -> void:
	level_label.text = "LEVEL %d    %d XP" % [Settings.level(), int(Settings.career.xp) % Settings.XP_PER_LEVEL]
	xp_bar.value = int(Settings.career.xp) % Settings.XP_PER_LEVEL


func _card(anchor: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", MenuUI.box(Color(0.04, 0.06, 0.12, 0.86), Color(1, 1, 1, 0.12), 12, 14.0))
	p.set_anchors_preset(anchor)
	if anchor in [Control.PRESET_CENTER_RIGHT, Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT]:
		p.grow_horizontal = Control.GROW_DIRECTION_BEGIN          # wide content grows into the screen, not off it
	return p


func _build_play_page() -> void:
	lobby_box = Control.new()
	lobby_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lobby_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(lobby_box)
	# bottom right: the mode card, the bot difficulty, the status line and the big PLAY button
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	col.offset_left = -470
	col.offset_top = -330
	col.offset_right = -36
	col.offset_bottom = -36
	col.alignment = BoxContainer.ALIGNMENT_END
	col.add_theme_constant_override("separation", 10)
	lobby_box.add_child(col)
	var mode := _card(Control.PRESET_TOP_LEFT)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 4)
	mode.add_child(mv)
	mv.add_child(MenuUI.label("SOLO", 34, Color.WHITE))
	mv.add_child(MenuUI.label("Battle royale  ·  50 players  ·  last one standing wins", 16, MenuUI.DIM))
	bots_btn = MenuUI.button("", 18, Vector2(0, 40))
	bots_btn.pressed.connect(_cycle_bots)
	mv.add_child(bots_btn)
	_refresh_bots_btn()
	col.add_child(mode)
	status_label = MenuUI.label("", 22, Color.WHITE)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(status_label)
	ready_btn = Button.new()
	ready_btn.text = "PLAY"
	ready_btn.custom_minimum_size = Vector2(0, 104)
	ready_btn.add_theme_font_size_override("font_size", 52)
	ready_btn.add_theme_color_override("font_color", Color(0.08, 0.06, 0.02))
	ready_btn.add_theme_color_override("font_hover_color", Color(0.08, 0.06, 0.02))
	ready_btn.add_theme_color_override("font_disabled_color", Color(0.08, 0.06, 0.02, 0.8))
	ready_btn.add_theme_stylebox_override("normal", MenuUI.box(MenuUI.ACCENT, Color(1, 0.85, 0.5), 10))
	ready_btn.add_theme_stylebox_override("hover", MenuUI.box(MenuUI.ACCENT.lightened(0.15), Color.WHITE, 10))
	ready_btn.add_theme_stylebox_override("pressed", MenuUI.box(MenuUI.ACCENT.darkened(0.15), Color.WHITE, 10))
	ready_btn.add_theme_stylebox_override("disabled", MenuUI.box(MenuUI.ACCENT.darkened(0.3), Color(0, 0, 0, 0), 10))
	ready_btn.add_theme_stylebox_override("focus", MenuUI.box(Color(0, 0, 0, 0), Color.WHITE, 10))
	ready_btn.pressed.connect(_on_ready)
	col.add_child(ready_btn)
	# bottom left: what's new
	var news := _card(Control.PRESET_BOTTOM_LEFT)
	news.offset_left = 36
	news.offset_top = -270
	news.offset_right = 520
	news.offset_bottom = -36
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 6)
	news.add_child(nv)
	nv.add_child(MenuUI.label("WHAT'S NEW", 22, MenuUI.ACCENT))
	for n in NEWS:
		var l := MenuUI.label("•  " + n, 16, MenuUI.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nv.add_child(l)
	lobby_box.add_child(news)
	# bottom centre, under the character: emotes (or press B to cycle them)
	var em := HBoxContainer.new()
	em.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	em.offset_left = -230
	em.offset_right = 230
	em.offset_top = -86
	em.offset_bottom = -36
	em.alignment = BoxContainer.ALIGNMENT_CENTER
	em.add_theme_constant_override("separation", 8)
	lobby_box.add_child(em)
	for e in LOBBY_EMOTES:
		var b := MenuUI.button(e[0], 18, Vector2(130, 46))
		b.pressed.connect(lobby_emote.bind(e[1], e[2]))
		em.add_child(b)


const LOBBY_EMOTES := [["Dance", "x/Michelle_SambaDance", 0.0], ["Nod", "x/Xbot_agree", 1.8], ["No way", "x/Xbot_headShake", 2.5]]
var lobby_emote_i := 0


func lobby_emote(clip: String, length: float) -> void:
	## Play an emote on the lobby character; a dance keeps going until the next emote or about 9 s.
	if stage_char == null:
		return
	stage_char._play(clip, 1.0)
	emote_t = 9.0 if length <= 0.0 else length


func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_B and lobby_box != null and lobby_box.visible:
		var em: Array = LOBBY_EMOTES[lobby_emote_i % LOBBY_EMOTES.size()]
		lobby_emote_i += 1
		lobby_emote(em[1], em[2])


func _build_locker_page() -> void:
	locker_box = _card(Control.PRESET_CENTER_RIGHT)
	locker_box.offset_left = -560
	locker_box.offset_right = -36
	locker_box.offset_top = -330
	locker_box.offset_bottom = 330
	ui.add_child(locker_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	locker_box.add_child(v)
	v.add_child(MenuUI.label("LOCKER", 34, Color.WHITE))
	v.add_child(MenuUI.label("Pick an outfit. You wear it in every match.", 16, MenuUI.DIM))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	for i in Settings.OUTFITS.size():
		var o: Array = Settings.OUTFITS[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(110, 108)
		b.focus_mode = Control.FOCUS_NONE
		b.text = o[0]
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.add_theme_font_size_override("font_size", 15)
		var sw := GradientTexture2D.new()                       # a swatch: outfit colour with the accent along the bottom
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.72, 0.73, 1.0])
		g.colors = PackedColorArray([o[1], o[1], o[2], o[2]])
		sw.gradient = g
		sw.fill_from = Vector2(0.5, 0.0)
		sw.fill_to = Vector2(0.5, 1.0)
		sw.width = 56
		sw.height = 56
		b.icon = sw
		b.pressed.connect(func() -> void:
			Settings.outfit = i
			Settings.save_file()
			_dress_character()
			_mark_outfit())
		grid.add_child(b)
	_mark_outfit()


func _mark_outfit() -> void:
	var grid: GridContainer = locker_box.find_children("*", "GridContainer", true, false)[0]
	for i in grid.get_child_count():
		var b: Button = grid.get_child(i)
		var on := i == Settings.outfit
		b.add_theme_stylebox_override("normal", MenuUI.box(Color(0.14, 0.18, 0.26, 0.95), MenuUI.ACCENT if on else Color(1, 1, 1, 0.12), 8, 6.0))


func _build_career_page() -> void:
	career_box = _card(Control.PRESET_CENTER_RIGHT)
	career_box.offset_left = -470
	career_box.offset_right = -36
	career_box.offset_top = -200
	career_box.offset_bottom = 200
	ui.add_child(career_box)


func _fill_career() -> void:
	for c in career_box.get_children():
		c.queue_free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	career_box.add_child(v)
	v.add_child(MenuUI.label("CAREER", 34, Color.WHITE))
	var c: Dictionary = Settings.career
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 60)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	for row in [["Level", str(Settings.level())], ["Matches", str(c.matches)], ["Wins", str(c.wins)], ["Top 10", str(c.top10)],
			["Eliminations", str(c.kills)], ["Best place", "#%d" % c.best if c.best > 0 else "-"], ["Total XP", str(c.xp)]]:
		grid.add_child(MenuUI.label(row[0], 20, MenuUI.DIM))
		grid.add_child(MenuUI.label(row[1], 24, Color.WHITE))


# ----------------------------------------------------------------------------- pages

func _select_tab(name: String) -> void:
	for t in tabs:
		var b: Button = tabs[t]
		b.add_theme_color_override("font_color", MenuUI.ACCENT if t == name else MenuUI.TEXT)
		b.add_theme_stylebox_override("normal", MenuUI.box(Color(1, 1, 1, 0.08) if t == name else Color(0, 0, 0, 0), Color(0, 0, 0, 0), 6, 6.0))
	lobby_box.visible = name == "PLAY"
	locker_box.visible = name == "LOCKER"
	career_box.visible = name == "CAREER"
	settings.visible = name == "SETTINGS"


func _show_lobby() -> void:
	_select_tab("PLAY")
	if countdown < 0.0 and matchmaking < 0.0:
		status_label.text = ""
		ready_btn.disabled = false
		ready_btn.text = "PLAY"
		_set_tabs_locked(false)
	_refresh_level()


func _show_locker() -> void:
	_select_tab("LOCKER")


func _show_career() -> void:
	_fill_career()
	_select_tab("CAREER")


func _show_settings() -> void:
	_select_tab("SETTINGS")


func _set_tabs_locked(on: bool) -> void:
	for t in tabs:
		tabs[t].disabled = on and t != "PLAY"
	bots_btn.disabled = on


func _refresh_bots_btn() -> void:
	bots_btn.text = "Bots: " + Settings.difficulty_label(Settings.bot_difficulty)


func _cycle_bots() -> void:
	var i := Settings.DIFFICULTIES.find(Settings.bot_difficulty)
	Settings.bot_difficulty = Settings.DIFFICULTIES[(i + 1) % Settings.DIFFICULTIES.size()]
	Settings.save_file()
	_refresh_bots_btn()


func _on_ready() -> void:
	## PLAY: a short matchmaking beat, then the countdown into the match.
	ready_btn.disabled = true
	ready_btn.text = "READY!"
	_set_tabs_locked(true)
	matchmaking = 1.6
	status_label.text = "Finding a match..."


# ----------------------------------------------------------------------------- capture mode

func _run_shots() -> void:
	DirAccess.make_dir_recursive_absolute(shot_dir)
	await get_tree().create_timer(1.4).timeout
	_save("menu_lobby_play")
	_show_locker()
	await get_tree().create_timer(0.6).timeout
	_save("menu_locker")
	_show_career()
	await get_tree().create_timer(0.4).timeout
	_save("menu_career")
	_show_settings()
	settings.show_tab(2)
	await get_tree().create_timer(0.4).timeout
	_save("menu_settings_graphics")
	settings.show_tab(3)
	await get_tree().create_timer(0.3).timeout
	_save("menu_settings_audio")
	settings.close()
	_on_ready()
	await get_tree().create_timer(0.8).timeout
	_save("menu_matchmaking")
	await get_tree().create_timer(1.6).timeout
	_save("menu_countdown")
	get_tree().quit()


func _save(nm: String) -> void:
	get_viewport().get_texture().get_image().save_png(shot_dir.path_join(nm + ".png"))
	print("SHOT ", nm)
