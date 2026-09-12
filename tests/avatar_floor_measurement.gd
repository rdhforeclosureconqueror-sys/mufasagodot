extends SceneTree

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var packed := load("res://Main.tscn") as PackedScene
	if packed == null or change_scene_to_packed(packed) != OK: return _done(1)
	await scene_changed
	for frame in 4: await process_frame
	var player := current_scene.get_node("player") as CharacterBody3D
	var collider := player.get_node("CollisionShape3D") as CollisionShape3D
	var anchor := player.get_node("avataranchor") as Node3D
	var bootstrap := current_scene.get_node("PocketPTBootstrap")
	var loader = bootstrap.avatar_loader
	loader._active_member_id = "visual-measurement"
	loader._generation = 1
	var bytes := FileAccess.get_file_as_bytes("res://assets/characters/pocketpt/source/rashad1.glb")
	loader.import_buffer_for_test(bytes, "visual-measurement", {"profileVersion":"0123456789abcdef0123456789abcdef"})
	for frame in 4: await process_frame
	var wrapper := anchor.get_node_or_null("PocketPTAvatarVisual") as Node3D
	if wrapper == null: return _done(2)
	var min_y := INF
	var max_y := -INF
	for value in wrapper.find_children("*", "MeshInstance3D", true, false):
		var mesh := value as MeshInstance3D
		var world_bounds := mesh.global_transform * mesh.get_aabb()
		min_y = minf(min_y, world_bounds.position.y)
		max_y = maxf(max_y, world_bounds.end.y)
	var skeletons := wrapper.find_children("*", "Skeleton3D", true, false)
	print("AVATAR_FLOOR_MEASUREMENT player_y=%.6f collider_y=%.6f anchor_local_y=%.6f anchor_global_y=%.6f wrapper_local_y=%.6f mesh_min_y=%.6f mesh_max_y=%.6f loader_floor_offset=%.6f scale=%.6f" % [player.global_position.y, collider.global_position.y, anchor.position.y, anchor.global_position.y, wrapper.position.y, min_y, max_y, float(loader.avatar_state.floor_offset), wrapper.scale.x])
	if not skeletons.is_empty():
		var skeleton := skeletons[0] as Skeleton3D
		for bone_name in ["Hips", "LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"]:
			var index := skeleton.find_bone(bone_name)
			if index >= 0:
				print("AVATAR_BONE %s global_y=%.6f rest_origin_y=%.6f pose_origin_y=%.6f" % [bone_name, (skeleton.global_transform * skeleton.get_bone_global_pose(index)).origin.y, skeleton.get_bone_global_rest(index).origin.y, skeleton.get_bone_global_pose(index).origin.y])
	if "--visual" in OS.get_cmdline_user_args():
		for frame in 60: await process_frame
	_done(0)

func _done(code: int) -> void: quit(code)
