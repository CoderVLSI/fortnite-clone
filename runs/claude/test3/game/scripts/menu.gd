## Main menu and pre-match lobby. A 3D stage (the Soldier on a slowly turning podium) behind Control-node screens.
## Test / tool flags (--autotest, --buildtest, --demo, --shots=, ...) skip all of this and start the match directly.
## --menushot=<dir> saves menu_main / menu_settings / menu_lobby captures and quits.
extends Node3D

const GAME_SCENE := "res://scenes/game.tscn"
const SKIP_FLAGS := ["--demo", "--autotest", "--buildtest", "--movetest", "--eventtest", "--poses", "--crosshairs", "--soundtest"]
const SKIP_PREFIXES := ["--shots=", "--summarytest="]

var pivot: Node3D
var ui: Control
var main_box: Control
var lobby_box: Control
var settings: Control
var ready_btn: Button
var back_btn: Button
var bots_btn: Button
var countdown_label: Label
var countdown := -1.0
var shot_dir := ""


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
	if shot_dir != "":
		_run_shots()


# ----------------------------------------------------------------------------- 3D backdrop

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


func _cyl(parent: Node3D, r_top: float, r_bot: float, h: float, y: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = 64
	cm.material = mat
	mi.mesh = cm
	mi.position.y = y
	parent.add_child(mi)


func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.16, 0.34, 0.62)
	sm.sky_horizon_color = Color(0.95, 0.72, 0.48)
	sm.ground_horizon_color = Color(0.5, 0.42, 0.38)
	sm.ground_bottom_color = Color(0.1, 0.12, 0.16)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 40, 0)
	sun.light_color = Color(1.0, 0.92, 0.8)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	add_child(sun)
	var rim := DirectionalLight3D.new()                           # cool back light so the silhouette reads
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_color = Color(0.5, 0.7, 1.0)
	rim.light_energy = 0.7
	add_child(rim)
	# ground and podium
	var ground := Node3D.new()
	add_child(ground)
	_cyl(ground, 30, 30, 0.2, -0.75, _mat(Color(0.09, 0.15, 0.11), 0.0, 1.0))
	pivot = Node3D.new()
	add_child(pivot)
	_cyl(pivot, 1.9, 2.0, 0.35, -0.5, _mat(Color(0.2, 0.22, 0.27), 0.0, 0.8))
	_cyl(pivot, 1.55, 1.7, 0.3, -0.18, _mat(Color(0.3, 0.32, 0.37), 0.0, 0.85))
	_cyl(pivot, 1.72, 1.72, 0.06, -0.38, _mat(MenuUI.ACCENT, 0.0, 0.4, 2.0))
	var top := _mat(Color(0.42, 0.44, 0.5), 0.0, 0.85)
	_cyl(pivot, 1.35, 1.4, 0.08, 0.0, top)
	# the character
	var rig: Node3D = (load("res://assets/characters/Soldier.glb") as PackedScene).instantiate()
	rig.position.y = 0.04
	rig.rotation.y = PI                                          # the Soldier faces -Z; turn it toward the camera
	pivot.add_child(rig)
	var ap: AnimationPlayer = rig.find_children("*", "AnimationPlayer", true, false)[0]
	ap.get_animation("Idle").loop_mode = Animation.LOOP_LINEAR
	ap.play("Idle")
	var cam := Camera3D.new()
	cam.fov = 38.0
	add_child(cam)
	cam.position = Vector3(0.3, 1.25, 5.6)
	cam.look_at(Vector3(-0.9, 0.85, 0.0))
	cam.current = true


func _process(delta: float) -> void:
	if pivot:
		pivot.rotate_y(delta * 0.45)
	if countdown > 0.0:
		countdown -= delta
		countdown_label.text = "MATCH STARTS IN  %d" % maxi(ceili(countdown), 1)
		if countdown <= 0.0:
			countdown = -1.0
			get_tree().change_scene_to_file(GAME_SCENE)


