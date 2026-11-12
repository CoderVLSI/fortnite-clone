## A character standing at a point of interest who can be talked to and hired for gold. Until hired they stay put,
## turn to face a player who comes close and wave now and then; nobody can hurt them and the bots leave them alone.
## Hiring (game.hire_npc) swaps this brain for a bot brain in ally mode.
extends Node

var game: Node
var a: Actor
var info: Dictionary                      # name, line, cost
var home := Vector3.ZERO
var wave_t := 4.0
var plate: Label3D


func setup(g: Node, actor: Actor, data: Dictionary) -> void:
	game = g
	a = actor
	info = data
	home = actor.global_position
	plate = Label3D.new()
	plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	plate.font_size = 34
	plate.outline_size = 10
	plate.modulate = Color(1.0, 0.85, 0.4)
	plate.no_depth_test = true
	plate.position = Vector3(0, 2.25, 0)
	plate.text = "%s\nfor hire" % data.name
	a.add_child(plate)


func _physics_process(delta: float) -> void:
	if not a.alive():
		return
	a.in_fire = false
	a.in_move = Vector2.ZERO
	if a.global_position.distance_to(home) > 1.5:                 # stay at the post
		var to := home - a.global_position
		a.aim_yaw = atan2(-to.x, -to.z)
		a.in_move = Vector2(0, 1)
		return
	var p: Actor = game.player
	var d := a.global_position.distance_to(p.global_position)
	plate.visible = d < 45.0
	if d < 10.0 and p.alive():
		var to2 := p.global_position - a.global_position
		a.aim_yaw = lerp_angle(a.aim_yaw, atan2(-to2.x, -to2.z), clampf(delta * 5.0, 0.0, 1.0))
		wave_t -= delta
		if wave_t <= 0.0:
			wave_t = game.rng.randf_range(6.0, 10.0)
			a.start_emote("wave")
