## A combatant: the player or a bot. Movement states (blimp, skydive, glide, ground), health and shield,
## the five-slot inventory, ammo, firing, reloading and consumables. Input comes from player.gd or bot.gd.
class_name Actor
extends CharacterBody3D

enum State { BLIMP, SKYDIVE, GLIDE, GROUND, DEAD }

const WALK := 5.2
const SPRINT := 7.6
const JUMP := 8.2
const GRAVITY := 24.0
const GLIDER_HEIGHT := 42.0
const EYE := Vector3(0, 1.55, 0)
const PICKAXE_DAMAGE := 20.0

var game: Node
var display_name := "Player"
var is_player := false
var state := State.BLIMP
var hp := 100.0
var shield := 0.0
var kills := 0
var slots: Array = [null, null, null, null, null]
var active := -1                         # 0..4 = hotbar slot, -1 = pickaxe
var ammo := {"light": 0, "medium": 0, "heavy": 0, "shells": 0, "rockets": 0}
var body: Character
var spread_mul := 1.0                    # bots: aim error on top of the weapon spread
var placement := 0
var ever_armed := false
var mats := {"wood": 0, "brick": 0, "metal": 0}
var build_piece := ""                    # "" = not building, else wall / floor / stairs / cone
var build_mat := "wood"
var build_cd := 0.0

# control inputs, written by the player or the bot brain every physics tick
var in_move := Vector2.ZERO              # x = right, y = forward, relative to aim_yaw
var in_sprint := false
var in_jump := false
var in_fire := false
var in_dive := false
var aim_yaw := 0.0
var aim_pitch := 0.0

var fire_cd := 0.0
var reloading := 0.0
var using := 0.0
var use_total := 0.0
var use_slot := -1
var last_hit_from := Vector3.ZERO
var last_hit_time := -99.0
var last_attacker: Actor
var storm_time := 0.0
var fall_start := 0.0
var pickup_cd := 0.0


func setup(g: Node, nm: String, player: bool, outfit: Color, accent: Color) -> void:
	game = g
	display_name = nm
	is_player = player
	collision_layer = 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(50)
	floor_snap_length = 0.4
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	add_child(cs)
	body = Character.new()
	add_child(body)
	body.build(outfit, accent, [Color(0.95, 0.78, 0.62), Color(0.78, 0.56, 0.4), Color(0.5, 0.34, 0.24)][nm.hash() % 3])
	body.hold("pickaxe")


func alive() -> bool:
	return state != State.DEAD


func eye() -> Vector3:
	return global_position + EYE


func aim_dir() -> Vector3:
	return Vector3(-sin(aim_yaw) * cos(aim_pitch), sin(aim_pitch), -cos(aim_yaw) * cos(aim_pitch))


func height_above_ground() -> float:
	return global_position.y - maxf(game.terrain.height(global_position.x, global_position.z), 0.0)


# ----------------------------------------------------------------------------- movement

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	fire_cd = maxf(fire_cd - delta, 0.0)
	match state:
		State.BLIMP:
			global_position = game.blimp_seat()
			velocity = Vector3.ZERO
			if in_jump:
				jump_from_blimp()
		State.SKYDIVE:
			var fall := -52.0 if in_dive else -30.0
			var steer := 9.0 if in_dive else 16.0
			_air_move(delta, fall, steer, 3.0)
			if height_above_ground() <= GLIDER_HEIGHT:
				state = State.GLIDE
		State.GLIDE:
			_air_move(delta, -7.5, 14.0, 4.0)
			if is_on_floor() or global_position.y < 0.3:
				state = State.GROUND
		State.GROUND:
			_ground_move(delta)
	body.rotation.y = lerp_angle(body.rotation.y, aim_yaw, clampf(delta * 14.0, 0.0, 1.0))
	body.animate(delta, self)
	if state == State.GROUND:
		_combat(delta)
	elif using > 0.0:
		cancel_use()


func jump_from_blimp() -> void:
	if state != State.BLIMP:
		return
	state = State.SKYDIVE
	velocity = game.blimp_velocity() * 0.5 + Vector3(0, -6, 0)
	in_jump = false


func _wish() -> Vector3:
	var f := Vector3(-sin(aim_yaw), 0, -cos(aim_yaw))
	var r := Vector3(cos(aim_yaw), 0, -sin(aim_yaw))
	var w := f * in_move.y + r * in_move.x
	return w.normalized() if w.length() > 1.0 else w


