## Flies a camera around the island and measures the average frame time.
##   xvfb-run -a godot --path <project> --rendering-driver opengl3 --resolution 1280x720 \
##       --fixed-fps 30 --write-movie ../captures/flythrough.avi -s scripts/flythrough.gd
extends SceneTree

const Terrain := preload("res://scripts/terrain.gd")
const FRAMES := 660
var T: Terrain
var cam: Camera3D
var frame := 0
var t0 := 0
var times := PackedFloat32Array()
var keys: Array = []


func _init() -> void:
	T = Terrain.new()
	get_root().add_child(load("res://scenes/island.tscn").instantiate())
	cam = Camera3D.new()
	cam.far = 3000.0
	cam.fov = 62.0
	get_root().add_child(cam)
	cam.current = true
	# [camera position, look-at target]: an orbit, then a low pass through each zone
	var v := T.village; var y := T.yard; var f := T.farm
	keys = [[Vector3(0, 170, 330), Vector3(0, 0, 0)], [Vector3(300, 120, 120), Vector3(0, 0, 0)], [Vector3(230, 60, -160), Vector3(f.x, 4, f.y)],
			[Vector3(f.x + 30, 22, f.y + 45), Vector3(f.x - 10, 4, f.y - 10)], [Vector3(T.lake.x + 50, 26, T.lake.y + 40), Vector3(T.lake.x, 3, T.lake.y)],
			[Vector3(-120, 30, -120), Vector3(-92, 16, -166)], [Vector3(-170, 26, -20), Vector3(-120, 6, 10)], [Vector3(y.x - 55, 24, y.y + 45), Vector3(y.x, 4, y.y)],
			[Vector3(y.x + 40, 12, y.y + 10), Vector3(v.x, 5, v.y)], [Vector3(v.x - 30, 9, v.y + 34), Vector3(v.x, 5, v.y)], [Vector3(v.x + 40, 14, v.y + 20), Vector3(60, 4, 48)],
			[Vector3(95, 12, 70), Vector3(139, 14, 60)], [Vector3(190, 14, 120), Vector3(170, 3, 20)], [Vector3(60, 40, 240), Vector3(-2, 16, 150)],
			[Vector3(0, 170, 330), Vector3(0, 0, 0)]]


func sample(u: float) -> Array:
	var n := keys.size() - 1
	var x := clampf(u, 0.0, 0.9999) * n
	var i := int(x)
	var k := x - i
	k = k * k * (3.0 - 2.0 * k)
	return [keys[i][0].lerp(keys[i + 1][0], k), keys[i][1].lerp(keys[i + 1][1], k)]


func _process(_d: float) -> bool:
	var now := Time.get_ticks_usec()
	if frame > 2:
		times.append((now - t0) / 1000.0)
	t0 = now
	var s := sample(float(frame) / FRAMES)
	var pos: Vector3 = s[0]
	pos.y = maxf(pos.y, T.height(pos.x, pos.z) + 3.0)
	cam.look_at_from_position(pos, s[1])
	frame += 1
	if frame > FRAMES:
		var sum := 0.0
		var worst := 0.0
		for ms in times:
			sum += ms
			worst = maxf(worst, ms)
		var avg := sum / times.size()
		var info := {"frames": times.size(), "avg_frame_ms": avg, "avg_fps": 1000.0 / avg, "worst_frame_ms": worst,
				"renderer": RenderingServer.get_video_adapter_name(), "resolution": str(get_root().size),
				"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}
		print("PERF ", JSON.stringify(info))
		var fa := FileAccess.open(ProjectSettings.globalize_path("res://").path_join("../captures/performance.json"), FileAccess.WRITE)
		fa.store_string(JSON.stringify(info, "  "))
		fa.close()
		quit()
		return true
	return false
