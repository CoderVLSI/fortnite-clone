extends SceneTree
var n := 0
func _process(_d):
	n += 1
	if n == 1:
		var lib := AnimationLibrary.new()
		for f in ["Xbot", "Michelle"]:
			var inst: Node = (load("res://assets/characters/%s.glb" % f) as PackedScene).instantiate()
			var ap: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
			for an in ap.get_animation_list():
				lib.add_animation(StringName(f + "_" + an), ap.get_animation(an))
			inst.free()
		var clips := [["Idle", 0.5], ["Run", 0.2], ["Walk", 0.3], ["x/Xbot_run", 0.2], ["x/Xbot_walk", 0.3], ["x/Xbot_sneak_pose", 0.0], ["x/Michelle_SambaDance", 3.0], ["x/Xbot_idle", 0.6]]
		for i in clips.size():
			var s: Node3D = (load("res://assets/characters/Soldier.glb") as PackedScene).instantiate()
			get_root().add_child(s)
			s.position = Vector3((i - 3.5) * 1.15, 0, 0)
			s.rotation.y = 0.35
			var ap2: AnimationPlayer = s.find_children("*", "AnimationPlayer", true, false)[0]
			ap2.add_animation_library("x", lib)
			ap2.play(clips[i][0])
			ap2.seek(clips[i][1], true)
			ap2.pause()
		var cam := Camera3D.new()
		get_root().add_child(cam)
		cam.look_at_from_position(Vector3(0, 1.1, 5.2), Vector3(0, 0.9, 0))
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-40, 30, 0)
		get_root().add_child(sun)
		var we := WorldEnvironment.new()
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.55, 0.65, 0.75)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.8, 0.8, 0.85)
		we.environment = env
		get_root().add_child(we)
		return false
	if n == 6:
		get_root().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://").path_join("../captures/retarget_test.png"))
		print("SAVED")
		quit()
	return false