func _air_move(delta: float, fall: float, speed: float, accel: float) -> void:
	var w := _wish() * speed
	velocity.x = move_toward(velocity.x, w.x, accel * speed * delta)
	velocity.z = move_toward(velocity.z, w.z, accel * speed * delta)
	velocity.y = move_toward(velocity.y, fall, 40.0 * delta)
	move_and_slide()


func _ground_move(delta: float) -> void:
	var in_water := global_position.y < -0.9
	var speed := (SPRINT if in_sprint and in_move.y > 0.1 and using <= 0.0 else WALK) * (0.55 if in_water else 1.0) * (0.6 if using > 0.0 else 1.0)
	var w := _wish() * speed
	var acc := 60.0 if is_on_floor() else 14.0
	velocity.x = move_toward(velocity.x, w.x, acc * delta)
	velocity.z = move_toward(velocity.z, w.z, acc * delta)
	if in_water:
		velocity.y = move_toward(velocity.y, 1.5 if global_position.y < -1.2 else 0.0, 30.0 * delta)   # float at the surface
	elif is_on_floor():
		if in_jump:
			velocity.y = JUMP
		fall_start = global_position.y
	else:
		velocity.y -= GRAVITY * delta
	in_jump = false
	var was_air := not is_on_floor()
	move_and_slide()
	if was_air and is_on_floor():
		var drop := fall_start - global_position.y
		if drop > 9.0:
			hit((drop - 9.0) * 7.0, null, true, global_position)
	if is_on_floor():
		fall_start = global_position.y


# ----------------------------------------------------------------------------- inventory

func item() -> Variant:
	return slots[active] if active >= 0 else null


func select(i: int) -> void:
	if (i == active and build_piece == "") or i < -1 or i >= Items.SLOTS:
		return
	build_piece = ""
	active = i
	reloading = 0.0
	cancel_use()
	fire_cd = maxf(fire_cd, 0.25)
	_refresh_held()


func set_build(piece: String) -> void:
	## Enter build mode with this piece; the same key again leaves it.
	build_piece = "" if build_piece == piece else piece
	reloading = 0.0
	cancel_use()
	in_fire = false
	if build_piece != "":
		body.hold("")
	else:
		_refresh_held()


func cycle_build_mat() -> void:
	build_mat = Structures.MATS[(Structures.MATS.find(build_mat) + 1) % Structures.MATS.size()]


func _refresh_held() -> void:
	if build_piece != "":
		body.hold("")
		return
	var it = item()
	body.hold(Items.def(it).asset if it != null else "pickaxe")


func free_slot() -> int:
	for i in Items.SLOTS:
		if slots[i] == null:
			return i
	return -1


func wants(it: Dictionary) -> bool:
	## Would walking over this pick it up?
	if it.has("ammo"):
		return true
	if it.has("mat"):
		return int(mats[it.mat]) < Structures.MAX_MATS
	var d: Dictionary = Items.def(it)
	if d.has("stack"):
		for s in slots:
			if s != null and s.id == it.id and s.count < d.stack:
				return true
	return free_slot() >= 0


func add_item(it: Dictionary) -> bool:
	if it.has("ammo"):
		ammo[it.ammo] += it.get("count", Items.AMMO_PICKUP[it.ammo])
		return true
	if it.has("mat"):
		mats[it.mat] = mini(int(mats[it.mat]) + int(it.count), Structures.MAX_MATS)
		return true
	var d: Dictionary = Items.def(it)
	if d.has("stack"):
		for s in slots:
			if s != null and s.id == it.id and s.count < d.stack:
				var take: int = mini(d.stack - s.count, it.count)
				s.count += take
				it.count -= take
				if it.count <= 0:
					return true
	var f := free_slot()
	if f < 0:
		return false
	slots[f] = it
	if active == -1 and d.kind == "weapon":
		select(f)
	elif f == active:
		_refresh_held()
	return true


func drop_slot(i: int) -> void:
	if i < 0 or slots[i] == null:
		return
	var it: Dictionary = slots[i]
	slots[i] = null
	game.spawn_pickup(it, global_position + Vector3(-sin(aim_yaw), 0.4, -cos(aim_yaw)) * 1.4)
	if i == active:
		reloading = 0.0
		cancel_use()
		_refresh_held()


