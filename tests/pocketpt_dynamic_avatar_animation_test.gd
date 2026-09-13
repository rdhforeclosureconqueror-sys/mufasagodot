extends SceneTree

const RASHAD_RESOURCE := "res://assets/characters/pocketpt/source/rashad1.glb"
const BONES := [&"Hips", &"LeftArm", &"RightArm", &"LeftUpLeg", &"RightUpLeg"]

var player: GymPlayerController
var loader: PocketPTAvatarLoader
var animator: PocketPTLocomotionAnimator
var phone_flow: PocketPTPhoneFlow
var avatar: Node3D
var skeleton: Skeleton3D
var diagnostics: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://Main.tscn") as PackedScene
	if packed == null or change_scene_to_packed(packed) != OK:
		return _fail("MAIN_SCENE")
	await scene_changed
	for frame in 8:
		await physics_frame
	player = current_scene.get_node("player") as GymPlayerController
	var bootstrap := current_scene.get_node("PocketPTBootstrap")
	loader = bootstrap.avatar_loader as PocketPTAvatarLoader
	animator = bootstrap.locomotion_animator as PocketPTLocomotionAnimator
	phone_flow = bootstrap.phone_flow as PocketPTPhoneFlow
	phone_flow.bridge_message_prepared.connect(func(payload: Dictionary):
		if payload.get("event") == "DIAGNOSTIC": diagnostics.append(payload))
	loader._active_member_id = "dynamic-animation-test"
	loader._generation = 1
	loader.import_buffer_for_test(FileAccess.get_file_as_bytes(RASHAD_RESOURCE), "dynamic-animation-test", {"profileVersion":"0123456789abcdef0123456789abcdef"})
	for frame in 8:
		await process_frame
	avatar = player.get_node_or_null("avataranchor/PocketPTAvatarVisual") as Node3D
	if avatar == null:
		return _fail("PERSONAL_AVATAR_MOUNT")
	var skeletons := avatar.find_children("*", "Skeleton3D", true, false)
	if skeletons.size() != 1:
		return _fail("PERSONAL_SKELETON_COUNT_%d" % skeletons.size())
	skeleton = skeletons[0] as Skeleton3D
	_print_inventory()
	if animator.animation_player == null or animator.animation_tree == null:
		return _fail("ANIMATION_OWNER_NOT_BOUND")
	for animation_name in [&"player/Idle", &"player/Walk", &"player/Run", &"action/ThrillerPart1"]:
		if not _verify_tracks(animation_name):
			return
	var rest := _sample_bones(skeleton)
	var fallback_skeletons := player.get_node("Sketchfab_Scene").find_children("*", "Skeleton3D", true, false)
	var fallback_skeleton := fallback_skeletons[0] as Skeleton3D
	var fallback_before := _sample_available_bones(fallback_skeleton)
	for frame in 12:
		await process_frame
	var idle := _sample_bones(skeleton)
	_trace("STANDING")
	if not _state_is("IDLE", "player/Idle"): return _fail("STANDING_STATE")
	var fallback_after := _sample_available_bones(fallback_skeleton)
	_print_changes("IDLE", rest, idle)
	if not _changed(rest, idle):
		return _fail("IDLE_NOT_AFFECTING_PERSONAL_SKELETON")
	print("HIDDEN_FALLBACK_BONES_CHANGING: %s" % _changed(fallback_before, fallback_after))
	if _changed(fallback_before, fallback_after): return _fail("ANIMATING_FALLBACK_SKELETON")
	if not player.set_remote_intent(Vector2.UP, 300):
		return _fail("REMOTE_WALK_INTENT")
	for frame in 18:
		await physics_frame
	var walk := _sample_bones(skeleton)
	_trace("FORWARD_WALK")
	if not _state_is("WALK", "player/Walk"): return _fail("MOVING_BODY_STUCK_IN_IDLE")
	_print_changes("WALK", idle, walk)
	if animator.current_state != &"WALK" or not _changed(idle, walk):
		return _fail("WALK_NOT_AFFECTING_PERSONAL_SKELETON")
	player.stop_navigation()
	for frame in 12:
		await physics_frame
	if animator.current_state != &"IDLE":
		return _fail("STOP_NOT_IDLE")
	_trace("WALK_RELEASE")
	if not _state_is("IDLE", "player/Idle"): return _fail("STOP_STATE")
	player.set_locomotion_mode("RUN")
	Input.action_press("ui_up")
	for frame in 30:
		await physics_frame
	var run := _sample_bones(skeleton)
	_trace("FORWARD_RUN")
	if not _state_is("RUN", "player/Run"): return _fail("RUN_STATE_NOT_ACTIVE")
	if animator.current_state != &"RUN" or not _changed(idle, run):
		return _fail("RUN_NOT_AFFECTING_PERSONAL_SKELETON")
	Input.action_release("ui_up")
	player.stop_navigation()
	for frame in 30: await physics_frame
	_trace("RUN_RELEASE")
	if not _state_is("IDLE", "player/Idle"): return _fail("RUN_STOP_STATE")
	player.set_locomotion_mode("WALK")
	var mat_targets := get_nodes_in_group("pocketpt_mat_target")
	if mat_targets.is_empty(): return _fail("MAT_TARGET")
	var arrived := [false]
	player.route_finished.connect(func(ok: bool): arrived[0] = ok)
	if not player.start_route((mat_targets[0] as Node3D).global_position): return _fail("GO_TO_MAT_START")
	for frame in 30: await physics_frame
	_trace("GO_TO_MAT")
	if not _state_is("WALK", "player/Walk"): return _fail("GO_TO_MAT_NOT_WALK")
	for frame in 450:
		await physics_frame
		if arrived[0]: break
	if not arrived[0]: return _fail("GO_TO_MAT_ARRIVAL")
	for frame in 20: await physics_frame
	_trace("GO_TO_MAT_ARRIVAL")
	if not _state_is("IDLE", "player/Idle"): return _fail("ARRIVAL_NOT_IDLE")
	if not animator.request_action(&"action/ThrillerPart1"):
		return _fail("THRILLER_REQUEST")
	for frame in 12:
		await process_frame
	var thriller := _sample_bones(skeleton)
	if not _changed(run, thriller):
		return _fail("THRILLER_NOT_AFFECTING_PERSONAL_SKELETON")
	var clip := animator.animation_player.get_animation(&"action/ThrillerPart1")
	animator.animation_player.seek(clip.length - 0.01, true)
	animator.animation_player.advance(0.02)
	await process_frame
	if animator.current_state != &"IDLE" or animator.action_override_active:
		return _fail("THRILLER_NOT_RETURNING_IDLE")
	phone_flow.ingest_message_for_test({"type":"POCKETPT_GODOT_BRIDGE", "protocolVersion":1, "event":"DIAGNOSTICS_REQUEST", "diagnosticVersion":1, "requestId":"dynamic-animation"})
	if not diagnostics.any(func(value: Dictionary): return value.get("stage") == "ANIMATION_IDLE" and value.get("status") == "PASS"):
		return _fail("ANIMATION_IDLE_DIAGNOSTIC")
	if not diagnostics.any(func(value: Dictionary): return value.get("stage") == "LOCOMOTION" and value.get("status") == "PASS"):
		return _fail("LOCOMOTION_DIAGNOSTIC")
	var fallback := player.get_node("Sketchfab_Scene") as Node3D
	if fallback.visible:
		return _fail("FALLBACK_NOT_HIDDEN")
	print("POCKETPT_DYNAMIC_AVATAR_ANIMATION_TEST: PASS")
	quit(0)

