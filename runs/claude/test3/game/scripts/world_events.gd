## Items, traversal and world events:
## - supply drops that fall from the sky under their canopy with a smoke trail, and hold better loot;
## - launch pads, placed or thrown, that throw you high into the air and open the glider;
## - zip lines between the hills and towers;
## - rifts that send you back into skydiving;
## - apples under the oaks and mushrooms in the pine forest, eaten by walking over them.
class_name WorldEvents
extends Node3D

const DROP_TIMES := [100.0, 200.0, 300.0]
const DROP_HEIGHT := 120.0
const DROP_SPEED := 6.0
const PAD_LAUNCH := 46.0
const ZIP_SPEED := 15.0
const RIFT_HEIGHT := 100.0

var game: Node
var drops: Array = []            # {node, pos, landed, smoke_t, smoke_until}
var drop_i := 0
var pads: Array = []             # {node, pos}
var thrown: Array = []           # launch pads in flight {node, vel}
var zips: Array = []             # {a, b, length, sag}
var rifts: Array = []            # {node, pos}
var benches: Array = []          # upgrade benches: {node, pos}
const UPGRADE_COST := [100, 150, 200, 250]    # gold to go up from Common, Uncommon, Rare, Epic
var puffs: Array = []
var pois: Array = []             # named places: {name, pos (Vector2), r, label}
var poi_current := ""            # the place the player is standing in
var poi_banner := {}             # {name, sub, t (real seconds)}: the "entering" banner, drawn by hud.gd
var poi_tick := 0
var cooldown := {}               # actor instance id -> time it may trigger a pad or rift again
var puff_mesh: SphereMesh


func setup(g: Node) -> void:
	game = g
	puff_mesh = SphereMesh.new()
	puff_mesh.radius = 0.5
	puff_mesh.height = 1.0
	puff_mesh.radial_segments = 8
	puff_mesh.rings = 4
	_build_zips()
	_build_rifts()
	_build_benches()
	_spawn_forage()
	_build_pois()


# ----------------------------------------------------------------------------- set-up

func _tower_deck(i: int, toward: Vector3) -> Vector3:
	## A point at hand height on tower i's deck, on the side facing `toward`.
	return _deck_at(game.terrain.towers[i], toward)


func _deck_at(tp: Vector2, toward: Vector3) -> Vector3:
	## The same for whichever tower stands nearest to `tp`.
	var best: Node3D = null
	for n in game.island.find_children("LookoutTower_*", "Node3D", true, false):
		if best == null or Vector2(n.global_position.x, n.global_position.z).distance_to(tp) < Vector2(best.global_position.x, best.global_position.z).distance_to(tp):
			best = n
	var base: Vector3 = best.global_position if best else Vector3(tp.x, game.terrain.height(tp.x, tp.y), tp.y)
	var dir := Vector3(toward.x - base.x, 0, toward.z - base.z).normalized()
	return base + Vector3(0, 7.0 + 2.6, 0) + dir * 1.2


func _ground_anchor(p: Vector2) -> Vector3:
	var h: float = game.terrain.height(p.x, p.y)
	return Vector3(p.x, h + 4.2, p.y)


