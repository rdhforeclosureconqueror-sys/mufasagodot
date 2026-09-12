extends SceneTree

const RASHAD_RESOURCE := "res://assets/characters/pocketpt/source/rashad1.glb"
const SHOTS := "res://build/visual-acceptance"

var player: GymPlayerController
var anchor: Node3D
var loader: PocketPTAvatarLoader
var animator: PocketPTLocomotionAnimator
var avatar: Node3D

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
	var packed := load("res://Main.tscn") as PackedScene
	if packed == null or change_scene_to_packed(packed) != OK: return _fail("MAIN")
	await scene_changed
	for frame in 8: await physics_frame
	player = current_scene.get_node("player") as GymPlayerController
	anchor = player.get_node("avataranchor") as Node3D
	var bootstrap := current_scene.get_node("PocketPTBootstrap")
	loader = bootstrap.avatar_loader as PocketPTAvatarLoader
	animator = bootstrap.locomotion_animator as PocketPTLocomotionAnimator
	loader._active_member_id = "rashad-visual-acceptance"
	loader._generation = 1
	loader.import_buffer_for_test(FileAccess.get_file_as_bytes(RASHAD_RESOURCE), "rashad-visual-acceptance", {"profileVersion":"0123456789abcdef0123456789abcdef"})
	for frame in 8: await process_frame
	avatar = anchor.get_node_or_null("PocketPTAvatarVisual") as Node3D
	if avatar == null: return _fail("PERSONAL_AVATAR_MOUNT")
	_print_identity_and_inventory()
	_print_surfaces()
	await _stage("A_SPAWN_IDLE")
	player.set_remote_intent(Vector2.UP, 300)
	for frame in 6: await physics_frame
	await _stage("B_MANUAL_WALK")
	player.stop_navigation()
	for frame in 12: await physics_frame
	await _stage("C_STOP_IDLE")
	var target := get_nodes_in_group("pocketpt_mat_target")[0] as Node3D
	var arrived := [false]
	player.route_finished.connect(func(ok: bool): arrived[0] = ok)
	if not player.start_route(target.global_position): return _fail("GO_TO_MAT_START")
	for frame in 30: await physics_frame
	await _stage("D_GO_TO_MAT_WALK")
	for frame in 450:
		await physics_frame
		if arrived[0]: break
	if not arrived[0]: return _fail("GO_TO_MAT_ARRIVAL")
	await _stage("E_GO_TO_MAT_IDLE")
	Input.action_press("ui_up")
	var shift_down := InputEventKey.new()
	shift_down.keycode = KEY_SHIFT
	shift_down.pressed = true
	Input.parse_input_event(shift_down)
	for frame in 12: await physics_frame
	await _stage("F_RUN")
	Input.action_release("ui_up")
	shift_down.pressed = false
	Input.parse_input_event(shift_down)
	player.stop_navigation()
	for frame in 4: await physics_frame
	if not animator.request_action(&"action/ThrillerPart1"): return _fail("THRILLER_START")
	for frame in 30: await process_frame
	await _stage("G_THRILLER")
	var thriller := animator.animation_player.get_animation(&"action/ThrillerPart1")
	animator.animation_player.seek(thriller.length - 0.01, true)
	animator.animation_player.advance(0.02)
	for frame in 5: await process_frame
	await _stage("H_RETURN_IDLE")
	print("PRODUCTION_AVATAR_VISUAL_ACCEPTANCE: PASS")
	quit(0)

func _print_identity_and_inventory() -> void:
	print("PERSONAL_AVATAR_RESOURCE: %s" % RASHAD_RESOURCE)
	print("PERSONAL_AVATAR_NODE: %s" % avatar.get_path())
	for value in player.find_children("*", "MeshInstance3D", true, false):
		var mesh := value as MeshInstance3D
		print("PLAYER_MESH path=%s visible=%s inherited_visible=%s owner_visual=%s" % [mesh.get_path(), mesh.visible, mesh.is_visible_in_tree(), "PERSONAL" if avatar.is_ancestor_of(mesh) else "FALLBACK"])
	for value in player.find_children("*", "Skeleton3D", true, false):
		var skeleton := value as Skeleton3D
		print("PLAYER_SKELETON path=%s owner_visual=%s" % [skeleton.get_path(), "PERSONAL" if avatar.is_ancestor_of(skeleton) else "FALLBACK"])
	print("ACTIVE_PLAYER_VISUAL_COUNT: %d" % _visible_visual_roots())

func _print_surfaces() -> void:
	var floor_mesh := current_scene.get_node("GymEnvironment/RubberFloor/FloorMesh") as MeshInstance3D
	var mat_mesh := current_scene.get_node("GymEnvironment/ExerciseMatArea/ExerciseMatSelectable/ExerciseMat") as MeshInstance3D
	print("GYM_FLOOR_TOP_Y: %.6f" % (floor_mesh.global_transform * floor_mesh.get_aabb()).end.y)
	print("MAT_TOP_Y: %.6f" % (mat_mesh.global_transform * mat_mesh.get_aabb()).end.y)

func _stage(stage: String) -> void:
	var bounds := _global_bounds(avatar)
	var feet := _foot_values()
	var wrapper_transform := avatar.transform
	print("VISUAL_STAGE %s player=(%.6f,%.6f,%.6f) anchor_y=%.6f min_y=%.6f max_y=%.6f left_foot_y=%.6f right_foot_y=%.6f visual_count=%d state=%s" % [stage, player.global_position.x, player.global_position.y, player.global_position.z, anchor.global_position.y, bounds.position.y, bounds.end.y, feet.x, feet.y, _visible_visual_roots(), animator.current_state])
	await process_frame
	var image := root.get_viewport().get_texture().get_image()
	var save_error := image.save_png(ProjectSettings.globalize_path("%s/%s.png" % [SHOTS, stage]))
	if save_error != OK: push_error("SCREENSHOT_FAILED:%s" % stage)
	if not avatar.transform.is_equal_approx(wrapper_transform): push_error("VISUAL_ROOT_DRIFT:%s" % stage)

func _global_bounds(root_node: Node3D) -> AABB:
	var combined := AABB()
	var found := false
	for value in root_node.find_children("*", "MeshInstance3D", true, false):
		var mesh := value as MeshInstance3D
		if mesh.mesh == null: continue
		var bounds := mesh.global_transform * mesh.get_aabb()
		combined = bounds if not found else combined.merge(bounds)
		found = true
	return combined

func _foot_values() -> Vector2:
	var skeletons := avatar.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty(): return Vector2(INF, INF)
	var skeleton := skeletons[0] as Skeleton3D
	var left := skeleton.find_bone("LeftFoot")
	var right := skeleton.find_bone("RightFoot")
	return Vector2((skeleton.global_transform * skeleton.get_bone_global_pose(left)).origin.y, (skeleton.global_transform * skeleton.get_bone_global_pose(right)).origin.y)

func _visible_visual_roots() -> int:
	var count := 0
	var fallback := player.get_node_or_null("Sketchfab_Scene") as Node3D
	if fallback != null and fallback.visible: count += 1
	if avatar != null and avatar.visible: count += 1
	return count

func _fail(boundary: String) -> void:
	push_error("PRODUCTION_AVATAR_VISUAL_ACCEPTANCE: FAIL " + boundary)
	quit(1)