func _print_inventory() -> void:
	var fallback_skeletons := player.get_node("Sketchfab_Scene").find_children("*", "Skeleton3D", true, false)
	print("PLAYER_PATH: %s" % player.get_path())
	print("AVATAR_ANCHOR_PATH: %s" % player.get_node("avataranchor").get_path())
	print("PERSONAL_AVATAR_PATH: %s" % avatar.get_path())
	print("PERSONAL_SKELETON_PATH: %s" % skeleton.get_path())
	print("FALLBACK_SKELETON_PATH: %s" % ((fallback_skeletons[0] as Skeleton3D).get_path() if not fallback_skeletons.is_empty() else NodePath("NONE")))
	print("FALLBACK_VISIBLE: %s" % player.get_node("Sketchfab_Scene").visible)
	print("ANIMATION_PLAYER_PATH: %s" % animator.animation_player.get_path())
	print("ANIMATION_PLAYER_ROOT: %s" % animator.animation_player.root_node)
	print("ANIMATION_TREE_PATH: %s" % animator.animation_tree.get_path())
	print("ANIMATION_TREE_ANIM_PLAYER: %s" % animator.animation_tree.anim_player)
	print("LOCOMOTION_ANIMATOR_PATH: %s" % animator.get_path())
	print("ACTIVE_SKELETON_TARGET: %s" % skeleton.get_path())

