## A MultiMeshInstance3D that keeps its instance transforms in the scene file and
## builds the MultiMesh when it enters the tree (GPU instancing for vegetation and crops).
extends MultiMeshInstance3D

@export var mesh: Mesh
@export var transforms: PackedFloat32Array      # 12 floats per instance: basis rows with the origin in the 4th column


func _ready() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size() / 12
	mm.buffer = transforms
	multimesh = mm


func instance_transform(i: int) -> Transform3D:
	var o := i * 12
	var t := transforms
	return Transform3D(Vector3(t[o], t[o + 4], t[o + 8]), Vector3(t[o + 1], t[o + 5], t[o + 9]), Vector3(t[o + 2], t[o + 6], t[o + 10]), Vector3(t[o + 3], t[o + 7], t[o + 11]))
