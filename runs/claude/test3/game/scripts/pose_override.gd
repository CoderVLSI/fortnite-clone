## Runs after the animation clip each frame and bends chosen limbs towards target directions
## (skeleton space), with a weight per limb group, plus an offset on the hips.
## Used for poses the Mixamo clips do not have: aiming, crouching, sliding, swimming, gliding, mantling.
class_name PoseOverride
extends SkeletonModifier3D

const LEGS := ["LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg"]
const ARMS := ["LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm"]

var dirs := {}                   # bone name -> direction the bone should point (skeleton space)
var legs_w := 0.0
var arms_w := 0.0
var right_arm_only := false      # holding the pickaxe: only the right arm follows the override
var hips_offset := Vector3.ZERO
var hand_r := Vector3.ZERO       # right hand position after posing (skeleton space)
var hand_l := Vector3.ZERO
var idx := {}


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if idx.is_empty():
		for n in LEGS + ARMS + ["Hips", "RightHand", "LeftHand"]:
			idx[n] = sk.find_bone(n)
	var h: int = idx["Hips"]
	if h >= 0 and hips_offset != Vector3.ZERO:
		sk.set_bone_pose_position(h, sk.get_bone_pose_position(h) + hips_offset)
	if legs_w > 0.001:
		for n in LEGS:
			_aim(sk, n, legs_w)
	if arms_w > 0.001:
		for n in ARMS:
			if right_arm_only and n.begins_with("Left"):
				continue
			_aim(sk, n, arms_w)
	if idx["RightHand"] >= 0:
		hand_r = sk.get_bone_global_pose(idx["RightHand"]).origin
		hand_l = sk.get_bone_global_pose(idx["LeftHand"]).origin


func _aim(sk: Skeleton3D, bone: String, w: float) -> void:
	var b: int = idx.get(bone, -1)
	if b < 0 or not dirs.has(bone):
		return
	var want: Vector3 = dirs[bone]
	if want.length() < 0.01:
		return
	var g := sk.get_bone_global_pose(b)
	var cur := g.basis.y.normalized()
	var q := Quaternion(cur, want.normalized())
	var new_basis := Basis(q) * g.basis
	var p := sk.get_bone_parent(b)
	var pg := sk.get_bone_global_pose(p) if p >= 0 else Transform3D.IDENTITY
	var local := (pg.basis.orthonormalized().inverse() * new_basis.orthonormalized()).get_rotation_quaternion()
	sk.set_bone_pose_rotation(b, sk.get_bone_pose_rotation(b).slerp(local, clampf(w, 0.0, 1.0)))