func swap_with(it: Dictionary) -> void:
	## Inventory full: the held slot is dropped and replaced.
	var i := active if active >= 0 else 0
	drop_slot(i)
	slots[i] = it
	select(i)
	_refresh_held()


func best_weapon_slot(dist: float) -> int:
	var best := -1
	var best_score := -1.0
	for i in Items.SLOTS:
		var it = slots[i]
		if it == null or Items.def(it).kind != "weapon":
			continue
		var d: Dictionary = Items.def(it)
		if it.loaded <= 0 and ammo[d.ammo] <= 0:
			continue
		var score = 1.0 + it.rarity * 0.15
		match it.id:
			"shotgun": score *= 3.0 if dist < 12.0 else (1.0 if dist < 25.0 else 0.1)
			"pistol": score *= 1.3 if dist < 30.0 else 0.6
			"assault_rifle": score *= 2.2 if dist < 90.0 else 1.0
			"sniper_rifle": score *= 3.0 if dist > 55.0 else (0.5 if dist > 20.0 else 0.2)
			"rocket_launcher": score *= 2.4 if (dist > 14.0 and dist < 90.0) else 0.05
		if score > best_score:
			best_score = score
			best = i
	return best


func has_weapon() -> bool:
	return best_weapon_slot(30.0) >= 0


func find_item(id: String) -> int:
	for i in Items.SLOTS:
		if slots[i] != null and slots[i].id == id:
			return i
	return -1


# ----------------------------------------------------------------------------- combat

func _combat(delta: float) -> void:
	var it = item()
	if using > 0.0:
		using -= delta
		if using <= 0.0:
			_finish_use()
		return
	if reloading > 0.0:
		reloading -= delta
		if reloading <= 0.0 and it != null and Items.def(it).kind == "weapon":
			var d: Dictionary = Items.def(it)
			var take: int = mini(d.mag - it.loaded, ammo[d.ammo])
			it.loaded += take
			ammo[d.ammo] -= take
		return
	if build_piece != "":
		return                                         # placing pieces is driven by the controller
	if not in_fire or fire_cd > 0.0:
		return
	if it == null:
		_swing_pickaxe()
		return
	var d2: Dictionary = Items.def(it)
	match d2.kind:
		"weapon":
			if it.loaded <= 0:
				start_reload()
				return
			_shoot(it, d2)
			if not d2.auto and is_player:
				in_fire = false
		"throwable":
			_throw(it, d2)
			in_fire = false
		"heal", "shield":
			start_use()
			in_fire = false


func start_reload() -> void:
	var it = item()
	if it == null or reloading > 0.0 or Items.def(it).kind != "weapon":
		return
	var d: Dictionary = Items.def(it)
	if it.loaded >= d.mag or ammo[d.ammo] <= 0:
		return
	reloading = Items.reload_time(it)
	game.sfx("reload", global_position)


func start_use() -> void:
	var it = item()
	if it == null or using > 0.0:
		return
	var d: Dictionary = Items.def(it)
	if d.kind == "heal" and hp >= d.cap:
		return
	if d.kind == "shield" and shield >= d.cap:
		return
	using = d.use_time
	use_total = d.use_time
	use_slot = active


func cancel_use() -> void:
	using = 0.0
	use_slot = -1


func _finish_use() -> void:
	using = 0.0
	if use_slot < 0 or slots[use_slot] == null:
		return
	var it: Dictionary = slots[use_slot]
	var d: Dictionary = Items.def(it)
	if d.kind == "heal":
		hp = minf(hp + d.amount, d.cap)
	else:
		shield = minf(shield + d.amount, d.cap)
	it.count -= 1
	if it.count <= 0:
		slots[use_slot] = null
		_refresh_held()
	use_slot = -1
	game.sfx("use", global_position)


func _swing_pickaxe() -> void:
	fire_cd = 0.55
	body.swing = 1.0
	var from := eye()
	var dir := aim_dir()
	if is_player:                                      # the pickaxe hits the point under the crosshair
		dir = (game.player_aim_point() - from).normalized()
	var hitp = game.ray(from, from + dir * 3.2, self)
	if hitp.is_empty():
		return
	if hitp.collider is Actor:
		(hitp.collider as Actor).hit(PICKAXE_DAMAGE, self, false, global_position)
		game.on_damage_dealt(self, hitp.collider, PICKAXE_DAMAGE, hitp.position)
	else:
		game.structures.pickaxe_hit(self, hitp)


