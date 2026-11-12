## Captures the crosshair for each weapon and situation into one sheet.  Needs a display:
##   xvfb-run -a godot --path <project> --rendering-driver opengl3 --resolution 1280x720 -- --crosshairs
extends Node

var game: Node


func setup(g: Node) -> void:
	game = g


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ready() -> void:
	await frames(5)
	var a: Actor = game.player
	var ctl = game.controller
	ctl.demo = true
	for o in game.actors:
		if o != a:
			o.process_mode = Node.PROCESS_MODE_DISABLED
	var T = game.terrain
	var p: Vector3 = game.events._dry_spot(T.village + Vector2(22, 6))
	a.state = Actor.State.GROUND
	a.global_position = p + Vector3(0, 0.1, 0)
	a.aim_yaw = PI * 0.5
	ctl.yaw = a.aim_yaw
	ctl.pitch = 0.0
	for w in ["assault_rifle", "pistol", "shotgun", "sniper_rifle", "rocket_launcher", "grenade"]:
		a.add_item(Items.make(w, 2))
	a.ammo = {"light": 99, "medium": 99, "heavy": 99, "shells": 99, "rockets": 99}
	await frames(20)
	var shots := []
	var cases := [["rifle, standing", "assault_rifle", ""], ["rifle, moving", "assault_rifle", "move"], ["rifle, rapid fire", "assault_rifle", "fire"],
			["rifle, crouched", "assault_rifle", "crouch"], ["pistol", "pistol", ""], ["shotgun", "shotgun", ""], ["rocket launcher", "rocket_launcher", ""],
			["pickaxe", "", ""], ["grenade", "grenade", ""], ["build mode", "", "build"], ["sniper, hip", "sniper_rifle", ""], ["sniper, scoped", "sniper_rifle", "scope"]]
	for cs in cases:
		a.build_piece = ""
		a.set_crouched(false)
		a.in_move = Vector2.ZERO
		a.in_fire = false
		ctl.force_aim = false
		a.bloom = 0.0
		a.select(a.find_item(cs[1]) if cs[1] != "" else -1)
		await frames(10)
		match cs[2]:
			"move":
				a.in_move = Vector2(1, 0)
			"fire":
				for k in 6:
					a.bloom = minf(a.bloom + 0.2, 1.5)
			"crouch":
				a.set_crouched(true)
			"build":
				a.set_build("wall")
			"scope":
				ctl.force_aim = true
		await frames(30 if cs[2] != "scope" else 40)
		if cs[2] == "fire":
			a.bloom = 1.2
		ctl.yaw = a.aim_yaw
		await get_tree().process_frame
		await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		shots.append([cs[0], img])
		a.in_move = Vector2.ZERO
	# sheet: centre crops, and the full scoped view
	var sz: Vector2i = shots[0][1].get_size()
	var crop := 220
	var cols := 6
	var sheet := Image.create(cols * crop, 2 * (crop + 24) + sz.y / 2, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.1, 0.11, 0.13))
	for i in shots.size() - 1:
		var im: Image = shots[i][1]
		var part := im.get_region(Rect2i(sz.x / 2 - crop / 2, sz.y / 2 - crop / 2, crop, crop))
		sheet.blit_rect(part, Rect2i(0, 0, crop, crop), Vector2i((i % cols) * crop, (i / cols) * (crop + 24) + 24))
	var full: Image = shots[shots.size() - 1][1]
	full.resize(sz.x / 2, sz.y / 2)
	sheet.blit_rect(full, Rect2i(0, 0, sz.x / 2, sz.y / 2), Vector2i(0, 2 * (crop + 24)))
	var dir := ProjectSettings.globalize_path("res://").path_join("../captures")
	sheet.save_png(dir.path_join("crosshairs.png"))
	var f := FileAccess.open(dir.path_join("crosshairs_labels.txt"), FileAccess.WRITE)
	for i in shots.size():
		f.store_line(shots[i][0])
	f.close()
	print("CROSSHAIRS saved")
	get_tree().quit()
