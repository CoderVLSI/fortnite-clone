## Bakes the walkability grid the bots path-find on and saves res://textures/navgrid.png.
## Two pixels per metre over the island: white = walkable, light grey = walkable next to a wall, dark grey = swimmable
## river or lake water, black = blocked. A cell is walkable when it is dry, not too steep and a
## player-sized capsule standing on it touches nothing but the ground. Bridge decks over water count as walkable.
##   godot --headless --path <project> -s scripts/bake_nav.gd
extends SceneTree

const Terrain := preload("res://scripts/terrain.gd")
const HALF := 215
const SWIM := Color(0.33, 0.33, 0.33)    # river and lake water: path-finding swims it when it has to
const CELL := 0.5                        # fine enough that a thin wall always blocks at least one cell
var island: Node3D
var ticks := 0


func _init() -> void:
	island = load("res://scenes/island.tscn").instantiate()
	get_root().add_child(island)


func _physics_process(_d: float) -> bool:
	ticks += 1
	if ticks == 1:
		# doors open in play, so they must not block the grid
		for name in ["house_door", "warehouse_door", "warehouse_roller_door"]:
			for n in island.find_children(name, "MeshInstance3D", true, false):
				for c in n.find_children("*", "StaticBody3D", true, false):
					c.free()
	if ticks < 4:
		return false
	var t0 := Time.get_ticks_msec()
	var T := Terrain.new()
	var space := island.get_world_3d().direct_space_state
	var terrain_body: StaticBody3D = island.get_node("Terrain/TerrainBody")
	var cap := CapsuleShape3D.new()
	cap.radius = 0.36                     # just over half a cell's diagonal, so a thin wall at an angle can never slip between two samples
	cap.height = 1.3
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.collision_mask = 1
	q.exclude = [terrain_body.get_rid()]
	var n := int(HALF * 2 / CELL)
	var img := Image.create(n, n, false, Image.FORMAT_L8)
	var free_cells := 0
	var swim_cells := 0
	for j in n:
		for i in n:
			var x := -HALF + (i + 0.5) * CELL
			var z := -HALF + (j + 0.5) * CELL
			var h := T.height(x, z)
			var ok := false
			if h >= 0.55:
				var slope := maxf(absf(T.height(x + 0.6, z) - T.height(x - 0.6, z)), absf(T.height(x, z + 0.6) - T.height(x, z - 0.6))) / 1.2
				if slope < 0.95:
					q.transform = Transform3D(Basis.IDENTITY, Vector3(x, h + 1.2, z))
					ok = space.intersect_shape(q, 1).is_empty()
			elif T.river_info(Vector2(x, z)).x < 14.0:
				# over the river: only a bridge deck makes this walkable
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 30, z), Vector3(x, 0.5, z), 1))
				ok = not hit.is_empty() and String(hit.collider.name) == "DeckCollider"
			var swim := false
			if not ok and (T.river_info(Vector2(x, z)).x < 9.5 or Vector2(x, z).distance_to(T.lake) < T.lake_r + 4.0):
				# river and lake water can be swum: walkable at a cost, unless something stands in it
				var surf := T.water_surface(x, z)
				if surf > -100.0:
					q.transform = Transform3D(Basis.IDENTITY, Vector3(x, surf - 0.2, z))
					swim = space.intersect_shape(q, 1).is_empty()
			if ok:
				free_cells += 1
			elif swim:
				swim_cells += 1
			img.set_pixel(i, j, Color.WHITE if ok else (SWIM if swim else Color.BLACK))
	# walls the capsule test misses (a cell centre that falls inside a thick wall touches neither face):
	# a ray between neighbouring walkable cells at knee and chest height must be clear, or both cells are blocked
	var walls := 0
	var rq := PhysicsRayQueryParameters3D.new()
	rq.collision_mask = 1
	rq.exclude = [terrain_body.get_rid()]
	rq.hit_back_faces = true
	rq.hit_from_inside = true
	var block := PackedByteArray()
	block.resize(n * n)
	for j in n:
		for i in n:
			if img.get_pixel(i, j).r < 0.9:
				continue                                  # open land only; water is checked by the capsule alone
			var x := -HALF + (i + 0.5) * CELL
			var z := -HALF + (j + 0.5) * CELL
			var h := T.height(x, z)
			if h < 0.55:
				continue                                  # bridge decks: the terrain is far below the deck
			for d in [Vector2i(1, 0), Vector2i(0, 1)]:
				var i2: int = i + d.x
				var j2: int = j + d.y
				if i2 >= n or j2 >= n or img.get_pixel(i2, j2).r < 0.9:
					continue
				var x2: float = x + d.x * CELL
				var z2: float = z + d.y * CELL
				var h2 := T.height(x2, z2)
				if h2 < 0.55:
					continue
				for up in [0.6, 1.4]:
					rq.from = Vector3(x, h + up, z)
					rq.to = Vector3(x2, h2 + up, z2)
					if not space.intersect_ray(rq).is_empty():
						block[j * n + i] = 1
						block[j2 * n + i2] = 1
						break
	for k in n * n:
		if block[k] == 1:
			img.set_pixel(k % n, k / n, Color.BLACK)
			walls += 1
	print("NAV cells blocked by the ray check: ", walls)
	# doorways: a 1 m opening in a rotated building can fall between the cell centres, sealing the room off,
	# so a corridor is carved straight through every door
	var carved := 0
	for nm in ["house_door", "warehouse_door", "warehouse_roller_door"]:
		for dn in island.find_children(nm, "MeshInstance3D", true, false):
			var ab: AABB = (dn as MeshInstance3D).get_aabb()
			var xf: Transform3D = (dn as Node3D).global_transform
			var centre: Vector3 = xf * ab.get_center()
			var through: Vector3 = xf.basis.x if ab.size.x <= ab.size.z else xf.basis.z     # the door leaf's thin axis
			through.y = 0.0
			through = through.normalized()
			var side := Vector3(-through.z, 0, through.x)
			for k in range(-7, 8):
				for l in [-0.15, 0.0, 0.15]:
					var p: Vector3 = centre + through * (k * 0.25) + side * l
					var ci := int(floor((p.x + HALF) / CELL))
					var cj := int(floor((p.z + HALF) / CELL))
					if ci >= 0 and cj >= 0 and ci < n and cj < n and img.get_pixel(ci, cj).r < 0.3:
						img.set_pixel(ci, cj, Color.WHITE)
						carved += 1
	print("NAV doorway cells carved: ", carved)
	# pockets: small walkable islands that nothing connects to (a gap behind a staircase, a corner of a fence)
	# are filled in, so no path ever starts or ends in one
	var comp := PackedInt32Array()
	comp.resize(n * n)
	var filled := 0
	for start in n * n:
		if comp[start] != 0 or img.get_pixel(start % n, start / n).r < 0.3:
			continue
		var members := PackedInt32Array([start])
		comp[start] = 1
		var at := 0
		while at < members.size():
			var c := members[at]
			at += 1
			var cx := c % n
			var cy := c / n
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var x2: int = cx + d.x
				var y2: int = cy + d.y
				if x2 < 0 or y2 < 0 or x2 >= n or y2 >= n:
					continue
				var m := y2 * n + x2
				if comp[m] == 0 and img.get_pixel(x2, y2).r >= 0.3:
					comp[m] = 1
					members.append(m)
		if members.size() < 40:
			for m in members:
				img.set_pixel(m % n, m / n, Color.BLACK)
			filled += members.size()
	print("NAV pocket cells filled: ", filled)
	# walkable cells that touch a blocked one are grey: still walkable, but path-finding avoids hugging walls
	var near := 0
	for j in n:
		for i in n:
			if img.get_pixel(i, j).r < 0.9:
				continue                                  # only open land is greyed
			var touch := false
			for dj in range(-1, 2):
				for di in range(-1, 2):
					var x := clampi(i + di, 0, n - 1)
					var y := clampi(j + dj, 0, n - 1)
					if img.get_pixel(x, y).r < 0.3:              # black only: grey cells marked earlier still count as free
						touch = true
			if touch:
				near += 1
				img.set_pixel(i, j, Color(0.63, 0.63, 0.63))
	print("NAV near-wall cells: ", near)
	var err := img.save_png("res://textures/navgrid.png")
	print("NAV ", JSON.stringify({"save": err, "cells": n * n, "walkable": free_cells, "swim": swim_cells, "seconds": (Time.get_ticks_msec() - t0) / 1000.0}))
	quit()
	return true
