## Automated check of Duos: teams, no friendly fire, knocked, revive, team elimination, the bot teammate and team placement.  Run:
##   godot --headless --path <project> -- --duotest
## --duoshots additionally saves captures (teammate HUD, knocked crawl, revive) into ../captures when a display is available.
extends Node

var game: Node
var p: Actor                                    # the player
var m: Actor                                    # the bot teammate (actors[1])
var e1: Actor
var e2: Actor
var lines: Array = []
var fails := 0
var base: Vector3


func setup(g: Node) -> void:
	game = g


func check(name: String, ok: bool, detail := "") -> void:
	lines.append(("PASS  " if ok else "FAIL  ") + name + ("   " + detail if detail != "" else ""))
	if not ok:
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func snap(name: String) -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--duoshots"):
		return
	await frames(8)
	var dir := ProjectSettings.globalize_path("res://").path_join("../captures")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("SNAP ", name)


func brain_of(x: Actor) -> Node:
	for c in x.get_children():
		if c.get("buddy") != null:
			return c
	return null


func place(x: Actor, pos: Vector3, yaw := 0.0) -> void:
	x.zip = null
	x.mantle_t = -1.0
	x.launched = false
	x.state = Actor.State.GROUND
	x.global_position = pos
	x.velocity = Vector3.ZERO
	x.aim_yaw = yaw
	x.aim_pitch = 0.0
	x.in_move = Vector2.ZERO
	x.fall_start = pos.y


func standing(x: Actor) -> void:
	## Back to a clean, healthy, standing actor (also brings back an eliminated one: tests only).
	if x.state == Actor.State.DEAD:
		x.state = Actor.State.GROUND
		x.collision_layer = 2
		x.collision_mask = 1
		x.body.visible = true
	x.knocked = false
	x.knock_hp = 0.0
	x.revive_t = 0.0
	x.revive_target = null
	x.hp = 100.0
	x.shield = 0.0
	x.placement = 0
	x.stun_t = 0.0
	x._set_height(Actor.STAND_H)


func equip(x: Actor, id: String) -> Dictionary:
	var it := Items.make(id, 2)
	x.slots = [it, null, null, null, null]
	for t in Items.AMMO_TYPES:
		x.ammo[t] = 200
	x.select(-1)
	x.select(0)
	x.fire_cd = 0.0
	x.reloading = 0.0
	x.spread_mul = 0.0
	return it


func hold_revive(who: Actor, n: int) -> void:
	for i in n:
		game.try_revive(who, true)
		await get_tree().physics_frame


