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
var wp_fail := 0
var open_t := 0.0
var aim_err := Vector2.ZERO
var err_t := 0.0
var goal_container = null
var goal_is_pickup := false
var roam_until := 0.0
var goal_since := 0.0
var crouch_bias := false
var progress_t := 0.0
var progress_d := 1e9
var avoid: Array = []                   # [position, until] goals that could not be reached
var wp_i := -1                          # the waypoint being walked to, and the closest the bot has come to it
var wp_best := 1e9
var wp_t := 0.0
var moved_from := Vector3.ZERO          # where the bot was half a second ago, to measure real movement
var moved_t := 0.0
var stuck_n := 0                        # consecutive half-seconds without real movement
var escape_to := Vector3.INF            # a clear spot to back off to when wedged
var escape_until := 0.0
var junk: Array = []                    # items this bot threw away, never to be picked up again by it


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
	# never aim for water, a steep bank or the inside of a building
	for i in 20:
		if game.nav.dry(Vector3(p.x, 0, p.y)):
			break
		p += Vector2(game.rng.randf_range(-12, 12), game.rng.randf_range(-12, 12))
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
		Actor.State.GROUND, Actor.State.SWIM:
			_ground(delta)


func _ground(delta: float) -> void:
	think -= delta
	if think <= 0.0:
		think = 0.2
		_perceive()
		_decide()
		# crouch while healing, and now and then when fighting at range
		if a.state == Actor.State.GROUND and not a.sliding:
			var far: bool = mode == "fight" and target != null and a.global_position.distance_to(target.global_position) > 35.0
			a.set_crouched(mode == "heal" or (far and crouch_bias))
	a.in_fire = false
	a.in_sprint = true
	a.in_move = Vector2.ZERO
	if a.emote != "" and a.emote_t < 3.0 and not (target != null and target.alive() and game.match_time - target_seen < 0.5):
		return                                     # finish the celebration unless someone shows up
	a.stop_emote()
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
			crouch_bias = game.rng.randf() < 0.5
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
		var p := Vector3(c.x, game.terrain.height(c.x, c.y), c.y)
		if not game.terrain.is_water(c.x, c.y) and game.nav.dry(p) and not _avoided(p):
			return p
	return Vector3(s.next_center.x, 0, s.next_center.y)


