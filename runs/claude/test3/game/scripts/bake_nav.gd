## Bakes the walkability grid the bots path-find on and saves res://textures/navgrid.png.
## One pixel per metre over the island: white = walkable. A cell is walkable when it is dry, not too steep and a
## player-sized capsule standing on it touches nothing but the ground. Bridge decks over water count as walkable.
##   godot --headless --path <project> -s scripts/bake_nav.gd
extends SceneTree

const Terrain := preload("res://scripts/terrain.gd")
const HALF := 215
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
	cap.radius = 0.36
	cap.height = 1.3
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.collision_mask = 1
	q.exclude = [terrain_body.get_rid()]
	var n := HALF * 2
	var img := Image.create(n, n, false, Image.FORMAT_L8)
	var free_cells := 0
	for j in n:
		for i in n:
			var x := -HALF + i + 0.5
			var z := -HALF + j + 0.5
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
			if ok:
				free_cells += 1
			img.set_pixel(i, j, Color.WHITE if ok else Color.BLACK)
	var err := img.save_png("res://textures/navgrid.png")
	print("NAV ", JSON.stringify({"save": err, "cells": n * n, "walkable": free_cells, "seconds": (Time.get_ticks_msec() - t0) / 1000.0}))
	quit()
	return true
