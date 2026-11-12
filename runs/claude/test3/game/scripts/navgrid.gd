## Path-finding for the bots: A* over the baked 0.5 m walkability grid (see bake_nav.gd).
class_name NavGrid
extends RefCounted

const HALF := 215
const CELL := 0.5
const N := 860
const SWIM_COST := 6.0              # swimming is slow: only when the way round is much longer
const WALL_COST := 4.0              # cells beside a wall cost this much more, so paths keep to the middle of a room or doorway
var astar := AStarGrid2D.new()
var ready := false
var terrain
var baked := PackedByteArray()          # 1 where the baked grid is blocked, to restore cells when a built wall goes
var built := {}                         # cell -> number of built walls standing on it


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
	var n := N
	astar.region = Rect2i(0, 0, n, n)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES     # never squeeze past a corner
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	img.convert(Image.FORMAT_L8)
	var data := img.get_data()
	baked.resize(n * n)
	for j in n:
		var row := j * n
		for i in n:
			var v := data[row + i]
			if v < 40:
				astar.set_point_solid(Vector2i(i, j), true)
				baked[row + i] = 1
			elif v < 128:
				astar.set_point_weight_scale(Vector2i(i, j), SWIM_COST)
			elif v < 220:
				astar.set_point_weight_scale(Vector2i(i, j), WALL_COST)
	ready = true


func cell(p: Vector3) -> Vector2i:
	return Vector2i(clampi(int(floor((p.x + HALF) / CELL)), 0, N - 1), clampi(int(floor((p.z + HALF) / CELL)), 0, N - 1))


func walkable(p: Vector3) -> bool:
	return ready and not astar.is_point_solid(cell(p))


func dry(p: Vector3) -> bool:
	## Walkable without swimming.
	return walkable(p) and astar.get_point_weight_scale(cell(p)) < SWIM_COST


func centre(c: Vector2i, y: float) -> Vector3:
	return Vector3((c.x + 0.5) * CELL - HALF, y, (c.y + 0.5) * CELL - HALF)


func nearest_free(c: Vector2i, world: Vector3, clear: Callable, max_r := 16) -> Vector2i:
	## The closest walkable cell that can be reached in a straight line from `world`, so that someone pressed
	## against a wall is never snapped to a cell on its far side.
	if not astar.is_point_solid(c):
		return c
	var fallback := c
	var have_fallback := false
	var eye := world + Vector3(0, 1.0, 0)
	for r in range(1, max_r + 1):
		for dj in range(-r, r + 1):
			for di in range(-r, r + 1):
				if maxi(absi(di), absi(dj)) != r:
					continue
				var k := Vector2i(clampi(c.x + di, 0, N - 1), clampi(c.y + dj, 0, N - 1))
				if astar.is_point_solid(k):
					continue
				if not have_fallback:
					fallback = k
					have_fallback = true
				if clear.call(eye, centre(k, eye.y)):
					return k
	return fallback


func path(from: Vector3, to: Vector3, clear: Callable) -> PackedVector3Array:
	var out := PackedVector3Array()
	if not ready:
		out.append(from); out.append(to)
		return out
	var a := nearest_free(cell(from), from, clear)
	var b := nearest_free(cell(to), to, clear)
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
			var x := (ids[i].x + 0.5) * CELL - HALF
			var z := (ids[i].y + 0.5) * CELL - HALF
			out.append(Vector3(x, maxf(terrain.height(x, z), 0.3), z))
	if cell(to) == b:
		out.append(to)
	return out


func mark_wall(from: Vector3, to: Vector3, standing: bool) -> void:
	## A wall someone built on the ground blocks the cells along it while it stands.
	if not ready:
		return
	var along := to - from
	along.y = 0.0
	var side := Vector3(-along.z, 0, along.x).normalized()
	var cells := {}
	var steps := int(ceil(along.length() / (CELL * 0.5)))
	for k in steps + 1:
		var p := from + along * (float(k) / steps)
		for off in [-0.4, 0.0, 0.4]:
			cells[cell(p + side * off)] = true
	for c in cells:
		var n: int = built.get(c, 0) + (1 if standing else -1)
		if n > 0:
			built[c] = n
			astar.set_point_solid(c, true)
		else:
			built.erase(c)
			astar.set_point_solid(c, baked[c.y * N + c.x] == 1)