func _way_down(pos: Vector3) -> Vector3:
	## Up on a roof, a platform or an upper storey: the nearest spot in plain reach where the floor drops away
	## (an edge, or the top of a staircase), a little past it so the bot steps over. Random if there is none.
	var eye := pos + Vector3(0, 1.0, 0)
	var best := Vector3.INF
	var bd := 1e9
	var start: float = game.rng.randf() * TAU
	for k in 16:
		var ang: float = start + k * TAU / 16.0
		var dir := Vector3(cos(ang), 0, sin(ang))
		var r := 1.0
		while r <= 14.0:
			var p := pos + dir * r
			if not game.can_see(eye, p + Vector3(0, 1.0, 0)):
				break                                         # a wall in the way
			var hit: Dictionary = game.ray(p + Vector3(0, 0.6, 0), p + Vector3(0, -30, 0), a, 1)
			var below: float = hit.position.y if not hit.is_empty() else -10.0
			if below < pos.y - 0.6:
				if r < bd:
					bd = r
					best = pos + dir * (r + 1.2)
				break
			r += 0.5
	if best == Vector3.INF:
		var ang2: float = game.rng.randf() * TAU
		best = pos + Vector3(cos(ang2), 0, sin(ang2)) * 6.0
	return best


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
		if not has_goal or game.match_time - goal_since > 4.0 or Vector2(goal.x - pos.x, goal.z - pos.z).length() < 0.8:
			has_goal = false
			_set_goal(_way_down(pos))
		return
	# a goal that cannot be reached is dropped for a while
	if has_goal:
		var gd := Vector2(goal.x - pos.x, goal.z - pos.z).length()
		if gd < progress_d - 1.0:
			progress_d = gd
			progress_t = game.match_time
		elif game.match_time - progress_t > 5.0:
			if mode == "storm":                # try another safe spot rather than standing in the storm
				avoid.append([goal, game.match_time + 20.0])
				has_goal = false
				_set_goal(_safe_point(0.6))
			else:
				_give_up()
	# 1. the storm comes first
	var must_move := out_now > -6.0 or (out_next > 0.0 and (s.shrinking or s.time_left() < 22.0 + out_next / 4.5))
	if must_move and s.active:
		mode = "storm"
		if not has_goal or s.outside_next(goal) > -3.0 or _avoided(goal):
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
		if mk < 0:
			mk = a.find_item("healing_drink")
		var sp := a.find_item("shield_potion")
		if sp < 0 and a.shield < 50.0:
			sp = a.find_item("small_shield")
		if a.hp < 60.0 and mk >= 0:
			a.select(mk); a.start_use(); mode = "heal"; return
		if a.shield < 50.0 and sp >= 0:
			a.select(sp); a.start_use(); mode = "heal"; return
	if a.using > 0.0:
		mode = "heal"
		return
	# 4. loot: anything useful close by; until armed, or when the guns run low, go looking for it
	var low := _ammo_low()
	var reach := 16.0
	if not armed:
		reach = 110.0
	elif not low.is_empty():
		reach = 50.0
	var pk = _wanted_pickup(reach, armed, low)
	if pk == null and not armed:
		pk = _wanted_pickup(170.0, armed, low)
	if pk != null:
		mode = "loot"
		if not (has_goal and goal_is_pickup and _pickup_at(goal) and a.global_position.distance_to(goal) < a.global_position.distance_to(pk.pos) + 5.0):
			_set_goal(pk.pos)
			goal_is_pickup = true
		return
	goal_is_pickup = false
	var c = game.nearest_container(pos, 110.0 if not armed else (50.0 if not low.is_empty() else 30.0))
	if c != null and _storm_allows(c.pos) and not _avoided(c.pos):
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
	if game.autotest and not armed and OS.get_cmdline_user_args().has("--trace") and int(game.match_time * 5) % 50 == 0:
		_debug_loot()
	mode = "roam"
	if not has_goal or game.match_time > roam_until or pos.distance_to(goal) < 4.0:
		roam_until = game.match_time + 14.0
		_set_goal(_safe_point(0.75))


func _wanted_pickup(max_d: float, armed: bool, low: Array) -> Variant:
	## The best pickup in reach. Unarmed: a weapon, or ammo for a gun already carried. Low on ammo: that ammo.
	## Otherwise anything worth having close by. Nearer is better; what is needed most counts as nearer.
	var best = null
	var bs := 1e9
	var lim := max_d * max_d
	for p in game.pickups:
		var d := a.global_position.distance_squared_to(p.pos)
		if d > lim or junk.has(p.item) or not _worth(p.item) or _avoided(p.pos) or not _reachable(p.pos):
			continue
		if p.pos.y - game.terrain.height(p.pos.x, p.pos.z) > 1.6 or not _storm_allows(p.pos):
			continue
		var it: Dictionary = p.item
		var need := 1.0
		if it.has("ammo"):
			if low.has(it.ammo):
				need = 0.3
			elif _carries_gun_for(it.ammo) and (not armed):
				need = 0.3
			elif d > 400.0:
				continue
		elif it.has("id") and Items.def(it).kind == "weapon":
			need = 0.4 if not armed else 0.8
		elif not armed or not low.is_empty():
			continue                                   # heals and the like can wait until there is something to shoot
		var sc := d * need
		if sc < bs:
			bs = sc
			best = p
	return best


func _reachable(p: Vector3) -> bool:
	## On dry walkable ground, or close enough to it to be picked up from there (loot dropped against a wall).
	if game.nav.dry(p):
		return true
	for o in [Vector3(0.9, 0, 0), Vector3(-0.9, 0, 0), Vector3(0, 0, 0.9), Vector3(0, 0, -0.9)]:
		if game.nav.dry(p + o):
			return true
	return false


