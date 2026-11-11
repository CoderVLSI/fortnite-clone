## Writes the bone map that retargets Mixamo skeletons onto Godot's humanoid profile at import.
##   godot --headless --path <project> -s scripts/make_bonemap.gd
extends SceneTree

func _init() -> void:
	var bm := BoneMap.new()
	bm.profile = SkeletonProfileHumanoid.new()
	var m := {"Hips": "Hips", "Spine": "Spine", "Chest": "Spine1", "UpperChest": "Spine2", "Neck": "Neck", "Head": "Head"}
	for side in ["Left", "Right"]:
		m[side + "Shoulder"] = side + "Shoulder"
		m[side + "UpperArm"] = side + "Arm"
		m[side + "LowerArm"] = side + "ForeArm"
		m[side + "Hand"] = side + "Hand"
		m[side + "UpperLeg"] = side + "UpLeg"
		m[side + "LowerLeg"] = side + "Leg"
		m[side + "Foot"] = side + "Foot"
		m[side + "Toes"] = side + "ToeBase"
		var fingers := {"Thumb": ["Metacarpal", "Proximal", "Distal"], "Index": ["Proximal", "Intermediate", "Distal"], "Middle": ["Proximal", "Intermediate", "Distal"],
				"Ring": ["Proximal", "Intermediate", "Distal"], "Little": ["Proximal", "Intermediate", "Distal"]}
		for f in fingers:
			var mix: String = "Pinky" if f == "Little" else f
			for i in 3:
				m[side + f + fingers[f][i]] = "%sHand%s%d" % [side, mix, i + 1]
	for k in m:
		bm.set_skeleton_bone_name(k, "mixamorig_" + m[k])
	print("SAVE ", ResourceSaver.save(bm, "res://assets/characters/mixamo_bonemap.tres"), " mapped ", m.size())
	quit()
