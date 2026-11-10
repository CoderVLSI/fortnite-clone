## Renders still views of the island.  Needs a display (xvfb-run is fine):
##   xvfb-run -a godot --path <project> --rendering-driver opengl3 --resolution 1600x900 -s scripts/capture.gd
extends SceneTree

const Terrain := preload("res://scripts/terrain.gd")
var shots: Array = []
var i := -1
var wait := 0
var cam: Camera3D
var out_dir := ""


func _init() -> void:
	var T := Terrain.new()
	out_dir = ProjectSettings.globalize_path("res://").path_join("../captures")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var scene: Node3D = load("res://scenes/island.tscn").instantiate()
	get_root().add_child(scene)
	cam = Camera3D.new()
	cam.far = 2000.0
	get_root().add_child(cam)
	var v := T.village; var y := T.yard; var f := T.farm
	shots = [
		["01_topdown", "ortho", Vector3(0, 400, 0), Vector3(0, 0, 0), 460.0],
		["02_overview_south", "persp", Vector3(40, 190, 330), Vector3(0, 0, 10), 55.0],
		["03_village", "persp", Vector3(v.x + 55, 42, v.y + 70), Vector3(v.x, 4, v.y), 55.0],
		["04_village_street", "persp", Vector3(v.x + 8, 6.0, v.y + 14), Vector3(v.x - 20, 5, v.y - 30), 70.0],
		["05_farm", "persp", Vector3(f.x + 60, 40, f.y + 70), Vector3(f.x, 4, f.y), 55.0],
		["06_industrial", "persp", Vector3(y.x - 30, 45, y.y + 85), Vector3(y.x, 4, y.y), 55.0],
		["07_pine_forest_lake", "persp", Vector3(T.lake.x + 40, 38, T.lake.y + 75), Vector3(T.lake.x - 10, 4, T.lake.y - 10), 60.0],
		["08_oak_forest", "persp", Vector3(-95, 30, 55), Vector3(-140, 5, -20), 60.0],
		["09_beach", "persp", Vector3(215, 22, 95), Vector3(165, 4, 0), 60.0],
		["10_south_cliff_tower", "persp", Vector3(45, 34, 230), Vector3(-2, 14, 150), 55.0],
		["11_river_bridge", "persp", Vector3(80, 16, -40), Vector3(45, 4, -70), 60.0],
		["12_blimp", "persp", Vector3(-80, 70, -40), Vector3(-120, 92, -90), 50.0],
	]


func _process(_d: float) -> bool:
	wait += 1
	if wait < 4:
		return false
	wait = 0
	if i >= 0:
		var img := get_root().get_texture().get_image()
		img.save_png(out_dir.path_join(shots[i][0] + ".png"))
		print("SHOT ", shots[i][0])
	i += 1
	if i >= shots.size():
		quit()
		return true
	var s: Array = shots[i]
	var we: WorldEnvironment = get_root().find_child("WorldEnvironment", true, false)
	if we:
		we.environment.fog_enabled = s[1] != "ortho"
	if s[1] == "ortho":
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = s[4]
		cam.position = s[2]
		cam.rotation_degrees = Vector3(-90, 0, 0)
	else:
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = s[4]
		cam.look_at_from_position(s[2], s[3])
	cam.current = true
	return false
