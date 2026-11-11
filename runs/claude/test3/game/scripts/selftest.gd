## Automated check of building, collapse, harvesting and explosions.  Run:
##   godot --headless --path <project> -- --buildtest
extends Node

var game: Node
var lines: Array = []
var fails := 0


func setup(g: Node) -> void:
	game = g


func check(name: String, ok: bool, detail := "") -> void:
	lines.append(("PASS  " if ok else "FAIL  ") + name + ("   " + detail if detail != "" else ""))
	if not ok:
		fails += 1


func snap(name: String, yaw: float, pitch: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	game.controller.yaw = yaw
	game.controller.pitch = pitch
	await frames(8)
	var dir := ProjectSettings.globalize_path("res://").path_join("../captures")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("SNAP ", name)


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ready() -> void:
	await frames(5)
	var S: Structures = game.structures
	var a: Actor = game.player
	check("level destructibles registered", S.level_count > 500, "%d parts" % S.level_count)
	# stand on open ground in the village, out of the blimp
	var spot := Vector3(game.terrain.village.x + 22.0, 0, game.terrain.village.y + 4.0)
	spot.y = game.terrain.height(spot.x, spot.z) + 0.3
	a.state = Actor.State.GROUND
	a.global_position = spot
	a.velocity = Vector3.ZERO
	await frames(20)
	a.mats = {"wood": 300, "brick": 100, "metal": 60}
	a.aim_yaw = 0.0                       # facing north
	a.aim_pitch = 0.0
	# --- a wall in front, a floor ahead, a ceiling floor above the wall
	a.set_build("wall")
	check("wall placed", S.place(a), "pieces=%d" % S.pieces.size())
	check("wall costs 10 wood", a.mats.wood == 290)
	check("same spot cannot be built twice", not S.place(a))
	var wall = S.pieces.values()[0]
	check("wall rests on the ground", wall.grounded)
	check("hit points start low", wall.hp < 30.0, "%.0f" % wall.hp)
	await frames(int(Structures.BUILD_TIME.wood * 60.0) + 10)
	check("wood wall climbs to 150", absf(wall.hp - 150.0) < 1.0, "%.1f" % wall.hp)
	a.set_build("floor")
	a.aim_pitch = 0.8                     # looking up: floor above our own cell
	check("ceiling floor placed", S.place(a))
	var ceiling = S.pieces.values()[S.pieces.size() - 1]
	check("ceiling is held up, not grounded", not ceiling.grounded and ceiling.level == 1, "level=%d" % ceiling.level)
	a.aim_pitch = 0.0
	check("floor ahead placed", S.place(a))
	var ground_floor = S.pieces.values()[S.pieces.size() - 1]
	# --- brick and metal reach their own hit points
	a.cycle_build_mat()
	check("material cycles to brick", a.build_mat == "brick")
	a.set_build("stairs")
	a.aim_yaw = PI / 2                    # facing west
	check("brick stairs placed", S.place(a))
	var stairs = S.pieces.values()[S.pieces.size() - 1]
	a.cycle_build_mat()
	a.set_build("wall")
	a.aim_yaw = PI                        # facing south
	check("metal wall placed", S.place(a))
	var metal = S.pieces.values()[S.pieces.size() - 1]
	await frames(int(Structures.BUILD_TIME.metal * 60.0) + 10)
	check("brick climbs to 300", absf(stairs.hp - 300.0) < 1.0, "%.1f" % stairs.hp)
	a.build_piece = "floor"
	a.build_mat = "wood"
	await snap("build_01_pieces", PI * 0.78, -0.38)
	a.build_piece = ""
	check("metal climbs to 450", absf(metal.hp - 450.0) < 1.0, "%.1f" % metal.hp)
	# --- explosions: 2.5 times their damage to structures
	var before: float = metal.hp
	S.explode(metal.pos, 5.5, 100.0 * Structures.EXPLOSION_MULT, null)
	check("explosion hurts the metal wall by up to 250", before - metal.hp > 80.0 and before - metal.hp <= 250.0, "lost %.0f" % (before - metal.hp))
	# --- chain collapse: break the north wall and the ceiling it holds must fall; the ground floor stays
	var n_before := S.pieces.size()
	S.damage(wall, 1000.0, null, wall.pos)
	await frames(90)
	check("wall destroyed", wall.dead)
	var ceiling_ok: bool = ceiling.dead
	var others_held: bool = not ceiling.grounded
	for e in S.pieces.values():
		if e != ceiling and e.dead:
			others_held = false
	check("unsupported ceiling collapsed", ceiling_ok, "pieces %d -> %d" % [n_before, S.pieces.size()])
	check("grounded floor still standing", not ground_floor.dead)
	# --- a tall tower collapses top to bottom when its base goes
	a.set_build("")
	a.build_piece = ""
	a.aim_yaw = -PI / 2                   # east: an edge nothing else touches
	var base_t: Dictionary = S.target(a, "wall")
	var col := []
	var t2 := base_t.duplicate()
	for lv in 4:
		var t3: Dictionary = base_t.duplicate()
		t3.level = lv
		t3.key = "W|tower|%d" % lv
		t3.xf = Transform3D(base_t.xf.basis, base_t.xf.origin + Vector3(0, lv * Structures.GRID, 0))
		var fe: Array = []
		for f in base_t.features:
			fe.append(_shift_feature(f, lv))
		t3.features = fe
		col.append(S.place_target(t3, "wood", a))
	check("4-storey wall column built", col.size() == 4 and col[0].grounded and not col[3].grounded)
	S.damage(col[0], 1000.0, null, col[0].pos)
	await frames(120)
	var all_gone := true
	for e in col:
		all_gone = all_gone and e.dead
	check("column collapses in a chain", all_gone)
	# --- harvesting a tree: materials, weak point, double yield
	var tree = null
	var bd := 1e9
	for tb in S.trees.values():
		for e in tb.values():
			var d: float = (e.pos as Vector3).distance_to(a.global_position)
			if not e.dead and d < bd:
				bd = d
				tree = e
	check("found a tree", tree != null)
	var tp: Vector3 = tree.pos
	var stand := Vector3(tp.x + 1.6, game.terrain.height(tp.x + 1.6, tp.z) + 0.2, tp.z)
	a.global_position = stand
	a.velocity = Vector3.ZERO
	await frames(5)
	var wood0: int = a.mats.wood
	var res: Dictionary = game.ray(a.eye(), Vector3(tp.x, a.eye().y, tp.z), a, 1)
	check("pickaxe ray reaches the trunk", not res.is_empty() and S.lookup(res.collider, res.get("shape", 0)) == tree)
	S.pickaxe_hit(a, res)
	var plain: int = a.mats.wood - wood0
	check("a hit yields wood", plain > 0, "+%d" % plain)
	check("weak point appears after a hit", S.weak.visible and S.weak_entry == tree)
	a.aim_yaw = atan2(-(tp.x - a.global_position.x), -(tp.z - a.global_position.z))
	a.select(-1)
	await snap("build_02_weak_point", a.aim_yaw, 0.05)
	var wp: Vector3 = S.weak.global_position
	var res2: Dictionary = game.ray(wp + (wp - tp).normalized() * 0.6 + Vector3(0, 0.0, 0), wp - (wp - tp).normalized() * 0.3, a, 1)
	var w1: int = a.mats.wood
	var hp1: float = tree.hp
	if not res2.is_empty():
		S.pickaxe_hit(a, res2)
	check("weak point doubles the yield", a.mats.wood - w1 == plain * 2, "+%d" % (a.mats.wood - w1))
	check("weak point doubles the damage", absf(hp1 - tree.hp - Structures.PICKAXE_DAMAGE * 2.0) < 0.1, "%.0f" % (hp1 - tree.hp))
	var hits := 0
	while not tree.dead and hits < 30:
		S.pickaxe_hit(a, res)
		hits += 1
	check("tree breaks under the pickaxe", tree.dead, "%d more hits" % hits)
	await frames(3)
	check("broken tree no longer blocks", game.ray(a.eye(), Vector3(tp.x, a.eye().y, tp.z), a, 1).is_empty() or S.lookup(game.ray(a.eye(), Vector3(tp.x, a.eye().y, tp.z), a, 1).collider, 0) != tree)
	# --- a gun shot damages a built wall
	a.global_position = spot + Vector3(0, 0.2, 8.0)
	await frames(5)
	a.mats.wood = 100
	a.build_mat = "wood"
	a.aim_yaw = 0.0
	a.aim_pitch = 0.0
	a.build_piece = "wall"
	S.place(a)
	var target_wall = S.pieces.values()[S.pieces.size() - 1]
	a.build_piece = ""
	await frames(130)
	var w_hp: float = target_wall.hp
	var hit_res: Dictionary = game.ray(a.eye(), a.eye() + Vector3(0, 0, -6), a, 1)
	S.damage_at(hit_res.collider, hit_res.get("shape", 0), 30.0, a, hit_res.position)
	check("bullet damage applies to a built wall", absf(w_hp - target_wall.hp - 30.0) < 0.1)
	# --- editing: windows, doors, half walls, floor holes, turned ramps, cone openings, reset
	var espot := Vector3(game.terrain.village.x - 20.0, 0, game.terrain.village.y + 14.0)
	espot.y = game.terrain.height(espot.x, espot.z) + 0.3
	a.state = Actor.State.GROUND
	a.global_position = espot
	a.velocity = Vector3.ZERO
	await frames(10)
	a.mats = {"wood": 200, "brick": 100, "metal": 60}
	a.build_mat = "wood"
	a.aim_yaw = 0.0
	a.aim_pitch = 0.0
	a.build_piece = "wall"
	S.place(a)
	var ew = S.pieces.values()[S.pieces.size() - 1]
	a.build_piece = ""
	await frames(3)
	var wxf: Transform3D = (ew.root as Node3D).global_transform
	var eye := a.eye()
	var tile_c := func(i: int) -> Vector3: return wxf * Vector3(-2.0 + (i % 3 + 0.5) * 4.0 / 3.0, (i / 3 + 0.5) * 4.0 / 3.0, 0)
	check("edit grid opens on your own wall", S.begin_edit(a, ew))
	check("aiming picks the middle tile", S.edit_tile_at(ew, eye, (tile_c.call(4) - eye).normalized()) == 4)
	S.update_edit(a, eye, (tile_c.call(4) - eye).normalized(), true, true)
	await snap("edit_01_grid", a.aim_yaw + 0.35, -0.15)
	S.confirm_edit()
	await frames(2)
	var through := func(i: int) -> bool:
		var c: Vector3 = tile_c.call(i)
		var n: Vector3 = wxf.basis.z
		var r: Dictionary = game.ray(c + n * 1.0, c - n * 1.0, null, 1)
		return r.is_empty() or S.lookup(r.collider, r.get("shape", 0)) != ew
	check("window: the middle tile is open", through.call(4) and not through.call(0) and not through.call(8))
	check("window wall keeps 8 tiles", (ew.body as Node).get_child_count() == 8)
	S.begin_edit(a, ew)
	S.edit_sel = {1: true, 4: true}
	S.confirm_edit()
	await frames(2)
	check("door: bottom and middle of the centre column open", through.call(1) and through.call(4) and not through.call(7))
	S.begin_edit(a, ew)
	S.edit_sel = {6: true, 7: true, 8: true}
	S.confirm_edit()
	await frames(2)
	check("half wall: the top row is open", through.call(6) and through.call(7) and through.call(8) and not through.call(1))
	S.begin_edit(a, ew)
	S.edit_sel = {}
	for i in 9:
		S.edit_sel[i] = true
	S.confirm_edit()
	check("a wall cannot be cut away completely", (ew.edit as Array).size() == 3)
	S.begin_edit(a, ew)
	S.reset_edit()
	await frames(2)
	check("reset restores the whole wall", (ew.edit as Array).is_empty() and (ew.body as Node).get_child_count() == 1 and not through.call(4))
	check("someone else's piece cannot be edited", not S.begin_edit(game.actors[1], ew))
	# floor with a hole
	a.build_piece = "floor"
	a.aim_pitch = 0.0
	S.place(a)
	var ef = S.pieces.values()[S.pieces.size() - 1]
	a.build_piece = ""
	S.begin_edit(a, ef)
	S.edit_sel = {0: true}
	S.confirm_edit()
	await frames(2)
	var fxf: Transform3D = (ef.root as Node3D).global_transform
	var down0: Dictionary = game.ray(fxf * Vector3(-1, 2, -1), fxf * Vector3(-1, -1, -1), null, 1)
	var down3: Dictionary = game.ray(fxf * Vector3(1, 2, 1), fxf * Vector3(1, -1, 1), null, 1)
	check("floor: the cut tile is a hole", (down0.is_empty() or S.lookup(down0.collider, 0) != ef) and not down3.is_empty() and S.lookup(down3.collider, down3.get("shape", 0)) == ef)
	# turned ramp
	a.build_piece = "stairs"
	a.aim_yaw = PI / 2
	S.place(a)
	var es = S.pieces.values()[S.pieces.size() - 1]
	a.build_piece = ""
	var d0: int = es.dir
	S.begin_edit(a, es)
	S.edit_sel = {1: true, 3: true}
	S.confirm_edit()
	check("ramp turns towards the selected side", es.dir == (d0 + 1) % 4, "dir %d -> %d" % [d0, es.dir])
	S.begin_edit(a, es)
	S.edit_sel = {0: true, 3: true}
	check("a diagonal selection does not turn the ramp", not S.apply_edit(es, [0, 3]) and es.dir == (d0 + 1) % 4)
	S.cancel_edit()
	# cone with an opening
	a.build_piece = "cone"
	a.aim_yaw = PI
	S.place(a)
	var ec = S.pieces.values()[S.pieces.size() - 1]
	a.build_piece = ""
	S.begin_edit(a, ec)
	S.edit_sel = {0: true}
	S.confirm_edit()
	await frames(2)
	var cxf: Transform3D = (ec.root as Node3D).global_transform
	var c0: Dictionary = game.ray(cxf * Vector3(-1.4, 3, -1.4), cxf * Vector3(-1.4, -0.5, -1.4), null, 1)
	var c3: Dictionary = game.ray(cxf * Vector3(1.4, 3, 1.4), cxf * Vector3(1.4, -0.5, 1.4), null, 1)
	check("cone: the cut corner is open", (c0.is_empty() or S.lookup(c0.collider, 0) != ec) and not c3.is_empty() and S.lookup(c3.collider, c3.get("shape", 0)) == ec)
	await snap("edit_02_pieces", PI * 0.85, -0.4)
	# an edited wall still holds up what is built on it
	a.build_piece = "floor"
	a.aim_yaw = 0.0
	a.aim_pitch = 0.8
	S.place(a)
	var roof = S.pieces.values()[S.pieces.size() - 1]
	a.build_piece = ""
	S.begin_edit(a, ew)
	S.edit_sel = {4: true}
	S.confirm_edit()
	await frames(30)
	check("an edited wall still supports a floor", not roof.dead and not roof.grounded)
	# --- materials drop on elimination
	a.mats = {"wood": 40, "brick": 0, "metal": 7}
	var p_before: int = game.pickups.size()
	a.die(null)
	var mats_dropped := 0
	for p in game.pickups:
		if p.item.has("mat"):
			mats_dropped += 1
	check("materials drop on elimination", mats_dropped >= 2, "%d stacks" % mats_dropped)
	print("BUILDTEST\n" + "\n".join(lines))
	print("BUILDTEST %s  (%d checks, %d failed)" % ["OK" if fails == 0 else "FAILED", lines.size(), fails])
	get_tree().quit()


func _shift_feature(f: String, lv: int) -> String:
	## Move a wall's features up by `lv` storeys.
	var parts := f.split("|")
	if parts[0] == "E":
		parts[4] = str(int(parts[4]) + lv)
	elif parts[0] == "P":
		parts[3] = str(int(parts[3]) + lv)
	return "|".join(parts)
