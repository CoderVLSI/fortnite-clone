## Lines up characters in every pose and saves a screenshot.  Needs a display:
##   xvfb-run -a godot --path <project> --rendering-driver opengl3 --resolution 1600x700 -- --poses
extends Node

var game: Node
var rows: Array = []
var t := 0.0
var shot := false


func setup(g: Node) -> void:
	game = g


func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var T = game.terrain
	var o := Vector3(T.village.x + 14.0, 0, T.village.y + 22.0)
	var cfgs := [["idle", {}], ["walk", {"v": 1.5}], ["run", {"v": 7.0}], ["crouch", {"crouch": true}], ["crouch walk", {"crouch": true, "v": 3.0}],
			["slide", {"slide": true, "v": 9.0}], ["rifle", {"item": "assault_rifle"}], ["heal", {"item": "medkit", "use": true}],
			["pickaxe", {"swing": true}], ["jump", {"air": true}], ["glide", {"state": Actor.State.GLIDE}], ["skydive", {"state": Actor.State.SKYDIVE}],
			["swim", {"state": Actor.State.SWIM, "v": 3.0}], ["tread", {"state": Actor.State.SWIM}]]
	for o2 in game.actors:
		o2.process_mode = Node.PROCESS_MODE_DISABLED
	for i in cfgs.size():
		var a: Actor = game.actors[i + 1]
		a.process_mode = Node.PROCESS_MODE_ALWAYS
		a.set_physics_process(false)
		for c in a.get_children():
			if c.has_method("setup") and c.get("skill") != null:
				c.process_mode = Node.PROCESS_MODE_DISABLED
		var cfg: Dictionary = cfgs[i][1]
		var p := o + Vector3((i % 7 - 3) * 1.7, 0, (i / 7) * 3.2)
		p.y = T.height(p.x, p.z)
		a.state = cfg.get("state", Actor.State.GROUND)
		if cfg.has("state") and a.state != Actor.State.SWIM:
			p.y += 1.5
		a.global_position = p
		var yaw := PI - 0.45
		a.aim_yaw = yaw
		a.body.rotation.y = yaw
		a.velocity = Vector3(-sin(yaw), 0, -cos(yaw)) * cfg.get("v", 0.0)
		a.crouched = cfg.get("crouch", false)
		a.sliding = cfg.get("slide", false)
		if cfg.has("item"):
			a.add_item(Items.make(cfg.item, 2))
			a.select(a.find_item(cfg.item))
		if cfg.get("use", false):
			a.using = 99.0
			a.use_total = 100.0
		a.set_meta("pose_cfg", cfg)
		rows.append(a)
	game.controller.demo = true
	game.player.state = Actor.State.GROUND
	game.player.global_position = o + Vector3(0, 0, 30)


func _process(delta: float) -> void:
	if rows.is_empty():
		return
	t += delta
	for a in rows:
		var cfg: Dictionary = a.get_meta("pose_cfg")
		if cfg.get("swing", false):
			a.body.swing = 0.55
		a.set_meta("force_floor", not cfg.get("air", false) and not cfg.has("state"))
		a.body.animate(delta, a)
	var cam: Camera3D = game.controller.cam
	var mid: Vector3 = (rows[3].global_position + rows[10].global_position) / 2.0
	cam.global_position = mid + Vector3(1.2, 2.6, 9.0)
	cam.look_at(mid + Vector3(0.3, 0.9, 0))
	cam.fov = 58.0
	if t > 1.6 and not shot:
		shot = true
		var dir := ProjectSettings.globalize_path("res://").path_join("../captures")
		get_viewport().get_texture().get_image().save_png(dir.path_join("poses.png"))
		print("POSES saved")
		get_tree().quit()