func _storm_allows(p: Vector3) -> bool:
	## Inside the next circle, or the storm is far enough off that there is time to grab it and still get in.
	var s: Storm = game.storm
	if s.outside_next(p) <= 0.0:
		return true
	return not s.shrinking and s.time_left() > 20.0 + s.outside_next(p) / 4.0 and s.outside(p) < -15.0


func _carries_gun_for(ammo_type: String) -> bool:
	for it in a.slots:
		if it != null and Items.def(it).kind == "weapon" and Items.def(it).ammo == ammo_type:
			return true
	return false


func _ammo_low() -> Array:
	## Ammo types the bot is short of: every gun it carries wants at least two magazines in all.
	var out := []
	for it in a.slots:
		if it == null or Items.def(it).kind != "weapon":
			continue
		var d: Dictionary = Items.def(it)
		if it.loaded + int(a.ammo[d.ammo]) < d.mag * 2 and not out.has(d.ammo):
			out.append(d.ammo)
	return out


func _worth(it: Dictionary) -> bool:
	## Would the bot take this, making room for it if it has to?
	if a.wants(it):
		return true
	return it.has("id") and _junk_slot(it) >= 0


func _usable(it: Dictionary) -> bool:
	var d: Dictionary = Items.def(it)
	return d.kind != "weapon" or it.loaded > 0 or int(a.ammo[d.ammo]) > 0


func _junk_slot(new_it: Dictionary) -> int:
	## With a full inventory, the slot this item should replace, or -1 if it is not worth it.
	var nd: Dictionary = Items.def(new_it)
	var heals := 0
	for it in a.slots:
		if it != null and Items.def(it).kind in ["heal", "shield"]:
			heals += 1
	var best := -1
	var worst := 1e9
	for i in Items.SLOTS:
		var it = a.slots[i]
		if it == null:
			return -1                                  # there is room: nothing to throw away
		var d: Dictionary = Items.def(it)
		var v := 10.0
		if d.kind == "weapon":
			if not _usable(it):
				v = 0.0                                # a gun with nothing to shoot
			elif nd.kind == "weapon" and it.id == new_it.id:
				v = 1.0 + it.rarity if new_it.rarity > it.rarity else 99.0
			else:
				v = 20.0 + it.rarity
		elif d.kind in ["heal", "shield"]:
			v = 3.0 if heals > 2 else 12.0
		elif d.kind == "throwable" or d.kind == "launcher":
			v = 4.0
		if v < worst:
			worst = v
			best = i
	# a weapon is worth a gun with nothing to shoot, a surplus heal or a gadget; anything else only replaces junk
	var keep_below := 15.0 if nd.kind == "weapon" else 1.0
	return best if worst < keep_below else -1


func _swap_in(p: Dictionary) -> void:
	## At the pickup with a full inventory: drop the junk slot and take the item.
	var i := _junk_slot(p.item)
	if i < 0:
		return
	junk.append(a.slots[i])
	if junk.size() > 8:
		junk.pop_front()
	a.select(i)
	a.swap_with(p.item)
	if p.item.has("id") and Items.def(p.item).kind == "weapon":
		a.ever_armed = true
	game.remove_pickup(p)


func _pickup_at(p: Vector3) -> bool:
	for k in game.pickups:
		if k.pos.distance_squared_to(p) < 0.3 and _worth(k.item) and not junk.has(k.item) and not _avoided(k.pos):
			return true
	return false


