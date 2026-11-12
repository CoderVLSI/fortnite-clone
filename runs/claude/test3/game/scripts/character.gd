## The player/bot body: the Mixamo "Soldier" from the three.js examples, retargeted to Godot's humanoid
## skeleton at import. Idle, walk and run come from Mixamo clips (the Soldier's own, plus Xbot's and
## Michelle's for extra moves); poses the clips do not have are added on top by PoseOverride.
## It faces -Z. Pose is driven from the owning Actor every frame.
class_name Character
extends Node3D

const SOLDIER := preload("res://assets/characters/Soldier.glb")
## Bodies a skin can use. The Xbot robot keeps its own idle / walk / run (the Soldier's clips do not sit well on
## its proportions); it is also built facing +Z, so it is turned round.
const BODIES := {
	"Soldier": {"scene": "res://assets/characters/Soldier.glb", "clips": {}, "turn": 0.0, "tint": 0.5},
	"Xbot": {"scene": "res://assets/characters/Xbot.glb", "clips": {"Idle": "idle", "Walk": "walk", "Run": "run"}, "turn": PI, "tint": 0.85},
}
var clip_map := {}
const HIP_SCALE := 1.12                  # the Soldier's legs compared with the old blocky body
## Emotes for the emote wheel: Mixamo clips (Michelle's samba, Xbot's nod and head shake) and a wave
## done with the pose override. length 0 = loops until cancelled.
const EMOTES := {
	"samba": {"name": "Samba", "clip": "x/Michelle_SambaDance", "length": 0.0},
	"nod": {"name": "Nod", "clip": "x/Xbot_agree", "length": 1.8},
	"no": {"name": "No way", "clip": "x/Xbot_headShake", "length": 2.5},
	"wave": {"name": "Wave", "clip": "Idle", "length": 2.4},
}

static var _lib: AnimationLibrary
static var _tints := {}

var rig: Node3D
var skel: Skeleton3D
var anim: AnimationPlayer
var pose: PoseOverride
var holder: Node3D
var glider: Node3D
var held: Node3D
var held_id := ""
var phase := 0.0
var swing := 0.0
var clip := ""
var legs_w := 0.0
var arms_w := 0.0
var dirs := {}
var hips_off := Vector3.ZERO
var mats := {}


static func library() -> AnimationLibrary:
	## Extra clips from the other two Mixamo characters, shared by every body.
	if _lib == null:
		_lib = AnimationLibrary.new()
		for f in ["Xbot", "Michelle"]:
			var inst: Node = (load("res://assets/characters/%s.glb" % f) as PackedScene).instantiate()
			var ap: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
			for an in ap.get_animation_list():
				var a: Animation = ap.get_animation(an)
				if an in ["idle", "walk", "run", "SambaDance"]:
					a.loop_mode = Animation.LOOP_LINEAR
				_lib.add_animation(StringName(f + "_" + an), a)
			inst.free()
	return _lib


func build(outfit: Color, accent: Color, _skin: Color, body_id := "Soldier") -> void:
	var b: Dictionary = BODIES.get(body_id, BODIES.Soldier)
	rig = (SOLDIER if body_id == "Soldier" else load(b.scene) as PackedScene).instantiate()
	add_child(rig)
	rig.rotation.y = b.turn
	clip_map = b.clips
	skel = rig.find_children("*", "Skeleton3D", true, false)[0]
	anim = rig.find_children("*", "AnimationPlayer", true, false)[0]
	anim.add_animation_library("x", library())
	for n in ["Idle", "Walk", "Run"]:
		anim.get_animation(clip_map.get(n, n)).loop_mode = Animation.LOOP_LINEAR
	# each player gets a tint of their outfit colour
	var key := body_id + outfit.to_html()
	for mi in rig.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var k := "%s_%s_%d" % [key, mi.name, s]
			if not _tints.has(k):
				var base: Material = mi.get_active_material(s)
				var m: Material = base.duplicate() if base else StandardMaterial3D.new()
				if m is StandardMaterial3D:
					var shade: Color = Color.WHITE.lerp(outfit, b.tint)
					if body_id == "Xbot" and s % 2 == 1:
						shade = accent.lightened(0.25)                 # the robot's joints take the accent colour
					(m as StandardMaterial3D).albedo_color = shade
				_tints[k] = m
			mi.set_surface_override_material(s, _tints[k])
	pose = PoseOverride.new()
	skel.add_child(pose)
	holder = Node3D.new()
	add_child(holder)
	_build_glider(accent)
	_play("Idle", 1.0)
	hold("pickaxe")


