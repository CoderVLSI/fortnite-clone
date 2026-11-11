## Bot brain. Drives an Actor through the same inputs as the player: picks a landing spot, loots until armed,
## fights with line-of-sight perception and skill-based reaction and aim, heals, stays ahead of the storm
## and hunts other players late in the match.
extends Node

var game: Node
var a: Actor
var skill := 0.5                         # 0 = slow and inaccurate, 1 = sharp
var mode := "drop"
var drop_target := Vector3.ZERO
var jump_at := 10.0
var target: Actor
var target_seen := -99.0
var first_seen := -99.0
var last_known := Vector3.ZERO
var goal := Vector3.ZERO
var has_goal := false
var path := PackedVector3Array()
var path_i := 0
var repath := 0.0
var think := 0.0
var strafe := 1.0
var strafe_t := 0.0
var burst_t := 0.0
var pause_t := 0.0
var stuck_t := 0.0
var open_t := 0.0
var aim_err := Vector2.ZERO
var err_t := 0.0
var goal_container = null
var goal_is_pickup := false
var roam_until := 0.0
var goal_since := 0.0
var progress_t := 0.0
var progress_d := 1e9
var avoid: Array = []                   # [position, until] goals that could not be reached


func setup(g: Node, actor: Actor, s: float) -> void:
	game = g
	a = actor
	skill = s
	a.spread_mul = lerpf(2.4, 1.1, skill)
	think = game.rng.randf() * 0.25
	# landing spot: a point of interest, or anywhere on land
	var T = game.terrain
	var pois: Array = [T.village, T.yard, T.farm, T.towers[0], T.towers[1], T.towers[2], T.lake + Vector2(30, 20)]
	var p: Vector2
	if game.rng.randf() < 0.55:
		p = pois[game.rng.randi() % pois.size()] + Vector2(game.rng.randf_range(-45, 45), game.rng.randf_range(-45, 45))
	else:
		p = Vector2(game.rng.randf_range(-160, 160), game.rng.randf_range(-160, 160))
	drop_target = Vector3(p.x, 0, p.y)
	# leave the blimp near its closest approach to that spot
	var rel: Vector3 = drop_target - game.blimp_from
	var t: float = rel.dot(game.blimp_dir) / game.BLIMP_SPEED
	jump_at = clampf(t - 3.0 + game.rng.randf_range(-2.0, 2.0), 1.5, game.BLIMP_TIME - 1.0)


func _physics_process(delta: float) -> void:
	if not a.alive() or game.over:
		a.in_fire = false
		a.in_move = Vector2.ZERO
		return
	match a.state:
		Actor.State.BLIMP:
			if game.match_time >= jump_at:
				a.in_jump = true
		Actor.State.SKYDIVE, Actor.State.GLIDE:
			var to := drop_target - a.global_position
			to.y = 0
			var d := to.length()
			a.aim_yaw = atan2(-to.x, -to.z)
			a.aim_pitch = 0.0
			a.in_move = Vector2(0, 1) if d > 4.0 else Vector2.ZERO
			a.in_dive = a.state == Actor.State.SKYDIVE and d < 60.0
		Actor.State.GROUND:
			_ground(delta)


func _ground(delta: float) -> void:
	think -= delta
	if think <= 0.0:
		think = 0.2
		_perceive()
		_decide()
	a.in_fire = false
	a.in_sprint = true
	a.in_move = Vector2.ZERO
	if mode == "fight" and target != null and target.alive():
		_fight(delta)
		return
	if a.using > 0.0:
		return
	if has_goal:
		_follow(delta)


# ----------------------------------------------------------------------------- perception

