## Trailer footage: plays a real match (the AI plays the player's character too) and records the interesting
## moments as JPEG sequences. Between clips the match fast-forwards with 3D rendering off.
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path <project> --rendering-driver opengl3 --resolution 1920x1080 \
##       --fixed-fps 30 -s tools/trailer_director.gd -- --demo --seed=3 --clips=<dir>
## Clips: blimp, skydive, fight (orbiting two players in a firefight), build, pov (over the shoulder with the HUD),
## drop (a supply drop coming down), storm, final (the last duel) - each saved as <dir>/<nn>_<kind>/<frame>.jpg.
extends SceneTree

const FPS := 30.0
const FAST := 8.0
var game: Node
var out := ""
var cam: Camera3D
var clip := {}                      # the clip being recorded: kind, frames, left, subject...
var clip_n := 0
var counts := {}
var limits := {"fight": 10, "build": 4, "pov": 3, "drop": 1, "storm": 2, "final": 1, "blimp": 1, "skydive": 1}
var cooldown := 0.0
var built_seen := 0
var started := false
var frame := 0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--clips="):
			out = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(out)
	var scene: PackedScene = load("res://scenes/game.tscn")
	game = scene.instantiate()
	root.add_child(game)
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.far = 3000.0
	root.add_child(cam)


func _process(_d: float) -> bool:
	frame += 1
	if frame < 3 or game.storm == null:
		return false
	if not started:
		started = true
		Engine.max_physics_steps_per_frame = 16
		root.get_viewport().msaa_3d = Viewport.MSAA_DISABLED      # the software renderer pays dearly for it
		for sun in game.island.find_children("Sun", "DirectionalLight3D", true, false):
			sun.directional_shadow_max_distance = 100.0
	var t: float = game.match_time
	if clip.is_empty():
		_look_for_shot(t)
	if clip.is_empty():
		_fast(true)
		if game.over and t - game.over_time > 1.0:
			_finish()
		return false
	_fast(false)
	_shoot(t)
	return false


func _fast(on: bool) -> void:
	Engine.time_scale = FAST if on else 1.0
	root.get_viewport().disable_3d = on
	if game.hud:
		game.hud.visible = not on and clip.get("hud", false)


# ----------------------------------------------------------------------------- picking shots

func _room(kind: String) -> bool:
	return counts.get(kind, 0) < limits.get(kind, 0)


func _start(kind: String, seconds: float, extra := {}) -> void:
	clip_n += 1
	counts[kind] = counts.get(kind, 0) + 1
	clip = {"kind": kind, "left": int(seconds * FPS), "i": 0, "dir": out.path_join("%02d_%s" % [clip_n, kind]), "ang": randf() * TAU, "hud": false}
	clip.merge(extra, true)
	DirAccess.make_dir_recursive_absolute(clip.dir)
	if not clip.hud:
		cam.current = true
	else:
		game.controller.cam.current = true
	print("CLIP %s at t=%.1f" % [clip.dir.get_file(), game.match_time])


