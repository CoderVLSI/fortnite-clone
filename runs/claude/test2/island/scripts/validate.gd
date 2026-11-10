## Headless checks on the saved level: hierarchy, spawn points, colliders, counts.
##   godot --headless --path <project> -s scripts/validate.gd
extends SceneTree

var scene: Node3D
var ticks := 0


func _init() -> void:
	scene = load("res://scenes/island.tscn").instantiate()
	get_root().add_child(scene)


func _physics_process(_d: float) -> bool:
	ticks += 1
	if ticks < 3:
		return false
	var out := {}
	var zones := []
	for c in scene.get_children():
		zones.append("%s (%d)" % [c.name, c.get_child_count()])
	out["top_level_groups"] = zones
	var space := scene.get_world_3d().direct_space_state
	var spawns := scene.get_node("Spawns").get_children()
	var bad := []
	var min_gap := 1e9
	for s in spawns:
		var p: Vector3 = s.global_position
		# ground directly below, and nothing solid in a player-sized capsule
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3(0, 60, 0), p + Vector3(0, -60, 0)))
		if hit.is_empty() or absf(hit.position.y - p.y) > 0.6:
			bad.append("%s: no ground at spawn height (%s)" % [s.name, hit.get("position", "none")])
		var q := PhysicsShapeQueryParameters3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.4
		cap.height = 1.8
		q.shape = cap
		q.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, 1.1, 0))
		if not space.intersect_shape(q, 1).is_empty():
			bad.append("%s: overlaps a collider" % s.name)
		if p.y < 1.0:
			bad.append("%s: under water" % s.name)
		for o in spawns:
			if o != s:
				min_gap = minf(min_gap, p.distance_to(o.global_position))
	out["spawns"] = spawns.size()
	out["spawn_names_ok"] = spawns.size() == 30 and spawns[0].name == "Spawn_01" and spawns[29].name == "Spawn_30"
	out["spawn_problems"] = bad
	out["closest_two_spawns_m"] = snappedf(min_gap, 0.1)
	out["static_bodies"] = scene.find_children("*", "StaticBody3D", true, false).size()
	out["collision_shapes"] = scene.find_children("*", "CollisionShape3D", true, false).size()
	out["mesh_instances"] = scene.find_children("*", "MeshInstance3D", true, false).size()
	var inst := 0
	for m in scene.find_children("*", "MultiMeshInstance3D", true, false):
		inst += m.multimesh.instance_count
	out["gpu_instanced_objects"] = inst
	out["loot_nodes"] = scene.get_tree().get_nodes_in_group("loot").size()
	# a ray dropped into a house must land on its floor, not fall through
	var house: Node3D = scene.get_node("Zone_Center_Village/House_01")
	var inside := house.global_transform * Vector3(-1.5, 2.0, 0.5)
	var floor_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(inside, inside + Vector3(0, -10, 0)))
	out["house_floor_height_above_ground_m"] = snappedf(floor_hit.position.y - house.global_position.y, 0.01) if not floor_hit.is_empty() else -1.0
	# a horizontal ray from outside must be stopped by the wall
	var wall_from := house.global_transform * Vector3(-8.0, 1.5, -1.0)
	var wall_to := house.global_transform * Vector3(0.0, 1.5, -1.0)
	out["house_wall_blocks_ray"] = not space.intersect_ray(PhysicsRayQueryParameters3D.create(wall_from, wall_to)).is_empty()
	print("VALIDATE ", JSON.stringify(out, "  "))
	var fa := FileAccess.open(ProjectSettings.globalize_path("res://").path_join("../captures/validation.json"), FileAccess.WRITE)
	fa.store_string(JSON.stringify(out, "  "))
	fa.close()
	quit()
	return true