func _perceive() -> void:
	var best: Actor = null
	var bd := 95.0
	var fwd := Vector3(-sin(a.aim_yaw), 0, -cos(a.aim_yaw))
	for o in game.actors:
		if o == a or not o.alive() or o.state == Actor.State.BLIMP or o.state == Actor.State.SKYDIVE:
			continue
		var to: Vector3 = o.global_position - a.global_position
		var d := to.length()
		if d > bd:
			continue
		var heard = o == a.last_attacker and game.match_time - a.last_hit_time < 3.0
		if d > 14.0 and not heard and fwd.dot(to.normalized()) < 0.15:
			continue                                              # outside the field of view
		if not game.can_see(a.eye(), o.eye()):
			continue
		bd = d
		best = o
	if best != null:
		if best != target:
			first_seen = game.match_time
		target = best
		target_seen = game.match_time
		last_known = best.global_position
	elif target != null and (not target.alive() or game.match_time - target_seen > 3.0):
		target = null


# ----------------------------------------------------------------------------- decisions

func _set_goal(p: Vector3) -> void:
	if not has_goal or goal.distance_to(p) > 3.0:
		goal = p
		has_goal = true
		repath = 0.0
		goal_since = game.match_time
		progress_t = game.match_time
		progress_d = 1e9


func _avoided(p: Vector3) -> bool:
	for e in avoid:
		if e[1] > game.match_time and e[0].distance_squared_to(p) < 9.0:
			return true
	return false


func _give_up() -> void:
	avoid.append([goal, game.match_time + 40.0])
	goal_is_pickup = false
	if avoid.size() > 12:
		avoid.pop_front()
	has_goal = false
	goal_container = null


func _safe_point(spread: float) -> Vector3:
	var s: Storm = game.storm
	for i in 12:
		var ang = game.rng.randf() * TAU
		var c: Vector2 = s.next_center + Vector2(cos(ang), sin(ang)) * game.rng.randf() * maxf(s.next_radius * spread, 4.0)
		if not game.terrain.is_water(c.x, c.y):
			return Vector3(c.x, game.terrain.height(c.x, c.y), c.y)
	return Vector3(s.next_center.x, 0, s.next_center.y)


func _decide() -> void:
	var s: Storm = game.storm
	var pos := a.global_position
	var out_now := s.outside(pos)
	var out_next := s.outside_next(pos)
	var armed := a.has_weapon()
	goal_container = null
	# stranded on a roof or platform: walk off it
	if pos.y - maxf(game.terrain.height(pos.x, pos.z), 0.0) > 2.4 and a.is_on_floor():
		mode = "descend"
		if not has_goal or game.match_time - goal_since > 3.0:
			var ang: float = game.rng.randf() * TAU
			has_goal = false
			_set_goal(pos + Vector3(cos(ang), 0, sin(ang)) * 14.0)
		return
	# a goal that cannot be reached is dropped for a while
	if has_goal:
		var gd := Vector2(goal.x - pos.x, goal.z - pos.z).length()
		if gd < progress_d - 1.0:
			progress_d = gd
			progress_t = game.match_time
		elif game.match_time - progress_t > 5.0 and mode != "storm":
			_give_up()
	# 1. the storm comes first
	var must_move := out_now > -6.0 or (out_next > 0.0 and (s.shrinking or s.time_left() < 22.0 + out_next / 4.5))
	if must_move and s.active:
		mode = "storm"
		if not has_goal or s.outside_next(goal) > -3.0:
			_set_goal(_safe_point(0.6))
		return
	# 2. fight what we can see
	if target != null and target.alive() and game.match_time - target_seen < 1.2:
		# unarmed bots only swing back at someone right on top of them; otherwise they keep looking for a weapon
		var cornered: bool = a.global_position.distance_to(target.global_position) < 2.4 and target == a.last_attacker and game.match_time - a.last_hit_time < 2.0
		if armed or cornered:
			mode = "fight"
			return
	# 3. patch up when it is quiet
	var quiet: bool = target == null and game.match_time - a.last_hit_time > 4.0
	if quiet and a.using <= 0.0:
		var mk := a.find_item("medkit")
		var sp := a.find_item("shield_potion")
		if a.hp < 60.0 and mk >= 0:
			a.select(mk); a.start_use(); mode = "heal"; return
		if a.shield < 50.0 and sp >= 0:
			a.select(sp); a.start_use(); mode = "heal"; return
	if a.using > 0.0:
		mode = "heal"
		return
	# 4. loot: anything useful close by, and until armed go looking for it
	var reach := 90.0 if not armed else 16.0
	var pk = _wanted_pickup(reach, not armed)
	if pk == null and not armed:
		pk = _wanted_pickup(25.0, false)
	if pk != null:
		mode = "loot"
		if not (has_goal and goal_is_pickup and _pickup_at(goal) and a.global_position.distance_to(goal) < a.global_position.distance_to(pk.pos) + 5.0):
			_set_goal(pk.pos)
			goal_is_pickup = true
		return
	goal_is_pickup = false
	var c = game.nearest_container(pos, 110.0 if not armed else 30.0)
	if c != null and s.outside_next(c.pos) < 0.0 and not _avoided(c.pos):
		mode = "loot"
		goal_container = c
		_set_goal(c.pos)
		return
	# 5. late in the match, hunt
	if armed and (game.alive_count() <= 9 or s.phase >= 2):
		var prey := _nearest_enemy()
		if prey != null:
			mode = "hunt"
			_set_goal(prey.global_position)
			return
	# 6. otherwise drift towards the next circle
	mode = "roam"
	if not has_goal or game.match_time > roam_until or pos.distance_to(goal) < 4.0:
		roam_until = game.match_time + 14.0
		_set_goal(_safe_point(0.75))