func _build_zips() -> void:
	var T = game.terrain
	var hill_w := _ground_anchor(T.px(190, 300))
	var hill_n := _ground_anchor(T.px(760, 120))
	var hill_c := _ground_anchor(T.px(470, 250))
	var lines := [[_tower_deck(0, hill_w), hill_w], [_tower_deck(2, Vector3.ZERO), Vector3.ZERO], [hill_n, hill_c]]
	# the middle line runs between the south and south-east towers
	lines[1] = [_tower_deck(2, _tower_deck(1, Vector3.ZERO)), _tower_deck(1, _tower_deck(2, Vector3.ZERO))]
	# the big island: towers down to the towns, and up onto the desert mesas (the only way up without building)
	var snow_t: Vector2 = T.extra_towers[0]
	var west_t: Vector2 = T.extra_towers[1]
	var east_t: Vector2 = T.extra_towers[2]
	var snow_town := _ground_anchor(T.snow_town + (snow_t - T.snow_town).normalized() * 30.0)
	lines.append([_deck_at(snow_t, snow_town), snow_town])
	var cove := _ground_anchor(T.east_cove + (east_t - T.east_cove).normalized() * 26.0)
	lines.append([_deck_at(east_t, cove), cove])
	var desert := _ground_anchor(T.desert_town + Vector2(30, -20))
	lines.append([_mesa_top(T.mesas[0], desert), desert])
	var depot := _ground_anchor(T.depot + Vector2(-36, -22))
	lines.append([_mesa_top(T.mesas[3], depot), depot])
	lines.append([_deck_at(west_t, _mesa_top(T.mesas[2], Vector3.ZERO)), _mesa_top(T.mesas[2], _deck_at(west_t, Vector3.ZERO))])
	for l in lines.duplicate():
		if not _clear(l[0], l[1]):
			push_warning("zip line skipped: the cable would cut through the ground")
			lines.erase(l)
	for l in lines:
		var a: Vector3 = l[0]
		var b: Vector3 = l[1]
		var length := a.distance_to(b)
		var z := {"a": a, "b": b, "length": length, "sag": length * 0.02}
		zips.append(z)
		_draw_zip(z)


func _mesa_top(m: Array, toward: Vector3) -> Vector3:
	## A pole near the edge of a mesa top, on the side facing `toward`.
	var c: Vector2 = m[0]
	var d := Vector2(toward.x, toward.z) - c
	var p := c + (d.normalized() if d.length() > 1.0 else Vector2.RIGHT) * (float(m[1]) - 8.0)
	return _ground_anchor(p)


func _clear(a: Vector3, b: Vector3) -> bool:
	## The cable stays at least a metre above the ground all the way.
	var z := {"a": a, "b": b, "length": a.distance_to(b), "sag": a.distance_to(b) * 0.02}
	for i in range(2, 39):
		var p := cable_point(z, i / 40.0)
		if p.y < game.terrain.height(p.x, p.z) + 1.0:
			return false
	return true


func cable_point(z: Dictionary, t: float) -> Vector3:
	return (z.a as Vector3).lerp(z.b, t) - Vector3(0, float(z.sag) * 4.0 * t * (1.0 - t), 0)


func _draw_zip(z: Dictionary) -> void:
	var dark := Color(0.18, 0.19, 0.22)
	var segs := 16
	for i in segs:
		var p0 := cable_point(z, float(i) / segs)
		var p1 := cable_point(z, float(i + 1) / segs)
		var mi := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.035
		c.bottom_radius = 0.035
		c.height = p0.distance_to(p1)
		c.radial_segments = 6
		mi.mesh = c
		mi.material_override = _flat(dark)
		add_child(mi)
		mi.global_position = (p0 + p1) / 2.0
		var dir := (p1 - p0).normalized()
		mi.global_transform.basis = Basis(Quaternion(Vector3.UP, dir))
	for end in [z.a, z.b]:
		var g: float = game.terrain.height(end.x, end.z)
		var h: float = end.y - g + 0.3
		if h > 6.0:
			continue                                    # anchored on a tower deck
		var pole := MeshInstance3D.new()
		var pc := CylinderMesh.new()
		pc.top_radius = 0.12
		pc.bottom_radius = 0.16
		pc.height = h
		pole.mesh = pc
		pole.material_override = _flat(Color(0.45, 0.3, 0.16))
		add_child(pole)
		pole.global_position = Vector3(end.x, g + h / 2.0, end.z)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.16
		cyl.height = h
		cs.shape = cyl
		body.add_child(cs)
		pole.add_child(body)
		var lamp := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.18
		sm.height = 0.36
		lamp.mesh = sm
		lamp.material_override = Models.glow_material(Color(1.0, 0.8, 0.25), 2.0, 0.9)
		add_child(lamp)
		lamp.global_position = Vector3(end.x, g + h + 0.15, end.z)