func _verify_tracks(animation_name: StringName) -> bool:
	var clip := animator.animation_player.get_animation(animation_name)
	if clip == null:
		_fail("MISSING_%s" % animation_name)
		return false
	var root := animator.animation_player.get_node(animator.animation_player.root_node)
	var reported := 0
	for track_index in clip.get_track_count():
		var path := clip.track_get_path(track_index)
		var node_path := NodePath(str(path).get_slice(":", 0))
		var bone := str(path).get_slice(":", 1)
		var target := root.get_node_or_null(node_path)
		var resolves := target == skeleton and skeleton.find_bone(bone) >= 0
		if reported < 2:
			print("TRACK animation=%s path=%s bone=%s resolves=%s target=%s" % [animation_name, node_path, bone, resolves, target.get_path() if target != null else NodePath("NONE")])
			reported += 1
		if not resolves:
			_fail("ANIMATION_TRACK_PATH_UNRESOLVED_%s_%s" % [animation_name, bone])
			return false
	return true

func _sample_bones(target: Skeleton3D) -> Dictionary:
	var result := {}
	for bone_name in BONES:
		var index := target.find_bone(bone_name)
		if index < 0:
			_fail("MISSING_BONE_%s" % bone_name)
			return {}
		result[bone_name] = target.get_bone_pose(index)
	return result

func _sample_available_bones(target: Skeleton3D) -> Dictionary:
	var result := {}
	for bone_index in mini(5, target.get_bone_count()):
		result[bone_index] = target.get_bone_pose(bone_index)
	return result

func _changed(before: Dictionary, after: Dictionary) -> bool:
	for bone_name in before:
		if not (before[bone_name] as Transform3D).is_equal_approx(after[bone_name]):
			return true
	return false

func _print_changes(label: String, before: Dictionary, after: Dictionary) -> void:
	for bone_name in BONES:
		print("BONE_CHANGE state=%s bone=%s changed=%s" % [label, bone_name, not (before[bone_name] as Transform3D).is_equal_approx(after[bone_name])])

func _trace(stage: String) -> void:
	var sample := animator.runtime_snapshot
	print("LOCOMOTION_TRACE stage=%s action=%s direction=%s velocity=%s displacement=%.6f mode=%s requested=%s actual_tree=%s clip=%s moving=%s" % [stage, sample.get("controlAction"), sample.get("requestedDirection"), sample.get("velocity"), float(sample.get("actualHorizontalDisplacement", 0.0)), sample.get("movementMode"), sample.get("requestedLocomotionState"), sample.get("actualAnimationTreeState"), sample.get("currentClip"), sample.get("physicalMovementObserved")])

func _state_is(state_name: String, clip_name: String) -> bool:
	return str(animator.runtime_snapshot.get("requestedLocomotionState")) == state_name and str(animator.runtime_snapshot.get("actualAnimationTreeState")) == state_name and str(animator.runtime_snapshot.get("currentClip")) == clip_name

func _fail(boundary: String) -> void:
	push_error("POCKETPT_DYNAMIC_AVATAR_ANIMATION_TEST: FAIL " + boundary)
	quit(1)