func _wanted_pickup(max_d: float, weapons_only := false) -> Variant:
	var best = null
	var bd := max_d * max_d
	for p in game.pickups:
		var d := a.global_position.distance_squared_to(p.pos)
		if d < bd and a.wants(p.item) and not _avoided(p.pos) and game.nav.walkable(p.pos) and p.pos.y - game.terrain.height(p.pos.x, p.pos.z) < 1.6 and game.storm.outside_next(p.pos) < 0.0:
			if p.item.has("ammo") and d > 400.0:
				continue
			if weapons_only and (p.item.has("ammo") or Items.def(p.item).kind != "weapon"):
				continue
			bd = d
			best = p
	return best


func _pickup_at(p: Vector3) -> bool:
	for k in game.pickups:
		if k.pos.distance_squared_to(p) < 0.3 and a.wants(k.item) and not _avoided(k.pos):
			return true
	return false


func _nearest_enemy() -> Actor:
	var best: Actor = null
	var bd := 1e9
	for o in game.actors:
		if o != a and o.alive() and o.state == Actor.State.GROUND:
			var d := a.global_position.distance_squared_to(o.global_position)
			if d < bd:
				bd = d
				best = o
	return best


# ----------------------------------------------------------------------------- movement

func _follow(delta: float) -> void:
	repath -= delta
	if repath <= 0.0:
		repath = 1.6
		path = game.nav_path(a.global_position, goal)
		path_i = 1
	var wp := goal
	while path_i < path.size():
		wp = path[path_i]
		# reached it, or already ran past it (so a fast runner never circles a waypoint)
		var seg: Vector3 = wp - path[path_i - 1]
		var rest: Vector3 = wp - a.global_position
		seg.y = 0
		rest.y = 0
		if rest.length() < 0.6 or (path_i < path.size() - 1 and seg.dot(rest) < 0.0):
			path_i += 1
		else:
			break
	var to := wp - a.global_position
	to.y = 0
	var dist_goal := Vector2(goal.x - a.global_position.x, goal.z - a.global_position.z).length()
	if goal_container != null and dist_goal < 2.4:
		open_t += delta
		if open_t > 0.5:
			game.open_container(goal_container, a)
			goal_container = null
			open_t = 0.0
			has_goal = false
		return
	open_t = 0.0
	if dist_goal < 0.7:
		has_goal = false
		return
	if mode == "descend":                      # no path-finding up here: just walk to the edge
		to = goal - a.global_position
		to.y = 0
	a.aim_yaw = lerp_angle(a.aim_yaw, atan2(-to.x, -to.z), clampf(delta * 22.0, 0.0, 1.0))
	a.aim_pitch = lerpf(a.aim_pitch, 0.0, delta * 5.0)
	a.in_move = Vector2(0, 1)
	a.in_sprint = to.length() > 2.5 or path_i >= path.size() - 1       # slow down for tight corners and doorways
	# unstick: hop, then sidestep
	if Vector2(a.velocity.x, a.velocity.z).length() < 0.8:
		stuck_t += delta
		if stuck_t > 0.5:
			a.in_jump = true
			a.in_move = Vector2(strafe, 0.6)
		if stuck_t > 1.6:
			stuck_t = 0.0
			strafe = -strafe
			repath = 0.0
	else:
		stuck_t = 0.0