func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
	return m


func _build_benches() -> void:
	## An upgrade bench in every town: hold a weapon, pay gold, and it goes up a rarity.
	var T = game.terrain
	for p in [T.village + Vector2(9, 7), T.yard + Vector2(-8, 12), T.farm + Vector2(10, -6), T.snow_town + Vector2(7, 4),
			T.desert_town + Vector2(-7, 5), T.depot + Vector2(0, 16), T.west_hamlet + Vector2(6, -5), T.east_cove + Vector2(-6, 6)]:
		var spot := _dry_spot(p)
		var n := Models.make("upgrade_bench")
		add_child(n)
		n.global_position = spot
		n.rotation.y = atan2(p.x - spot.x, p.y - spot.z) + game.rng.randf_range(-0.3, 0.3)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.8, 1.0, 0.8)
		cs.shape = box
		cs.position = Vector3(0, 0.5, 0)
		body.add_child(cs)
		n.add_child(body)
		benches.append({"node": n, "pos": spot})


func bench_near(a: Actor) -> Variant:
	for b in benches:
		if a.global_position.distance_to(b.pos) < 2.6:
			return b
	return null


func upgrade_cost(rarity: int) -> int:
	return UPGRADE_COST[clampi(rarity, 0, UPGRADE_COST.size() - 1)]


func upgrade(a: Actor) -> bool:
	## The held weapon goes up one rarity for gold.
	var it = a.item()
	if it == null or Items.def(it).kind != "weapon" or it.rarity >= 4:
		return false
	var cost := upgrade_cost(it.rarity)
	if a.gold < cost:
		return false
	a.gold -= cost
	it.rarity += 1
	game.sfx("chest_open", a.global_position)
	if a.is_player and game.hud:
		game.hud.add_pickup_note(it)
		game.announce("Upgraded to %s" % Items.label(it))
	game.stats["upgrades"] = game.stats.get("upgrades", 0) + 1
	return true


func _build_rifts() -> void:
	var T = game.terrain
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled, blend_add;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float swirl = sin(a * 5.0 + r * 9.0 - TIME * 4.0) * 0.5 + 0.5;
	vec3 col = mix(vec3(0.35, 0.15, 0.9), vec3(0.3, 0.85, 1.0), swirl);
	ALBEDO = col;
	ALPHA = smoothstep(1.0, 0.75, r) * (0.55 + 0.35 * swirl);
}"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var where: Array = [T.village + Vector2(48, -36), T.farm + Vector2(-46, 34), T.yard + Vector2(18, -50),
			T.snow_town + Vector2(34, 22), T.desert_town + Vector2(-34, -26), T.depot + Vector2(-44, 14),
			T.west_hamlet + Vector2(30, -32), T.east_cove + Vector2(-34, 26), T.lake + Vector2(-40, -10), Vector2(170, -230)]
	for p in where:
		var spot := _dry_spot(p)
		var n := Node3D.new()
		add_child(n)
		n.global_position = spot + Vector3(0, 1.8, 0)
		var disc := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(3.2, 3.2)
		disc.mesh = q
		disc.material_override = mat
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(disc)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 1.45
		tm.outer_radius = 1.7
		ring.mesh = tm
		ring.rotation.x = PI / 2
		ring.material_override = Models.glow_material(Color(0.55, 0.35, 1.0), 2.5, 0.9)
		n.add_child(ring)
		rifts.append({"node": n, "pos": spot})


func _dry_spot(p: Vector2) -> Vector3:
	## The nearest walkable point to p, searching outwards.
	for r in range(0, 40, 2):
		for k in 12:
			var q := p + Vector2(cos(TAU * k / 12.0), sin(TAU * k / 12.0)) * r
			var v := Vector3(q.x, game.terrain.height(q.x, q.y), q.y)
			if game.nav.walkable(v) and game.terrain.water_surface(q.x, q.y) < -999.0:
				return v
	return Vector3(p.x, game.terrain.height(p.x, p.y), p.y)