func _mat(c: Color) -> StandardMaterial3D:
	var k := c.to_html()
	if not mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.75
		mats[k] = m
	return mats[k]


func _build_glider(accent: Color) -> void:
	glider = Node3D.new()
	glider.position = Vector3(0, 2.95, 0.1)
	add_child(glider)
	for i in 5:
		var w := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.7, 0.07, 1.5 - absf(i - 2) * 0.2)
		bm.material = _mat(accent if i % 2 == 0 else Color(0.93, 0.9, 0.82))
		w.mesh = bm
		w.position = Vector3((i - 2) * 0.7, -absf(i - 2) * 0.12, 0)
		w.rotation.z = -(i - 2) * 0.16
		glider.add_child(w)
	for s in [-1, 1]:
		var strut := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(0.04, 1.3, 0.04)
		sb.material = _mat(Color(0.25, 0.25, 0.28))
		strut.mesh = sb
		strut.position = Vector3(s * 0.45, -0.7, 0)
		strut.rotation.z = s * 0.3
		glider.add_child(strut)
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
		held.position = Vector3(0, -0.15, 0)
	elif id == "medkit" or id == "shield_potion" or id == "grenade":
		held.position = Vector3(0, 0.0, 0.08)


func _play(name: String, speed: float) -> void:
	name = clip_map.get(name, name)
	if name != clip:
		clip = name
		anim.play(name, 0.22)
	anim.speed_scale = speed


static func _down(t: float) -> Vector3:
	## A limb swung forward by t radians from hanging straight down (the body faces -Z).
	return Vector3(0, -cos(t), -sin(t))


const FAR_HIDE := 260.0                 # beyond this nobody is drawn at all (50 players on a phone)
const FAR_LOD := 90.0                   # beyond this the animation steps every 4th frame, without the pose tweaks
var lod_far := false
var lod_acc := 0.0
var lod_n := 0


func _lod(delta: float) -> int:
	## 0: too far to draw, 1: far (cheap animation), 2: close enough to animate fully.
	var cam := get_viewport().get_camera_3d()
	var d := cam.global_position.distance_to(global_position) if cam else 0.0
	if d > FAR_HIDE:
		visible = false
		return 0
	var far := d > FAR_LOD
	if far != lod_far:
		lod_far = far
		anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL if far else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		pose.active = not far
		lod_acc = 0.0
	if far:
		lod_acc += delta
		lod_n += 1
		if lod_n % 4 == 0:
			anim.advance(lod_acc)
			lod_acc = 0.0
	return 1 if far else 2