# ----------------------------------------------------------------------------- combat

func _fight(delta: float) -> void:
	var tp := target.global_position + Vector3(0, 1.15, 0)
	var from := a.eye()
	var dist := from.distance_to(tp)
	var visible = game.match_time - target_seen < 0.45
	var slot := a.best_weapon_slot(dist)
	if slot >= 0 and slot != a.active:
		a.select(slot)
	elif slot < 0 and a.active != -1:
		a.select(-1)
	# aim: lead the target, with an error that wanders and shrinks with skill
	err_t -= delta
	if err_t <= 0.0:
		err_t = lerpf(0.5, 0.25, skill)
		var e := lerpf(0.075, 0.012, skill)
		aim_err = Vector2(game.rng.randf_range(-e, e), game.rng.randf_range(-e, e))
	var lead := target.velocity * clampf(dist / 180.0, 0.0, 0.35) * skill
	var d := (tp + lead - from)
	var want_yaw := atan2(-d.x, -d.z) + aim_err.x
	var want_pitch := atan2(d.y, Vector2(d.x, d.z).length()) + aim_err.y
	var turn := clampf(delta * lerpf(6.0, 16.0, skill), 0.0, 1.0)
	a.aim_yaw = lerp_angle(a.aim_yaw, want_yaw, turn)
	a.aim_pitch = lerpf(a.aim_pitch, want_pitch, turn)
	# move: strafe, close in or back off depending on the weapon
	strafe_t -= delta
	if strafe_t <= 0.0:
		strafe_t = game.rng.randf_range(0.5, 1.4)
		strafe = -strafe if game.rng.randf() < 0.7 else strafe
	var it = a.item()
	var want_d := 18.0
	if it != null:
		match it.id:
			"shotgun": want_d = 7.0
			"pistol": want_d = 14.0
			"sniper_rifle": want_d = 70.0
			"rocket_launcher": want_d = 30.0
			_: want_d = 26.0
	else:
		want_d = 1.6
	var fwd := 0.0
	if dist > want_d * 1.25 or not visible:
		fwd = 1.0
	elif dist < want_d * 0.6:
		fwd = -0.8
	a.in_move = Vector2(strafe * (0.9 if visible else 0.2), fwd)
	a.in_sprint = fwd > 0.5 and dist > 30.0
	if game.rng.randf() < delta * 0.25 * skill and visible:
		a.in_jump = true
	# fire in bursts once the reaction time has passed
	var reacted: bool = game.match_time - first_seen > lerpf(0.9, 0.22, skill)
	if not visible or not reacted or a.reloading > 0.0:
		return
	if absf(angle_difference(a.aim_yaw, want_yaw)) > 0.12:
		return
	if it == null:
		a.in_fire = dist < 2.6
		return
	if Items.def(it).kind != "weapon":
		return
	if dist > Items.def(it).range * 0.85:      # do not waste ammo beyond the weapon's range: close in instead
		a.in_move = Vector2(strafe * 0.4, 1.0)
		a.in_sprint = true
		return
	if pause_t > 0.0:
		pause_t -= delta
		return
	a.in_fire = true
	burst_t += delta
	var burst_len := 0.9 if Items.def(it).auto else 0.25
	if burst_t > burst_len:
		burst_t = 0.0
		pause_t = lerpf(0.55, 0.18, skill) if Items.def(it).auto else 0.05