func _spawn_forage() -> void:
	## Apples under some of the oaks, mushrooms among the pines.
	var S: Structures = game.structures
	var oaks: Array = []
	var pines: Array = []
	for tb in S.trees.values():
		for e in tb.values():
			if e.name == "tree_oak":
				oaks.append(e)
			elif String(e.name).begins_with("tree_pine"):
				pines.append(e)
	var n := 0
	for list in [[oaks, "apple", 70], [pines, "mushroom", 50]]:
		var arr: Array = list[0]
		for i in mini(list[2], arr.size()):
			var e: Dictionary = arr[game.rng.randi() % arr.size()]
			var a: float = game.rng.randf() * TAU
			var p: Vector3 = e.pos + Vector3(cos(a), 0, sin(a)) * game.rng.randf_range(1.2, 2.5)
			p.y = game.terrain.height(p.x, p.z)
			game.spawn_pickup({"forage": list[1]}, p)
			n += 1
	game.stats["forage"] = n


# ----------------------------------------------------------------------------- named places

func _build_pois() -> void:
	## The points of interest: name, centre and radius. Several entries may share a name (the mesas stand apart).
	var T = game.terrain
	var m: Array = T.mesas
	var pair: Vector2 = ((m[0][0] as Vector2) + (m[1][0] as Vector2)) / 2.0
	for d in [["Oakmoor Village", T.village, 62.0], ["Gearworks Yard", T.yard, 64.0], ["Hayfield Farm", T.farm, 62.0],
			["Mirror Lake", T.lake, 46.0], ["Frostpeak", T.snow_town, 50.0], ["Sunscorch", T.desert_town, 48.0],
			["Sandbar Depot", T.depot, 46.0], ["Willow Hamlet", T.west_hamlet, 40.0], ["Gull Cove", T.east_cove, 38.0]]:
		pois.append({"name": d[0], "pos": d[1], "r": d[2], "label": true})
	pois.append({"name": "Red Mesas", "pos": pair, "r": 62.0, "label": true})
	pois.append({"name": "Red Mesas", "pos": m[2][0], "r": float(m[2][1]) + 24.0, "label": true})
	pois.append({"name": "Red Mesas", "pos": m[3][0], "r": float(m[3][1]) + 24.0, "label": true})


func poi_names() -> Array:
	var out: Array = []
	for p in pois:
		if not out.has(p.name):
			out.append(p.name)
	return out


func poi_at(p: Vector2) -> String:
	## The name of the place this point is in ("" in the wilds); the one it is deepest inside wins.
	var best := ""
	var best_k := 1.0
	for q in pois:
		var k: float = p.distance_to(q.pos) / float(q.r)
		if k < best_k:
			best_k = k
			best = q.name
	return best


func _update_poi() -> void:
	## Walking into a named place shows its banner (not while still on the blimp or skydiving).
	var p: Actor = game.player
	if p == null or not p.alive() or p.state == Actor.State.BLIMP or p.state == Actor.State.SKYDIVE:
		return
	var nm := poi_at(Vector2(p.global_position.x, p.global_position.z))
	if nm == poi_current:
		return
	poi_current = nm
	if nm == "":
		return
	var sub := ""
	if game.get("bosses") != null:
		sub = game.bosses.poi_subtitle(nm)
	poi_banner = {"name": nm, "sub": sub, "t": Time.get_ticks_msec() / 1000.0}


# ----------------------------------------------------------------------------- frame

