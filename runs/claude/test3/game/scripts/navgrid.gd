## Path-finding for the bots: A* over the baked 1 m walkability grid (see bake_nav.gd).
class_name NavGrid
extends RefCounted

const HALF := 215
var astar := AStarGrid2D.new()
var ready := false
var terrain


func load_grid(t) -> void:
	terrain = t
	# loaded as an imported resource so it also works from an exported, packed build
	if not ResourceLoader.exists("res://textures/navgrid.png"):
		return
	var tex: Texture2D = load("res://textures/navgrid.png")
	var img := tex.get_image()
	if img == null:
		return
	if img.is_compressed():
		img.decompress()
	var n := HALF * 2
	astar.region = Rect2i(0, 0, n, n)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for j in n:
		for i in n:
			if img.get_pixel(i, j).r < 0.5:
				astar.set_point_solid(Vector2i(i, j), true)
	ready = true


func cell(p: Vector3) -> Vector2i:
	return Vector2i(clampi(int(floor(p.x)) + HALF, 0, HALF * 2 - 1), clampi(int(floor(p.z)) + HALF, 0, HALF * 2 - 1))


func walkable(p: Vector3) -> bool:
	return ready and not astar.is_point_solid(cell(p))


func nearest_free(c: Vector2i, max_r := 8) -> Vector2i:
	if not astar.is_point_solid(c):
		return c
	for r in range(1, max_r + 1):
		for dj in range(-r, r + 1):
			for di in range(-r, r + 1):
				if maxi(absi(di), absi(dj)) != r:
					continue
				var k := Vector2i(clampi(c.x + di, 0, HALF * 2 - 1), clampi(c.y + dj, 0, HALF * 2 - 1))
				if not astar.is_point_solid(k):
					return k
	return c


func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	if not ready:
		out.append(from); out.append(to)
		return out
	var a := nearest_free(cell(from))
	var b := nearest_free(cell(to))
	var ids := astar.get_id_path(a, b, true)
	if ids.size() < 2:
		out.append(from); out.append(to)
		return out
	# keep the corners only: drop points that continue in the same direction
	var prev_dir := Vector2i.ZERO
	for i in ids.size():
		var keep := i == 0 or i == ids.size() - 1
		if not keep:
			var d: Vector2i = ids[i + 1] - ids[i]
			keep = d != prev_dir
			prev_dir = d
		if keep:
			var x := ids[i].x - HALF + 0.5
			var z := ids[i].y - HALF + 0.5
			out.append(Vector3(x, maxf(terrain.height(x, z), 0.3), z))
	if cell(to) == b:
		out.append(to)
	return out