func _ready() -> void:
	await frames(5)
	p = game.player
	m = game.actors[1]
	e1 = game.actors[2]
	e2 = game.actors[3]
	game.controller.demo = true                         # the test drives the player: no keyboard polling
	for o in game.actors:
		if o != p and o != m and o != e1 and o != e2:
			o.process_mode = Node.PROCESS_MODE_DISABLED
	for b in game.bosses.list:
		b.actor.process_mode = Node.PROCESS_MODE_DISABLED
	for o in [e1, e2]:
		brain_of(o).set_physics_process(false)
	var mb := brain_of(m)
	mb.set_physics_process(false)                       # the teammate brain wakes up for its own section
	var T = game.terrain
	base = game.events._dry_spot(T.village + Vector2(20, 8)) + Vector3(0, 0.1, 0)
	# ---------------------------------------------------------------- teams
	var teams := {}
	for o in game.actors:
		teams[o.team] = true
	check("Duos: the player and the bot teammate share a team", p.team == m.team and game.same_team(p, m) and game.partner_of(p) == m and game.partner_of(m) == p)
	check("Duos: every other bot is on its own team", teams.size() == game.actors.size() - 1 and not game.same_team(p, e1) and not game.same_team(e1, e2), "%d teams" % teams.size())
	check("Duos: still 50 players", game.actors.size() == 50)
	var br: Node = mb
	check("the teammate bot has the team brain around the player", br.buddy and br.ally_of == p)
	# ---------------------------------------------------------------- no friendly fire
	place(p, base)
	place(m, base + Vector3(0, 0, -6))
	place(e1, base + Vector3(3, 0, -6))
	standing(p); standing(m); standing(e1)
	equip(p, "assault_rifle")
	p.in_fire = true
	await frames(60)
	p.in_fire = false
	check("teammate bullets do no damage", m.hp == 100.0 and m.shield == 0.0, "%.0f" % m.hp)
	m.hit(30.0, p, false, Vector3.ZERO)
	check("a direct hit from a teammate does nothing", m.hp == 100.0)
	m.hit(30.0, e1, false, Vector3.ZERO)
	check("an enemy still hurts the teammate", m.hp == 70.0, "%.0f" % m.hp)
	standing(m)
	place(m, base + Vector3(0, 0, -1.4))
	p.select(-1)
	p.fire_cd = 0.0
	p.in_fire = true
	await frames(90)
	p.in_fire = false
	check("the pickaxe does not hurt a teammate", m.hp == 100.0)
	place(m, base + Vector3(0, 0, -6))
	place(e1, base + Vector3(2, 0, -6))
	var node := Node3D.new()
	game.fx_root.add_child(node)
	var pr := {"node": node, "owner": p, "damage": 100.0, "radius": 8.0, "kind": "rocket", "life": 1.0, "vel": Vector3.ZERO}
	game.projectiles.append(pr)
	game.explode(base + Vector3(1, 1, -6), pr)
	check("a teammate's rocket or grenade does no damage to the team", m.hp == 100.0, "%.0f" % m.hp)
	check("... but it hits an enemy next to the blast", e1.hp < 100.0, "%.0f" % e1.hp)
	standing(e1)
	var pr2 := {"node": null, "owner": p, "damage": 50.0, "radius": 9.0, "knock": 34.0, "struct": 0.0, "kind": "orb"}
	game.shock_burst(base + Vector3(1, 0, -6), pr2)
	check("the shockwave does not damage or launch a teammate", m.hp == 100.0 and not m.launched and m.state == Actor.State.GROUND)
	check("... but it hurts and launches an enemy", e1.hp < 100.0 and e1.launched, "%.0f" % e1.hp)
	standing(e1)
	e1.launched = false
	e1.state = Actor.State.GROUND
	p.global_position = base
	p.fire_cd = 0.0
	check("Ravage's Grasp cannot grab a teammate", not p.grasp_at(m) and m.stun_t <= 0.0 and p.yank_victim == null)
	check("... but it grabs an enemy", p.grasp_at(e1))
	await frames(30)
	standing(e1)
	p.yank_victim = null
	# ---------------------------------------------------------------- Solo: eliminated at 0 hp, never knocked
	var saved_pairs: Array = game.duo_teams
	game.duo_teams = []
	var saved_team := m.team
	m.team = 9999
	place(p, base)
	standing(p)
	p.hit(500.0, e1, false, Vector3.ZERO)
	check("Solo: the player is eliminated at 0 hp, not knocked", p.state == Actor.State.DEAD and not p.knocked and p.placement > 0, "placement %d" % p.placement)
	game.duo_teams = saved_pairs
	m.team = saved_team
	standing(p)
	e1.kills = 0
	# ---------------------------------------------------------------- knocked
	place(p, base)
	place(m, base + Vector3(8, 0, 0))
	equip(p, "assault_rifle")
	var loaded_before: int = p.slots[0].loaded
	var walk := Vector2.ZERO
	p.in_move = Vector2(0, 1)
	await frames(40)
	walk = Vector2(p.velocity.x, p.velocity.z)
	p.in_move = Vector2.ZERO
	await frames(20)
	place(p, base)
	p.hp = 10.0
	p.hit(50.0, e1, false, Vector3.ZERO)
	check("with a teammate up, 0 hp means knocked, not eliminated", p.knocked and p.alive() and p.hp == 0.0 and p.state == Actor.State.GROUND)
	check("knocked hp starts at 100", absf(p.knock_hp - 100.0) < 0.5, "%.1f" % p.knock_hp)
	check("the knock is in the kill feed", game.kill_feed.any(func(k: Dictionary) -> bool: return k.text.contains("was knocked by")))
	check("a knocked player still counts as in the match", game.alive_count() == 50 and game.teams_alive() == 49)
	place(p, base)
	p.in_move = Vector2(0, 1)
	await frames(60)
	var crawl := Vector2(p.velocity.x, p.velocity.z).length()
	check("a knocked player crawls at about 1.6 m/s, much slower than walking", crawl > 1.0 and crawl < 2.0 and walk.length() > 4.0, "crawl %.2f walk %.2f" % [crawl, walk.length()])
	await snap("duo_knocked")
	p.in_fire = true
	p.in_jump = true
	await frames(40)
	p.in_fire = false
	check("a knocked player cannot fire", p.slots[0].loaded == loaded_before)
	check("... or jump", p.velocity.y < 1.0 and p.is_on_floor())
	p.set_build("wall")
	check("... or build", p.build_piece == "")
	p.in_move = Vector2.ZERO
	check("... or interact (the interact key is swallowed)", game.try_revive(p, true))
	var k0: float = p.knock_hp
	await frames(600)
	check("the knocked hp bleeds out over time (about 33 per 10 s)", absf((k0 - p.knock_hp) - 33.3) < 3.0, "%.1f -> %.1f" % [k0, p.knock_hp])
	var k1: float = p.knock_hp
	p.hit(20.0, e1, false, Vector3.ZERO)
	check("enemy damage hits the knocked hp", absf(k1 - 20.0 - p.knock_hp) < 0.1 and p.knocked)
	p.hit(500.0, e1, false, Vector3.ZERO)
	check("an enemy can finish a knocked player", p.state == Actor.State.DEAD and e1.kills == 1, "kills %d" % e1.kills)
	check("... and the player's placement waits while the teammate is in", p.placement == 0)
	standing(p)
	# a full bleed-out eliminates
	place(p, base)
	p.hit(500.0, e1, false, Vector3.ZERO)
	check("knocked again", p.knocked)
	await frames(1860)
	check("bleeding out for 30 s eliminates the knocked player", p.state == Actor.State.DEAD)
	standing(p)
	# ---------------------------------------------------------------- revive
	place(p, base)
	place(m, base + Vector3(1.5, 0, 0))
	p.hit(500.0, e1, false, Vector3.ZERO)
	check("knocked for the revive test", p.knocked)
	await snap("duo_revive_pre")
	await hold_revive(m, 240)
	check("holding revive for 4 s is not enough", p.knocked and m.revive_t > 3.5 and m.revive_target == p, "%.2f s" % m.revive_t)
	await snap("duo_revive")
	await hold_revive(m, 70)
	check("holding revive for 5 s brings the player back at 30 hp and no shield", not p.knocked and absf(p.hp - 30.0) < 0.5 and p.shield == 0.0, "hp %.1f" % p.hp)
	check("... standing and able to move again", p.state == Actor.State.GROUND and p.knock_hp == 0.0)
	p.hit(500.0, e1, false, Vector3.ZERO)
	await hold_revive(m, 120)
	var rt: float = m.revive_t
	place(m, base + Vector3(6, 0, 0))
	check("moving away cancels the revive", not game.try_revive(m, true) and m.revive_t == 0.0 and rt > 1.5)
	place(m, base + Vector3(1.5, 0, 0))
	await hold_revive(m, 30)
	m.hit(5.0, e1, false, Vector3.ZERO)
	check("taking damage cancels the revive", m.revive_t == 0.0 and p.knocked)
	await hold_revive(m, 20)
	game.try_revive(m, false)
	check("letting go of the key cancels it", m.revive_t == 0.0)
	standing(m)
	# ---------------------------------------------------------------- both down: the team is out
	standing(p)
	standing(m)
	place(p, base)
	place(m, base + Vector3(3, 0, 0))
	e1.kills = 0
	p.hit(500.0, e1, false, Vector3.ZERO)
	check("first member knocked", p.knocked and m.up())
	m.hit(500.0, e1, false, Vector3.ZERO)
	check("the last one standing at 0 hp is eliminated, not knocked", m.state == Actor.State.DEAD)
	check("... and the knocked partner goes down with them", p.state == Actor.State.DEAD)
	check("both place the same, behind the 48 other teams", p.placement == m.placement and p.placement == 49, "%d / %d" % [p.placement, m.placement])
	check("both eliminations are credited to the killer", e1.kills == 2, "%d" % e1.kills)
	standing(p)
	standing(m)
	e1.kills = 0
	# ---------------------------------------------------------------- the bot teammate
	equip(m, "assault_rifle")
	equip(p, "assault_rifle")
	e1.state = Actor.State.BLIMP                        # out of everyone's sight: the bot has nobody to shoot at but us
	e2.state = Actor.State.BLIMP
	place(p, base, 0.0)
	place(m, base + Vector3(25, 0, 12))
	mb.set_physics_process(true)
	mb.has_goal = false
	await frames(900)
	var d: float = p.global_position.distance_to(m.global_position)
	check("the bot teammate follows the player", d < 12.0, "%.1f m" % d)
	check("... and does not shoot the player", p.hp == 100.0 and p.shield == 0.0 and mb.target != p, "hp %.0f" % p.hp)
	await snap("duo_teammate_hud")
	p.hit(500.0, e1, false, Vector3.ZERO)
	check("the player is knocked next to the bot", p.knocked)
	var t_rev := 0
	while p.knocked and t_rev < 1800:
		await frames(1)
		t_rev += 1
	check("the bot teammate revives the player", not p.knocked and p.hp >= 25.0 and p.hp <= 31.0, "after %.1f s, hp %.1f" % [t_rev / 60.0, p.hp])
	check("... in about 5 s of channelling plus the walk over", t_rev > 290 and t_rev < 1500, "%d frames" % t_rev)
	mb.set_physics_process(false)
	place(e1, base + Vector3(30, 0, 30))
	place(e2, base + Vector3(-30, 0, 30))
	standing(e1)
	standing(e2)
	# the bot goes down and the player revives it
	place(p, base)
	place(m, base + Vector3(1.2, 0, 0))
	m.hit(500.0, e1, false, Vector3.ZERO)
	check("the bot teammate can be knocked too", m.knocked)
	await hold_revive(p, 305)
	check("the player revives the bot", not m.knocked and absf(m.hp - 30.0) < 0.5)
	standing(m)
	# ---------------------------------------------------------------- team placement and the match end
	var before: int = game.teams_alive()
	for o in game.actors:
		if o != p and o != m and o != e1 and o != e2:
			o.die(null)
	check("placements count the remaining teams", before - game.teams_alive() == 46 and game.teams_alive() == 3, "%d teams left" % game.teams_alive())
	e2.die(e1)
	check("third place for the next team out", e2.placement == 3, "%d" % e2.placement)
	check("the match is still on with two teams left", not game.over)
	e1.die(p)
	await frames(5)
	check("the match ends when one team is left", game.over)
	check("the duo wins together and both place #1", game.winner != null and game.same_team(game.winner, p) and p.placement == 1 and m.placement == 1)
	check("the runner-up placed second", e1.placement == 2, "%d" % e1.placement)
	print("DUOTEST\n" + "\n".join(lines))
	print("DUOTEST %s  (%d checks, %d failed)" % ["OK" if fails == 0 else "FAILED", lines.size(), fails])
	get_tree().quit()