func _physics_process(delta: float) -> void:
	poi_tick += 1
	if poi_tick % 6 == 0:
		_update_poi()
	if drop_i < DROP_TIMES.size() and game.match_time >= DROP_TIMES[drop_i] and game.storm.active:
		drop_i += 1
		spawn_drop()
	for d in drops:
		if not d.landed:
			var n: Node3D = d.node
			var ground: float = _ground_below(n.global_position)
			n.global_position.y = maxf(n.global_position.y - DROP_SPEED * delta, ground)
			n.rotation.y += delta * 0.4
			if n.global_position.y <= ground + 0.01:
				_land(d)
		if game.match_time < d.smoke_until:
			d.smoke_t -= delta
			if d.smoke_t <= 0.0:
				d.smoke_t = 0.12
				_puff((d.node as Node3D).global_position + Vector3(game.rng.randf_range(-0.3, 0.3), 0.2, game.rng.randf_range(-0.3, 0.3)))
	for p in puffs.duplicate():
		p.life -= delta
		var mi: MeshInstance3D = p.node
		mi.position += Vector3(0, 0.9, 0) * delta
		mi.scale = Vector3.ONE * (0.6 + (3.0 - p.life) * 0.9)
		(mi.material_override as StandardMaterial3D).albedo_color.a = clampf(p.life / 3.0, 0.0, 1.0) * 0.55
		if p.life <= 0.0:
			puffs.erase(p)
			mi.queue_free()
	for t in thrown.duplicate():
		_fly_pad(t, delta)
	for a in game.actors:
		if not a.alive() or a.state != Actor.State.GROUND or a.zip != null or a.mantle_t >= 0.0:
			continue
		if cooldown.get(a.get_instance_id(), -99.0) > game.match_time:
			continue
		for p in pads:
			var dx := Vector2(a.global_position.x - p.pos.x, a.global_position.z - p.pos.z).length()
			if dx < 1.3 and absf(a.global_position.y - p.pos.y) < 0.9:
				a.launch(PAD_LAUNCH)
				game.stats["pad_launches"] = game.stats.get("pad_launches", 0) + 1
				cooldown[a.get_instance_id()] = game.match_time + 1.5
				game.sfx("launch", p.pos)
				break
		for r in rifts:
			var dr := Vector2(a.global_position.x - r.pos.x, a.global_position.z - r.pos.z).length()
			if dr < 1.4 and absf(a.global_position.y - r.pos.y) < 2.5:
				_rift(a)
				break
	for r in rifts:
		(r.node as Node3D).rotation.y += delta * 0.8


func _ground_below(p: Vector3) -> float:
	var res: Dictionary = game.ray(p + Vector3(0, 0.5, 0), p - Vector3(0, 200, 0), null, 1)
	return res.position.y if not res.is_empty() else game.terrain.height(p.x, p.z)


# ----------------------------------------------------------------------------- supply drops

func spawn_drop(at := Vector3.INF) -> Dictionary:
	var p := at
	if p == Vector3.INF:
		var s: Storm = game.storm
		p = _dry_spot(s.next_center + Vector2.from_angle(game.rng.randf() * TAU) * game.rng.randf() * maxf(s.next_radius * 0.6, 5.0))
	var n := Models.make("supply_drop")
	add_child(n)
	n.global_position = p + Vector3(0, DROP_HEIGHT, 0)
	var d := {"node": n, "pos": p, "landed": false, "smoke_t": 0.0, "smoke_until": game.match_time + 1e6}
	drops.append(d)
	game.announce("A supply drop is falling")
	return d


func _land(d: Dictionary) -> void:
	d.landed = true
	game.sfx("supply_drop_land", (d.node as Node3D).global_position)
	d.smoke_until = game.match_time + 12.0
	var n: Node3D = d.node
	d.pos = n.global_position
	var chute := n.find_child("supply_parachute", true, false) as Node3D
	if chute:
		var tw := create_tween()
		tw.tween_property(chute, "scale", Vector3(1, 0.02, 1), 1.2)
		tw.tween_callback(chute.hide)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.2, 1.2, 1.2)
	cs.shape = bs
	cs.position = Vector3(0, 0.6, 0)
	body.add_child(cs)
	n.add_child(body)
	game._add_glow(n, Items.RARITY_COLORS[4], 1.1)
	game.containers.append({"node": n, "pos": n.global_position, "kind": "supply_drop", "opened": false, "lid": null})


