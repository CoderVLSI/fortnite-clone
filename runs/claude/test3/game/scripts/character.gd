## The player/bot body: an original blocky figure built and animated in code.
## It faces -Z. Pose is driven from the owning Actor every frame.
class_name Character
extends Node3D

var hips: Node3D
var torso: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var fore_l: Node3D
var fore_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var shin_l: Node3D
var shin_r: Node3D
var holder: Node3D
var glider: Node3D
var held: Node3D
var held_id := ""
var phase := 0.0
var swing := 0.0
var mats := {}


func _mat(c: Color) -> StandardMaterial3D:
	var k := c.to_html()
	if not mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.75
		mats[k] = m
	return mats[k]


func _box(parent: Node3D, size: Vector3, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = _mat(c)
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)
	return mi


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func build(outfit: Color, accent: Color, skin: Color) -> void:
	var dark := outfit.darkened(0.45)
	hips = _pivot(self, Vector3(0, 0.95, 0))
	_box(hips, Vector3(0.42, 0.22, 0.26), Vector3(0, 0, 0), dark)
	torso = _pivot(hips, Vector3(0, 0.1, 0))
	_box(torso, Vector3(0.5, 0.5, 0.3), Vector3(0, 0.27, 0), outfit)
	_box(torso, Vector3(0.52, 0.1, 0.32), Vector3(0, 0.08, 0), accent)                 # belt
	_box(torso, Vector3(0.34, 0.4, 0.16), Vector3(0, 0.3, 0.22), dark)                 # backpack
	head = _pivot(torso, Vector3(0, 0.56, 0))
	_box(head, Vector3(0.3, 0.3, 0.3), Vector3(0, 0.17, 0), skin)
	_box(head, Vector3(0.34, 0.13, 0.34), Vector3(0, 0.31, 0), accent)                 # cap
	_box(head, Vector3(0.3, 0.04, 0.16), Vector3(0, 0.26, -0.22), accent)              # cap peak
	_box(head, Vector3(0.22, 0.05, 0.02), Vector3(0, 0.19, -0.155), Color(0.1, 0.1, 0.12))  # visor
	arm_l = _pivot(torso, Vector3(-0.32, 0.46, 0))
	arm_r = _pivot(torso, Vector3(0.32, 0.46, 0))
	for a in [arm_l, arm_r]:
		_box(a, Vector3(0.15, 0.32, 0.16), Vector3(0, -0.14, 0), outfit)
	fore_l = _pivot(arm_l, Vector3(0, -0.3, 0))
	fore_r = _pivot(arm_r, Vector3(0, -0.3, 0))
	for f in [fore_l, fore_r]:
		_box(f, Vector3(0.13, 0.28, 0.14), Vector3(0, -0.13, 0), skin)
		_box(f, Vector3(0.15, 0.1, 0.16), Vector3(0, -0.3, 0), dark)                    # glove
	leg_l = _pivot(hips, Vector3(-0.12, -0.08, 0))
	leg_r = _pivot(hips, Vector3(0.12, -0.08, 0))
	for l in [leg_l, leg_r]:
		_box(l, Vector3(0.19, 0.42, 0.21), Vector3(0, -0.2, 0), dark)
	shin_l = _pivot(leg_l, Vector3(0, -0.42, 0))
	shin_r = _pivot(leg_r, Vector3(0, -0.42, 0))
	for s in [shin_l, shin_r]:
		_box(s, Vector3(0.17, 0.36, 0.19), Vector3(0, -0.18, 0), dark)
		_box(s, Vector3(0.19, 0.1, 0.3), Vector3(0, -0.4, -0.05), accent)               # boot
	holder = _pivot(torso, Vector3(0.2, 0.3, -0.42))
	holder.rotation.y = PI                                                               # assets point +Z; the body faces -Z
	# glider: a simple striped wing, shown while gliding
	glider = _pivot(self, Vector3(0, 2.9, 0.1))
	for i in 5:
		var w := _box(glider, Vector3(0.7, 0.07, 1.5 - absf(i - 2) * 0.2), Vector3((i - 2) * 0.7, -absf(i - 2) * 0.12, 0), accent if i % 2 == 0 else Color(0.93, 0.9, 0.82))
		w.rotation.z = -(i - 2) * 0.16
	for s in [-1, 1]:
		var strut := _box(glider, Vector3(0.04, 1.5, 0.04), Vector3(s * 0.5, -0.8, 0), Color(0.25, 0.25, 0.28))
		strut.rotation.z = s * 0.3
	glider.visible = false


func hold(id: String) -> void:
	if id == held_id:
		return
	held_id = id
	if held:
		held.queue_free()
		held = null
	if id == "":
		return
	held = Models.make(id)
	holder.add_child(held)
	if id == "pickaxe":
		held.position = Vector3(0, -0.1, 0.1)
		held.rotation = Vector3(deg_to_rad(-25), 0, 0)
	elif id == "medkit" or id == "shield_potion" or id == "grenade":
		held.position = Vector3(0, -0.12, 0.1)