func _look_for_shot(t: float) -> void:
	if t < 1.0:
		return
	if _room("blimp") and t > 2.0:
		_start("blimp", 5.0)
		return
	if _room("skydive"):
		for a in game.actors:
			if a.state == Actor.State.SKYDIVE and a != game.player:
				_start("skydive", 5.5, {"who": a})
				return
		return
	if t < cooldown:
		return
	# the last duel, to the end
	if _room("final") and game.alive_count() == 2:
		var two: Array = game.actors.filter(func(x): return x.alive())
		_start("final", 12.0, {"who": two[0], "other": two[1]})
		return
	if _room("drop"):
		for d in game.events.drops:
			if not d.landed and (d.node as Node3D).global_position.y - d.pos.y < 110.0:
				_start("drop", 5.0, {"drop": d})
				return
	if _room("storm") and game.storm.shrinking and game.storm.phase >= 1:
		for a in game.actors:
			if a.alive() and a.state == Actor.State.GROUND and absf(game.storm.outside(a.global_position)) < 12.0:
				_start("storm", 5.0, {"who": a})
				cooldown = t + 6.0
				return
	if structures_built() > built_seen:
		built_seen = structures_built()
		if _room("build"):
			var e = game.structures.pieces.values()[game.structures.pieces.size() - 1]
			var who = e.get("owner")
			if who != null and who.alive() and who != game.player:
				_start("build", 4.5, {"who": who})
				cooldown = t + 4.0
				return
	if _room("pov") and game.player.alive() and game.player.state == Actor.State.GROUND:
		var br = game.player.get_child(game.player.get_child_count() - 1)
		if br.get("mode") == "fight" and br.target != null and game.player.global_position.distance_to(br.target.global_position) < 40.0:
			_start("pov", 4.5, {"hud": true})
			cooldown = t + 8.0
			return
	if _room("fight"):
		for a in game.actors:
			if not a.alive() or a.state != Actor.State.GROUND:
				continue
			var br2 = a.get_child(a.get_child_count() - 1)
			if br2.get("mode") != "fight" or br2.target == null or not br2.target.alive():
				continue
			var d: float = a.global_position.distance_to(br2.target.global_position)
			if d > 6.0 and d < 32.0 and t - a.last_hit_time < 1.0:
				_start("fight", 4.0, {"who": a, "other": br2.target})
				cooldown = t + 5.0
				return


func structures_built() -> int:
	return game.structures.built


# ----------------------------------------------------------------------------- filming

func _ground(p: Vector3) -> float:
	return game.terrain.height(p.x, p.z)


func _place(pos: Vector3, look: Vector3) -> void:
	pos.y = maxf(pos.y, _ground(pos) + 1.2)
	cam.global_position = cam.global_position.lerp(pos, 0.25) if clip.i > 0 else pos
	cam.look_at(look)


func _shoot(t: float) -> void:
	var dt := 1.0 / FPS
	clip.ang += dt * 0.22
	match clip.kind:
		"blimp":
			var b: Vector3 = game.blimp.global_position
			var dir: Vector3 = game.blimp_dir
			var side := dir.cross(Vector3.UP).normalized()
			_place(b + side * 42.0 - dir * (24.0 - clip.i * 0.12) + Vector3(0, -6, 0), b + dir * 10.0)
		"skydive", "build", "storm":
			var w: Actor = clip.who
			var c := w.global_position + Vector3(0, 1.2, 0)
			var r := 9.0 if clip.kind == "skydive" else (6.5 if clip.kind == "build" else 14.0)
			var up := 3.0 if clip.kind != "skydive" else 4.0
			_place(c + Vector3(cos(clip.ang), 0, sin(clip.ang)) * r + Vector3(0, up, 0), c)
		"fight", "final":
			var a: Actor = clip.who
			var o: Actor = clip.other
			var m := (a.global_position + o.global_position) * 0.5 + Vector3(0, 1.3, 0)
			var span := a.global_position.distance_to(o.global_position)
			var r2 := clampf(span * 0.75 + 5.0, 7.0, 26.0)
			_place(m + Vector3(cos(clip.ang), 0, sin(clip.ang)) * r2 + Vector3(0, 2.5 + span * 0.12, 0), m)
		"drop":
			var n: Node3D = clip.drop.node
			var p := n.global_position
			_place(Vector3(clip.drop.pos.x + 22.0, _ground(p) + 6.0, clip.drop.pos.z + 16.0), p)
		"pov":
			pass
	if clip.i >= 2:                                          # the first frames settle the camera
		var img := root.get_viewport().get_texture().get_image()
		img.save_jpg(clip.dir.path_join("%04d.jpg" % (clip.i - 2)), 0.92)
	clip.i += 1
	clip.left -= 1
	var who_dead: bool = clip.has("who") and clip.kind in ["build", "storm"] and not (clip.who as Actor).alive() and clip.left > 30
	if clip.left <= 0 or who_dead or (clip.kind == "pov" and not game.player.alive()):
		clip = {}
		game.controller.cam.current = false
		cam.current = true


func _finish() -> void:
	print("DIRECTOR done: ", counts)
	quit()