func _puff(at: Vector3) -> void:
	if game.autotest:
		game.stats["smoke_puffs"] = game.stats.get("smoke_puffs", 0) + 1
		return
	var mi := MeshInstance3D.new()
	mi.mesh = puff_mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.62, 0.85, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	game.fx_root.add_child(mi)
	mi.global_position = at
	puffs.append({"node": mi, "life": 3.0})
	game.stats["smoke_puffs"] = game.stats.get("smoke_puffs", 0) + 1


# ----------------------------------------------------------------------------- launch pads

func deploy_pad(a: Actor) -> bool:
	## Looking down places the pad in front of you; otherwise it is thrown.
	var fwd := Vector3(-sin(a.aim_yaw), 0, -cos(a.aim_yaw))
	if a.aim_pitch < -0.45:
		var at: Vector3 = a.global_position + fwd * 2.2
		var res: Dictionary = game.ray(at + Vector3(0, 2.0, 0), at - Vector3(0, 4.0, 0), a, 1)
		if res.is_empty() or res.normal.y < 0.7:
			return false
		place_pad(res.position)
		return true
	var n := Models.make("launch_pad")
	n.scale = Vector3.ONE * 0.45
	add_child(n)
	n.global_position = a.eye() + fwd * 0.8
	thrown.append({"node": n, "vel": a.aim_dir() * 12.0 + Vector3(0, 4.0, 0) + a.velocity * 0.4, "owner": a})
	return true


func _fly_pad(t: Dictionary, delta: float) -> void:
	var n: Node3D = t.node
	t.vel.y -= 20.0 * delta
	var from := n.global_position
	var to: Vector3 = from + t.vel * delta
	var res: Dictionary = game.ray(from, to, t.owner, 1)
	if not res.is_empty():
		if res.normal.y > 0.7:
			thrown.erase(t)
			n.queue_free()
			place_pad(res.position)
			return
		t.vel = (t.vel as Vector3).bounce(res.normal) * 0.4
		to = res.position + res.normal * 0.1
	n.global_position = to
	n.rotate_y(delta * 8.0)
	if to.y < -5.0:
		thrown.erase(t)
		n.queue_free()


func place_pad(at: Vector3) -> Dictionary:
	var n := Models.make("launch_pad")
	add_child(n)
	n.global_position = at
	var p := {"node": n, "pos": at}
	pads.append(p)
	if pads.size() > 12:
		var old: Dictionary = pads.pop_front()
		(old.node as Node).queue_free()
	return p


# ----------------------------------------------------------------------------- zip lines and rifts

func zip_near(a: Actor) -> Variant:
	## [zip, start t] when the actor stands at either end of a zip line.
	for z in zips:
		for end in [0.0, 1.0]:
			var p := cable_point(z, end)
			var feet := a.global_position
			if Vector2(p.x - feet.x, p.z - feet.z).length() < 3.2 and p.y - feet.y > 1.0 and p.y - feet.y < 5.5:
				return [z, end]
	return null


func _rift(a: Actor) -> void:
	game.stats["rifts_used"] = game.stats.get("rifts_used", 0) + 1
	cooldown[a.get_instance_id()] = game.match_time + 3.0
	var p := a.global_position
	_puff(p + Vector3(0, 1.0, 0))
	a.zip = null
	a.global_position = Vector3(p.x, maxf(game.terrain.height(p.x, p.z), 0.0) + RIFT_HEIGHT, p.z)
	a.velocity = Vector3(a.velocity.x, -4.0, a.velocity.z)
	a.state = Actor.State.SKYDIVE
	a.launched = false
	game.stats["rifts_used"] = game.stats.get("rifts_used", 0) + 1
	game.sfx("rift", p)