func _nearest_enemy() -> Actor:
	var best: Actor = null
	var bd := 1e9
	for o in game.actors:
		if o != a and o.alive() and (o.state == Actor.State.GROUND or o.state == Actor.State.SWIM):
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
	# grinding along a wall without getting closer to the waypoint counts as stuck, even at full speed
	if path_i != wp_i:
		wp_i = path_i
		wp_fail = 0
		wp_best = to.length()
		wp_t = game.match_time
	elif to.length() < wp_best - 0.3:
		wp_best = to.length()
		wp_t = game.match_time
		wp_fail = 0
	elif game.match_time - wp_t > 1.5:
		wp_t = game.match_time
		wp_fail += 1
		if path_i < path.size() - 1 and game.can_see(a.eye(), path[path_i + 1] + Vector3(0, 1.0, 0)):
			path_i += 1                        # the next corner is in plain view: cut to it
		elif wp_fail >= 2 and escape_to == Vector3.INF:
			escape_to = _escape_point(wp - a.global_position)
			escape_until = game.match_time + 1.4
			wp_fail = 0
		else:
			repath = 0.0
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
	if goal_is_pickup and dist_goal < 1.6:
		for k in game.pickups:
			if k.pos.distance_squared_to(goal) < 0.3 and not a.wants(k.item) and _worth(k.item):
				_swap_in(k)
				has_goal = false
				return
	if dist_goal < 0.7:
		has_goal = false
		return
	if mode == "descend":                      # no path-finding up here: just walk to the edge
		to = goal - a.global_position
		to.y = 0
	if escape_to != Vector3.INF:               # backing out of a wedge
		if game.match_time < escape_until and Vector2(escape_to.x - a.global_position.x, escape_to.z - a.global_position.z).length() > 0.5:
			to = escape_to - a.global_position
			to.y = 0
		else:
			escape_to = Vector3.INF
			repath = 0.0
	if _shooting_on_the_move():
		_fire_on_the_move(delta, to)
	else:
		a.aim_yaw = lerp_angle(a.aim_yaw, atan2(-to.x, -to.z), clampf(delta * 22.0, 0.0, 1.0))
		a.aim_pitch = lerpf(a.aim_pitch, 0.0, delta * 5.0)
		a.in_move = Vector2(0, 1)
		a.in_sprint = to.length() > 2.5 or path_i >= path.size() - 1       # slow down for tight corners and doorways
	_unstick(to)


func _shooting_on_the_move() -> bool:
	return mode == "storm" and target != null and target.alive() and game.match_time - target_seen < 0.45 and a.has_weapon() and a.state == Actor.State.GROUND


func _unstick(to: Vector3) -> void:
	## Measured on real movement, not on velocity: a bot pressed into a corner can report full speed while going nowhere.
	if game.match_time - moved_t < 0.5:
		if stuck_n >= 1:
			a.in_jump = stuck_n == 1 or stuck_n == 3
			a.in_move = Vector2(strafe, 0.6)
		return
	var moved := Vector2(a.global_position.x - moved_from.x, a.global_position.z - moved_from.z).length()
	moved_from = a.global_position
	moved_t = game.match_time
	if moved > 0.6 or a.state == Actor.State.SWIM and moved > 0.3:
		stuck_n = 0
		return
	stuck_n += 1
	if stuck_n == 2:
		strafe = -strafe
	if stuck_n >= 4 and escape_to == Vector3.INF:
		escape_to = _escape_point(to)
		escape_until = game.match_time + 1.4
		stuck_n = 1
		repath = 0.0


func _escape_point(toward: Vector3) -> Vector3:
	## A spot a couple of metres away with nothing between it and the bot, at knee and chest height,
	## preferring the direction it was trying to go.
	var p := a.global_position
	var want := Vector2(toward.x, toward.z).normalized()
	var best := Vector3.INF
	var bs := -1e9
	var start: float = game.rng.randf() * TAU
	for k in 12:
		var ang: float = start + k * TAU / 12.0
		var d := Vector2(cos(ang), sin(ang))
		for r in [2.5, 1.5]:
			var q: Vector3 = p + Vector3(d.x, 0, d.y) * r
			if not game.nav.walkable(q):
				continue
			if not game.can_see(p + Vector3(0, 0.45, 0), q + Vector3(0, 0.45, 0)) or not game.can_see(p + Vector3(0, 1.3, 0), q + Vector3(0, 1.3, 0)):
				continue
			var sc: float = d.dot(want) + r * 0.2 + game.rng.randf() * 0.3
			if sc > bs:
				bs = sc
				best = q
			break
	if best == Vector3.INF:
		var ang2: float = game.rng.randf() * TAU
		best = p + Vector3(cos(ang2), 0, sin(ang2)) * 2.0
	return best


