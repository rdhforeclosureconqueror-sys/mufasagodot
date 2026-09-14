extends SceneTree

const SOURCE_SCENE := "res://assets/characters/pocketpt/source/rashad1.glb"
const OUTPUT_PATH := "res://resources/pocketpt/canonical_avatar_rest_profile.json"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(SOURCE_SCENE) as PackedScene
	if packed == null:
		return _fail("SOURCE_SCENE_MISSING")
	var instance := packed.instantiate() as Node3D
	if instance == null:
		return _fail("SOURCE_SCENE_INSTANTIATE_FAILED")
	get_root().add_child(instance)
	var skeletons := instance.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return _fail("SOURCE_SKELETON_MISSING")
	var skeleton := skeletons[0] as Skeleton3D
	var bones := {}
	for bone_index in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(bone_index)
		var parent_index := skeleton.get_bone_parent(bone_index)
		var parent_name := skeleton.get_bone_name(parent_index) if parent_index >= 0 else ""
		var local_q := skeleton.get_bone_rest(bone_index).basis.get_rotation_quaternion().normalized()
		var global_q := skeleton.get_bone_global_rest(bone_index).basis.get_rotation_quaternion().normalized()
		bones[bone_name] = {
			"localQuaternion": [local_q.x, local_q.y, local_q.z, local_q.w],
			"globalQuaternion": [global_q.x, global_q.y, global_q.z, global_q.w],
			"parentName": parent_name
		}
	var payload := {
		"version": 2,
		"basisSpace": "BONE_LOCAL_REST",
		"sourceScene": SOURCE_SCENE,
		"skeletonPath": str(instance.get_path_to(skeleton)),
		"boneCount": skeleton.get_bone_count(),
		"bones": bones
	}
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		return _fail("OUTPUT_OPEN_FAILED")
	file.store_string(JSON.stringify(payload, "  ") + "\n")
	file.close()
	print("CANONICAL_LOCAL_REST_PROFILE: PASS bones=%d" % skeleton.get_bone_count())
	quit(0)

func _fail(reason: String) -> void:
	push_error("CANONICAL_LOCAL_REST_PROFILE: %s" % reason)
	quit(1)
