## The storm: five phases, each a wait and then a shrink to a new circle that lies inside the previous one.
## Outside the circle actors take damage that ignores shields and grows from 1 to 10 HP per second.
class_name Storm
extends Node3D

## [wait seconds, shrink seconds, radius after the shrink, damage per second]
const PHASES := [[45.0, 35.0, 125.0, 1.0], [30.0, 30.0, 75.0, 2.0], [25.0, 25.0, 40.0, 5.0], [20.0, 20.0, 18.0, 8.0], [15.0, 20.0, 0.0, 10.0]]
const START_RADIUS := 300.0

var game: Node
var phase := 0
var shrinking := false
var timer := 0.0
var center := Vector2.ZERO
var radius := START_RADIUS
var from_center := Vector2.ZERO
var from_radius := START_RADIUS
var next_center := Vector2.ZERO
var next_radius := START_RADIUS
var active := false
var done := false
var tick := 0.0
var wall: MeshInstance3D
var wall_mat: ShaderMaterial


func setup(g: Node) -> void:
	game = g
	wall = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 96
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	wall.mesh = cyl
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
void fragment() {
	float bands = sin(UV.x * 240.0 + TIME * 1.5 + sin(UV.y * 9.0 + TIME) * 2.0) * 0.5 + 0.5;
	float rise = fract(UV.y * 6.0 + TIME * 0.35 + sin(UV.x * 60.0) * 0.2);
	vec3 col = mix(vec3(0.42, 0.12, 0.78), vec3(0.78, 0.35, 1.0), bands * 0.6 + rise * 0.4);
	ALBEDO = col;
	ALPHA = (0.16 + 0.16 * bands + 0.1 * rise) * mix(1.0, 0.25, smoothstep(0.35, 1.0, 1.0 - UV.y));   // fades towards the top
}"""
	wall_mat = ShaderMaterial.new()
	wall_mat.shader = sh
	wall.material_override = wall_mat
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wall)
	_pick_next()
	_update_wall()


func _pick_next() -> void:
	from_center = center
	from_radius = radius
	next_radius = PHASES[phase][2]
	# the new circle lies inside the current one, and its centre stays on land
	for i in 60:
		var a = game.rng.randf() * TAU
		var d = game.rng.randf() * maxf(radius - next_radius, 0.0) * 0.9
		var c = center + Vector2(cos(a), sin(a)) * d
		if game.terrain.height(c.x, c.y) > 2.0 or i == 59:
			next_center = c
			break


func start() -> void:
	active = true
	timer = PHASES[0][0]


func time_left() -> float:
	return maxf(timer, 0.0)


func damage_now() -> float:
	return PHASES[mini(phase, PHASES.size() - 1)][3]


func outside(p: Vector3) -> float:
	## Metres outside the current circle (negative inside).
	return Vector2(p.x, p.z).distance_to(center) - radius


func outside_next(p: Vector3) -> float:
	return Vector2(p.x, p.z).distance_to(next_center) - next_radius


func _physics_process(delta: float) -> void:
	if not active:
		return
	if not done:
		timer -= delta
		if shrinking:
			var total: float = PHASES[phase][1]
			var k := clampf(1.0 - timer / total, 0.0, 1.0)
			center = from_center.lerp(next_center, k)
			radius = lerpf(from_radius, next_radius, k)
			if timer <= 0.0:
				shrinking = false
				phase += 1
				if phase >= PHASES.size():
					done = true
					phase = PHASES.size() - 1
				else:
					timer = PHASES[phase][0]
					_pick_next()
		elif timer <= 0.0:
			shrinking = true
			timer = PHASES[phase][1]
			game.announce("The storm is closing in")
	tick += delta
	if tick >= 1.0:
		tick -= 1.0
		for a in game.actors:
			if a.alive() and a.state != Actor.State.BLIMP and outside(a.global_position) > 0.0:
				a.hit(damage_now(), null, true, a.global_position)
				a.storm_time += 1.0
	_update_wall()


func _update_wall() -> void:
	wall.position = Vector3(center.x, 60.0, center.y)
	wall.scale = Vector3(maxf(radius, 0.5), 260.0, maxf(radius, 0.5))