func animate(delta: float, a: Actor) -> void:
	var st := a.state
	visible = st != Actor.State.BLIMP and st != Actor.State.DEAD
	glider.visible = st == Actor.State.GLIDE
	var hv := Vector2(a.velocity.x, a.velocity.z).length()
	var armed := held_id != "" and held_id != "pickaxe"
	swing = maxf(swing - delta * 3.2, 0.0)
	var tl := 0.0; var tr := 0.0; var kl := 0.0; var kr := 0.0
	var al := Vector3.ZERO; var ar := Vector3.ZERO; var el := 0.0; var er := 0.0
	var lean := 0.0
	var bob := 0.0
	if st == Actor.State.SKYDIVE:
		lean = deg_to_rad(-78 if a.in_dive else -62)
		al = Vector3(deg_to_rad(20), 0, deg_to_rad(-70)); ar = Vector3(deg_to_rad(20), 0, deg_to_rad(70))
		tl = deg_to_rad(-12); tr = deg_to_rad(-18); kl = deg_to_rad(35); kr = deg_to_rad(45)
	elif st == Actor.State.GLIDE:
		al = Vector3(deg_to_rad(165), 0, deg_to_rad(-12)); ar = Vector3(deg_to_rad(165), 0, deg_to_rad(12))
		tl = deg_to_rad(12); tr = deg_to_rad(20); kl = deg_to_rad(25); kr = deg_to_rad(35)
	else:
		if not a.is_on_floor() and st == Actor.State.GROUND:
			tl = deg_to_rad(35); tr = deg_to_rad(-15); kl = deg_to_rad(50); kr = deg_to_rad(25)
			al = Vector3(deg_to_rad(-40), 0, deg_to_rad(-15)); ar = Vector3(deg_to_rad(30), 0, deg_to_rad(15))
		elif hv > 0.4:
			phase += delta * (5.5 + hv * 1.25)
			var amp := clampf(hv / 7.0, 0.35, 1.0)
			tl = sin(phase) * 0.85 * amp; tr = -sin(phase) * 0.85 * amp
			kl = maxf(0.0, -cos(phase)) * 1.1 * amp; kr = maxf(0.0, cos(phase)) * 1.1 * amp
			al = Vector3(-sin(phase) * 0.8 * amp, 0, -0.08); ar = Vector3(sin(phase) * 0.8 * amp, 0, 0.08)
			el = -0.5; er = -0.5
			bob = absf(sin(phase)) * 0.05
			lean = deg_to_rad(-9) * amp
		else:
			phase += delta * 1.6
			al = Vector3(0, 0, -0.07); ar = Vector3(0, 0, 0.07)
			bob = sin(phase) * 0.008
		if a.using > 0.0:
			al = Vector3(deg_to_rad(95), 0, deg_to_rad(20)); ar = Vector3(deg_to_rad(95), 0, deg_to_rad(-20)); el = deg_to_rad(-70); er = deg_to_rad(-70)
		elif armed:                                   # both hands on the weapon
			var p := a.aim_pitch
			ar = Vector3(deg_to_rad(72) + p, 0, deg_to_rad(-8)); er = deg_to_rad(-55)
			al = Vector3(deg_to_rad(80) + p, 0, deg_to_rad(32)); el = deg_to_rad(-40)
		elif held_id == "pickaxe":
			ar = Vector3(deg_to_rad(60) + sin(swing * PI) * 1.6, 0, 0); er = deg_to_rad(-60)
	hips.position.y = 0.95 + bob
	rotation.x = lerp_angle(rotation.x, lean, clampf(delta * 8.0, 0.0, 1.0))
	torso.rotation.x = clampf(a.aim_pitch * 0.45, -0.5, 0.5) if (armed and st == Actor.State.GROUND) else 0.0
	head.rotation.x = clampf(a.aim_pitch * 0.4, -0.5, 0.5)
	var k := clampf(delta * 14.0, 0.0, 1.0)
	arm_l.rotation = arm_l.rotation.lerp(al, k); arm_r.rotation = arm_r.rotation.lerp(ar, k)
	fore_l.rotation.x = lerpf(fore_l.rotation.x, el, k); fore_r.rotation.x = lerpf(fore_r.rotation.x, er, k)
	leg_l.rotation.x = lerpf(leg_l.rotation.x, tl, k); leg_r.rotation.x = lerpf(leg_r.rotation.x, tr, k)
	shin_l.rotation.x = lerpf(shin_l.rotation.x, -kl, k); shin_r.rotation.x = lerpf(shin_r.rotation.x, -kr, k)
	if held:
		holder.rotation.x = -a.aim_pitch * 0.5 if armed else 0.0
