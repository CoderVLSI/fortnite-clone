## Trailer footage: scenic camera moves over the island (no match running), saved as JPEG sequences.
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path <project> --rendering-driver opengl3 --resolution 1920x1080 \
##       -s tools/trailer_flyover.gd -- --clips=<dir>
extends SceneTree

const FPS := 30.0
## [name, seconds, from, to, look-from, look-to] - positions are x, height above ground, z
const MOVES := [
	["fly_snowtown", 4.5, Vector3(-30, 26, -250), Vector3(-62, 20, -292), Vector3(-90, 3, -318), Vector3(-95, 3, -322)],
	["fly_peaks", 4.5, Vector3(140, 14, -220), Vector3(110, 30, -262), Vector3(110, 8, -300), Vector3(80, 12, -350)],
	["fly_mesa", 4.5, Vector3(-70, 9, 250), Vector3(-10, 11, 240), Vector3(-30, 8, 300), Vector3(-30, 8, 300)],
	["fly_oasis", 4.5, Vector3(115, 12, 250), Vector3(105, 9, 290), Vector3(98, 2, 300), Vector3(100, 2, 340)],
	["fly_village", 4.5, Vector3(-60, 30, -50), Vector3(30, 34, -60), Vector3(-1, 4, -9), Vector3(-1, 4, -9)],
	["fly_island", 9.0, Vector3(-260, 230, 470), Vector3(-120, 210, 430), Vector3(-40, 0, 40), Vector3(10, 0, 0)],
]
var T
var cam: Camera3D
var out := ""
var m := 0
var i := 0
var wait := 0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--clips="):
			out = a.get_slice("=", 1)
	T = load("res://scripts/terrain.gd").new()
	var isl: Node3D = load("res://scenes/island.tscn").instantiate()
	root.add_child(isl)
	for sun in isl.find_children("Sun", "DirectionalLight3D", true, false):
		sun.directional_shadow_max_distance = 100.0
	root.msaa_3d = Viewport.MSAA_DISABLED
	cam = Camera3D.new()
	cam.fov = 60.0
	cam.far = 3000.0
	root.add_child(cam)
	cam.current = true


func _lift(v: Vector3) -> Vector3:
	return Vector3(v.x, T.height(v.x, v.z) + v.y, v.z)


func _process(_d: float) -> bool:
	wait += 1
	if wait < 10:
		return false
	if m >= MOVES.size():
		quit()
		return true
	var mv: Array = MOVES[m]
	var n := int(float(mv[1]) * FPS)
	var t := smoothstep(0.0, 1.0, float(i) / n) * 0.8 + float(i) / n * 0.2        # eased, never quite stopping
	cam.global_position = _lift(mv[2]).lerp(_lift(mv[3]), t)
	cam.look_at(_lift(mv[4]).lerp(_lift(mv[5]), t))
	if i >= 2:                                   # the camera has to be in place one frame before the capture
		var dir := out.path_join("%02d_%s" % [m + 1, mv[0]])
		if i == 2:
			DirAccess.make_dir_recursive_absolute(dir)
		root.get_viewport().get_texture().get_image().save_jpg(dir.path_join("%04d.jpg" % (i - 2)), 0.92)
	i += 1
	if i >= n + 2:
		print("MOVE ", mv[0])
		m += 1
		i = 0
	return false