# ----------------------------------------------------------------------------- UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.theme = MenuUI.make_theme()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(ui)
	var shade := ColorRect.new()                                 # darkens the left side so text is readable on the sky
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0)
	ui.add_child(shade)
	main_box = _left_column()
	main_box.add_child(MenuUI.label("ISLAND", 92, Color.WHITE))
	var roy := MenuUI.label("ROYALE", 92, MenuUI.ACCENT)
	main_box.add_child(roy)
	main_box.add_child(MenuUI.label("Drop in. Build up. Be the last one standing.", 20, Color(0.9, 0.93, 1.0)))
	main_box.add_child(MenuUI.spacer(24))
	for item in [["Play", _show_lobby], ["Settings", _show_settings], ["Quit", func() -> void: get_tree().quit()]]:
		var b := MenuUI.button(item[0], 28, Vector2(340, 62))
		b.pressed.connect(item[1])
		main_box.add_child(b)
	lobby_box = _left_column()
	lobby_box.visible = false
	lobby_box.add_child(MenuUI.label("LOBBY", 70, Color.WHITE))
	lobby_box.add_child(MenuUI.label("Players: 25 (you + 24 bots)", 28, MenuUI.ACCENT))
	bots_btn = MenuUI.button("", 22, Vector2(200, 46))
	bots_btn.pressed.connect(_cycle_difficulty)
	lobby_box.add_child(bots_btn)
	_refresh_bots_btn()
	lobby_box.add_child(MenuUI.label("Solo  -  last one standing wins", 20, Color(0.9, 0.93, 1.0)))
	lobby_box.add_child(MenuUI.spacer(24))
	ready_btn = MenuUI.button("READY", 44, Vector2(420, 96))
	ready_btn.pressed.connect(_on_ready)
	lobby_box.add_child(ready_btn)
	back_btn = MenuUI.button("Back", 22, Vector2(200, 46))
	back_btn.pressed.connect(_show_main)
	lobby_box.add_child(back_btn)
	countdown_label = MenuUI.label("", 40, Color.WHITE)
	lobby_box.add_child(countdown_label)
	settings = preload("res://scripts/settings_panel.gd").new()
	settings.visible = false
	settings.closed.connect(func() -> void:
		settings.visible = false
		main_box.visible = true)
	ui.add_child(settings)


func _left_column() -> Control:
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	v.offset_left = 80
	v.offset_right = 640
	v.offset_top = 60
	v.offset_bottom = -60
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 14)
	ui.add_child(v)
	return v


func _show_main() -> void:
	countdown = -1.0
	lobby_box.visible = false
	main_box.visible = true


func _refresh_bots_btn() -> void:
	bots_btn.text = "Bots: " + Settings.difficulty_label(Settings.bot_difficulty)


func _cycle_difficulty() -> void:
	var i: int = Settings.DIFFICULTIES.find(Settings.bot_difficulty)
	Settings.bot_difficulty = Settings.DIFFICULTIES[(i + 1) % Settings.DIFFICULTIES.size()]
	Settings.save_file()
	_refresh_bots_btn()


func _show_lobby() -> void:
	main_box.visible = false
	lobby_box.visible = true
	countdown_label.text = ""
	ready_btn.disabled = false
	back_btn.disabled = false
	bots_btn.disabled = false
	_refresh_bots_btn()


func _show_settings() -> void:
	main_box.visible = false
	settings.visible = true


func _on_ready() -> void:
	ready_btn.disabled = true
	back_btn.disabled = true
	bots_btn.disabled = true
	ready_btn.text = "READY!"
	countdown = 3.0
	countdown_label.text = "MATCH STARTS IN  3"


# ----------------------------------------------------------------------------- capture mode

func _run_shots() -> void:
	DirAccess.make_dir_recursive_absolute(shot_dir)
	await get_tree().create_timer(1.2).timeout
	_save("menu_main")
	_show_settings()
	settings.show_tab(1)
	await get_tree().create_timer(0.4).timeout
	_save("menu_settings")
	settings.show_tab(2)
	await get_tree().create_timer(0.3).timeout
	_save("menu_settings_graphics")
	settings.show_tab(4)
	await get_tree().create_timer(0.3).timeout
	_save("menu_settings_gameplay")
	settings.close()
	_show_lobby()
	await get_tree().create_timer(0.3).timeout
	_save("menu_lobby_ready")
	_on_ready()
	await get_tree().create_timer(1.2).timeout
	_save("menu_lobby")
	get_tree().quit()


func _save(nm: String) -> void:
	get_viewport().get_texture().get_image().save_png(shot_dir.path_join(nm + ".png"))
	print("SHOT ", nm)