func animate(delta: float, a: Actor) -> void:
	var st := a.state
	visible = st != Actor.State.BLIMP and st != Actor.State.DEAD
	glider.visible = st == Actor.State.GLIDE
	if not visible:
		return
	var detail := 2 if a.is_player else _lod(delta)
	if detail == 0:
		return
	var hv := Vector2(a.velocity.x, a.velocity.z).length()
	var armed := held_id != "" and held_id != "pickaxe"
	swing = maxf(swing - delta * 3.2, 0.0)
	# limb angles in the same terms as the old procedural body; turned into directions below
	var tl := 0.0; var tr := 0.0; var kl := 0.0; var kr := 0.0
	var al := Vector3.ZERO; var ar := Vector3.ZERO; var el := 0.0; var er := 0.0
	var lean := 0.0
	var hip_y := 0.95
	var want_legs := 0.0
	var want_arms := 0.0
	var arm_mode := ""
	var right_only := false
	var c := "Idle"
	var speed := 1.0
	if a.emote != "":
		var em: Dictionary = EMOTES[a.emote]
		_play(em.clip, 1.0)
		var wave: bool = a.emote == "wave"
		var wav := sin(a.emote_t * 9.0)
		dirs["RightUpperArm"] = Vector3(0.55, 0.85, -0.15).normalized()
		dirs["RightLowerArm"] = Vector3(0.35 * wav, 1.0, -0.2).normalized()
		legs_w = 0.0
		arms_w = move_toward(arms_w, 1.0 if wave else 0.0, delta * 8.0)
		hips_off = hips_off.lerp(Vector3.ZERO, clampf(delta * 14.0, 0.0, 1.0))
		pose.dirs = dirs
		pose.legs_w = 0.0
		pose.arms_w = arms_w
		pose.right_arm_only = true
		pose.hips_offset = hips_off
		rotation.x = lerp_angle(rotation.x, 0.0, clampf(delta * 8.0, 0.0, 1.0))
		return
	if st == Actor.State.SKYDIVE:
		lean = deg_to_rad(-78 if a.in_dive else -62)
		al = Vector3(deg_to_rad(20), 0, deg_to_rad(-70)); ar = Vector3(deg_to_rad(20), 0, deg_to_rad(70))
		tl = deg_to_rad(-12); tr = deg_to_rad(-18); kl = deg_to_rad(35); kr = deg_to_rad(45)
		want_legs = 1.0; want_arms = 1.0
	elif st == Actor.State.GLIDE:
		al = Vector3(deg_to_rad(165), 0, deg_to_rad(-12)); ar = Vector3(deg_to_rad(165), 0, deg_to_rad(12))
		tl = deg_to_rad(12); tr = deg_to_rad(20); kl = deg_to_rad(25); kr = deg_to_rad(35)
		want_legs = 1.0; want_arms = 1.0
	elif a.mantle_t >= 0.0:
		al = Vector3(deg_to_rad(155), 0, deg_to_rad(-12)); ar = Vector3(deg_to_rad(155), 0, deg_to_rad(12)); el = -0.4; er = -0.4
		tl = 1.0; tr = 0.25; kl = 1.5; kr = 0.5; lean = -0.25
		want_legs = 1.0; want_arms = 1.0
	elif st == Actor.State.SWIM:
		if hv > 0.8:
			phase += delta * 3.4
			lean = -0.75
			hip_y = 1.2
			al = Vector3(1.6 + sin(phase) * 1.5, 0, -0.15); ar = Vector3(1.6 - sin(phase) * 1.5, 0, 0.15)
			tl = sin(phase * 2.0) * 0.3; tr = -tl; kl = 0.25; kr = 0.25
		else:
			phase += delta * 2.6
			al = Vector3(0.5, 0, -1.1 + sin(phase) * 0.35); ar = Vector3(0.5, 0, 1.1 - sin(phase) * 0.35); el = -0.3; er = -0.3
			tl = sin(phase) * 0.5; tr = -sin(phase) * 0.5; kl = maxf(0.0, cos(phase)) * 0.9; kr = maxf(0.0, -cos(phase)) * 0.9
		want_legs = 1.0; want_arms = 1.0
	elif a.sliding:
		hip_y = 0.5
		lean = 0.3
		tl = 1.35; kl = 0.1; tr = 0.4; kr = 1.75
		al = Vector3(0.6, 0, -1.0); ar = Vector3(0.9, 0, 1.0)
		want_legs = 1.0; want_arms = 1.0
	elif not (a.is_on_floor() or a.get_meta("force_floor", false)):
		tl = deg_to_rad(35); tr = deg_to_rad(-15); kl = deg_to_rad(50); kr = deg_to_rad(25)
		al = Vector3(deg_to_rad(-40), 0, deg_to_rad(-15)); ar = Vector3(deg_to_rad(30), 0, deg_to_rad(15))
		want_legs = 1.0; want_arms = 1.0
	else:
		if a.crouched:
			c = "Walk" if hv > 0.4 else "Idle"
			speed = clampf(hv / 1.4, 0.6, 2.2) if hv > 0.4 else 1.0
			if hv > 0.4:
				phase += delta * (5.5 + hv * 1.25)
			else:
				phase += delta * 1.6
			var amp := clampf(hv / 7.0, 0.0, 1.0) if hv > 0.4 else 0.0
			tl = 1.05 + sin(phase) * 0.85 * amp * 0.4; tr = 1.05 - sin(phase) * 0.85 * amp * 0.4
			kl = 1.7 + maxf(0.0, -cos(phase)) * 1.1 * amp * 0.3; kr = 1.7 + maxf(0.0, cos(phase)) * 1.1 * amp * 0.3
			hip_y = 0.62
			lean = -0.12
			want_legs = 1.0
		elif hv > 3.6:
			c = "Run"
			speed = clampf(hv / 5.2, 0.6, 1.8)
		elif hv > 0.4:
			c = "Walk"
			speed = clampf(hv / 1.5, 0.6, 2.4)
		if a.using > 0.0:
			arm_mode = "use"
		elif armed:
			arm_mode = "aim"
		elif held_id == "pickaxe" and swing > 0.0:
			arm_mode = "swing"
			right_only = true
	_play(c, speed)
	if detail < 2:
		return                                     # far away: the clip alone, no limb overrides
	# directions for the overridden limbs
	var f := Vector3(0, sin(a.aim_pitch), -cos(a.aim_pitch))           # aim forward, with pitch
	var dn := Vector3(0, -cos(a.aim_pitch), -sin(a.aim_pitch))
	var r := Vector3.RIGHT
	var d := {}
	d["LeftUpperLeg"] = _down(tl)
	d["LeftLowerLeg"] = _down(tl - kl)
	d["RightUpperLeg"] = _down(tr)
	d["RightLowerLeg"] = _down(tr - kr)
	var bl := Basis.from_euler(al)
	var br := Basis.from_euler(ar)
	d["LeftUpperArm"] = bl * Vector3.DOWN
	d["LeftLowerArm"] = bl * Basis(Vector3.RIGHT, el) * Vector3.DOWN
	d["RightUpperArm"] = br * Vector3.DOWN
	d["RightLowerArm"] = br * Basis(Vector3.RIGHT, er) * Vector3.DOWN
	match arm_mode:
		"aim":                                  # rifle held at the shoulder, left hand under the barrel
			d["RightUpperArm"] = (f * 0.35 + dn * 0.85 + r * 0.3).normalized()
			d["RightLowerArm"] = (f * 1.0 - r * 0.3 + dn * 0.15).normalized()
			d["LeftUpperArm"] = (f * 0.75 + dn * 0.6 + r * 0.25).normalized()
			d["LeftLowerArm"] = (f * 0.85 + r * 0.55).normalized()
			want_arms = 1.0
		"use":
			d["LeftUpperArm"] = (f * 0.8 + dn * 0.55 - r * 0.15).normalized()
			d["RightUpperArm"] = (f * 0.8 + dn * 0.55 + r * 0.15).normalized()
			d["LeftLowerArm"] = (Vector3.UP * 0.7 + f * 0.4 + r * 0.45).normalized()
			d["RightLowerArm"] = (Vector3.UP * 0.7 + f * 0.4 - r * 0.45).normalized()
			want_arms = 1.0
		"swing":                                # chop: from overhead down to the front
			var k := sin(swing * PI)
			d["RightUpperArm"] = (Vector3.UP * (0.2 + k * 0.9) + f * (1.0 - k * 0.3) + r * 0.2).normalized()
			d["RightLowerArm"] = (f * 1.0 + Vector3.UP * k * 0.6).normalized()
			want_arms = 1.0
	# smooth the targets and weights, then hand them to the modifier
	var kk := clampf(delta * 14.0, 0.0, 1.0)
	for b in d:
		var cur: Vector3 = dirs.get(b, d[b])
		dirs[b] = cur.slerp(d[b], kk) if cur.length() > 0.01 and cur.angle_to(d[b]) > 0.001 else d[b]
	legs_w = move_toward(legs_w, want_legs, delta * 7.0)
	arms_w = move_toward(arms_w, want_arms, delta * 9.0)
	hips_off = hips_off.lerp(Vector3(0, (hip_y - 0.95) * HIP_SCALE, 0), kk)
	pose.dirs = dirs
	pose.legs_w = legs_w
	pose.arms_w = arms_w
	pose.right_arm_only = right_only and want_legs < 0.5
	pose.hips_offset = hips_off
	rotation.x = lerp_angle(rotation.x, lean, clampf(delta * 8.0, 0.0, 1.0))
	# the held item sits in the right hand and points where the player aims
	if held and pose.hand_r != Vector3.ZERO:
		var hand_w := skel.global_transform * pose.hand_r
		var aim_w := (global_transform.basis * f).normalized()
		var up := global_transform.basis.y
		var bas := Basis.looking_at(-aim_w, up)
		if held_id == "pickaxe":
			bas = bas * Basis(Vector3.RIGHT, -0.5 - sin(swing * PI) * 1.4)
		elif not armed:
			bas = bas * Basis(Vector3.RIGHT, -0.6)
		holder.global_transform = Transform3D(bas, hand_w)