func _keep_footing() -> void:
	## Fighting moves (strafing, backing off) never step off solid ground into water, a ravine or a wall.
	if a.state != Actor.State.GROUND or not game.nav.dry(a.global_position):
		return
	var yaw := a.aim_yaw
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var p := a.global_position
	if a.in_move.x != 0.0 and not game.nav.dry(p + right * signf(a.in_move.x) * 1.8):
		strafe = -strafe
		a.in_move.x = -a.in_move.x
		strafe_t = 0.8
	if a.in_move.y != 0.0 and not game.nav.dry(p + fwd * signf(a.in_move.y) * 1.8):
		a.in_move.y = 0.0


# ----------------------------------------------------------------------------- combat

func _aim(delta: float) -> float:
	## Pick the weapon for the range and turn toward the target, leading it, with an error that wanders and
	## shrinks with skill. Returns the yaw the bot is turning to.
	var tp := target.centre()
	var from := a.eye()
	var dist := from.distance_to(tp)
	var slot := a.best_weapon_slot(dist)
	if slot >= 0 and slot != a.active:
		a.select(slot)
	elif slot < 0 and a.active != -1:
		a.select(-1)
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
	return want_yaw


func _trigger(delta: float, dist: float, want_yaw: float) -> void:
	## Fire in bursts once the reaction time has passed and the aim is on, within the weapon's range.
	var it = a.item()
	if it == null or Items.def(it).kind != "weapon" or a.reloading > 0.0:
		return
	if game.match_time - first_seen < lerpf(0.9, 0.22, skill) or absf(angle_difference(a.aim_yaw, want_yaw)) > 0.12:
		return
	if dist > Items.def(it).range * 0.85:
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


func _fire_on_the_move(delta: float, move_dir: Vector3) -> void:
	## Running from the storm (or to it) with an enemy in sight: keep going the same way, but face and shoot them.
	var dist := a.eye().distance_to(target.centre())
	var want_yaw := _aim(delta)
	var fwd := Vector3(-sin(a.aim_yaw), 0, -cos(a.aim_yaw))
	var right := Vector3(cos(a.aim_yaw), 0, -sin(a.aim_yaw))
	var m := move_dir.normalized()
	a.in_move = Vector2(m.dot(right), m.dot(fwd))
	a.in_sprint = false
	_trigger(delta, dist, want_yaw)


func _fight(delta: float) -> void:
	var from := a.eye()
	var dist := from.distance_to(target.centre())
	var visible = game.match_time - target_seen < 0.45
	var want_yaw := _aim(delta)
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
	_keep_footing()
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
		_keep_footing()
		return
	_trigger(delta, dist, want_yaw)


func _debug_loot() -> void:
	var r := {"total": 0, "far": 0, "junk": 0, "notworth": 0, "avoided": 0, "wet": 0, "high": 0, "storm": 0, "ok": 0}
	var kinds := {}
	for p in game.pickups:
		r.total += 1
		var it: Dictionary = p.item
		var k: String = it.get("id", "ammo:" + it.get("ammo", "") if it.has("ammo") else ("mat" if it.has("mat") else "forage"))
		if a.global_position.distance_to(p.pos) > 110.0: r.far += 1; continue
		if junk.has(it): r.junk += 1; continue
		if not _worth(it): r.notworth += 1; continue
		if _avoided(p.pos): r.avoided += 1; continue
		if not game.nav.dry(p.pos): r.wet += 1; continue
		if p.pos.y - game.terrain.height(p.pos.x, p.pos.z) > 1.6: r.high += 1; continue
		if game.storm.outside_next(p.pos) > 0.0: r.storm += 1; continue
		r.ok += 1
		kinds[k] = kinds.get(k, 0) + 1
	var inv := []
	for it in a.slots:
		inv.append(("%s(%d+%d)" % [it.id, it.get("loaded", 0), int(a.ammo[Items.def(it).ammo]) if Items.def(it).kind == "weapon" else 0]) if it != null else "-")
	print("LOOTDBG %.0f %s inv=%s %s ok_kinds=%s" % [game.match_time, a.display_name, inv, r, kinds])