func _shoot(it: Dictionary, d: Dictionary) -> void:
	it.loaded -= 1
	fire_cd = 1.0 / d.rate
	var from := eye()
	var moving := Vector2(velocity.x, velocity.z).length() > 1.0
	var spread := deg_to_rad(d.spread * (1.35 if moving else 1.0) * (1.6 if not is_on_floor() else 1.0)) * spread_mul
	var base := aim_dir()
	if is_player:
		# aim where the camera looks, then shoot from the eye towards that point
		var target: Vector3 = game.player_aim_point()
		base = (target - from).normalized()
	game.sfx(it.id, global_position)
	if d.get("rocket", false):
		game.spawn_rocket(self, from + base * 1.2, base, Items.damage(it), d.radius)
		return
	for p in d.pellets:
		var dir := _jitter(base, spread)
		var to := from + dir * 400.0
		var res = game.ray(from, to, self)
		var endp: Vector3 = res.position if res.has("position") else to
		if res.has("collider") and res.collider is Actor:
			var victim: Actor = res.collider
			var dist := from.distance_to(endp)
			var dmg := Items.damage(it) * (1.0 if dist <= d.range else clampf(1.0 - (dist - d.range) / d.range, 0.35, 1.0))
			if endp.y - victim.global_position.y > 1.45 and d.pellets == 1:
				dmg *= 1.5                                    # headshot
			victim.hit(dmg, self, false, global_position)
			game.on_damage_dealt(self, victim, dmg, endp)
		elif res.has("collider"):
			game.structures.damage_at(res.collider, res.get("shape", 0), Items.damage(it), self, endp)
		game.fx_tracer(from + dir * 1.0 + Vector3(0, -0.2, 0), endp, it.rarity)


func _jitter(dir: Vector3, spread: float) -> Vector3:
	var a = game.rng.randf() * TAU
	var r := sqrt(game.rng.randf()) * spread
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	var x := dir.cross(up).normalized()
	var y := x.cross(dir).normalized()
	return (dir + (x * cos(a) + y * sin(a)) * tan(r)).normalized()


func _throw(it: Dictionary, d: Dictionary) -> void:
	fire_cd = 0.9
	var dir := (aim_dir() + Vector3(0, 0.28, 0)).normalized()
	game.spawn_grenade(self, eye() + dir * 0.8, dir * 19.0 + velocity * 0.5, d.damage, d.radius)
	it.count -= 1
	if it.count <= 0:
		slots[active] = null
		_refresh_held()


# ----------------------------------------------------------------------------- damage

func hit(amount: float, attacker: Actor, bypass_shield: bool, from: Vector3) -> void:
	if state == State.DEAD or state == State.BLIMP or amount <= 0.0:
		return
	if attacker != null and attacker != self:
		last_attacker = attacker
		last_hit_from = from
		last_hit_time = game.match_time
		cancel_use()
	var left := amount
	if not bypass_shield and shield > 0.0:
		var s := minf(shield, left)
		shield -= s
		left -= s
	hp -= left
	if hp <= 0.0:
		die(attacker if attacker != null else (last_attacker if game.match_time - last_hit_time < 8.0 else null))


func die(killer: Actor) -> void:
	if state == State.DEAD:
		return
	hp = 0.0
	shield = 0.0
	state = State.DEAD
	collision_layer = 0
	collision_mask = 0
	body.visible = false
	# eliminated players drop everything they carried
	var p := global_position + Vector3(0, 0.3, 0)
	var n := 0
	for i in Items.SLOTS:
		if slots[i] != null:
			game.spawn_pickup(slots[i], p + Vector3(cos(n * 1.3), 0, sin(n * 1.3)) * 1.1)
			slots[i] = null
			n += 1
	for m in Structures.MATS:
		if int(mats[m]) > 0:
			game.spawn_pickup({"mat": m, "count": mats[m]}, p + Vector3(cos(n * 1.3), 0, sin(n * 1.3)) * 2.2)
			mats[m] = 0
			n += 1
	build_piece = ""
	for t in Items.AMMO_TYPES:
		if ammo[t] > 0:
			game.spawn_pickup({"ammo": t, "count": ammo[t]}, p + Vector3(cos(n * 1.3), 0, sin(n * 1.3)) * 1.7)
			ammo[t] = 0
			n += 1
	game.on_eliminated(self, killer)
