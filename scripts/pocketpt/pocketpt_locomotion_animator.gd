class_name PocketPTLocomotionAnimator
extends Node

signal runtime_evidence_changed()
signal action_override_changed(active: bool)

const LIBRARY_PATH := "res://game/animations/player/player_locomotion_library.tres"
const ACTION_LIBRARY_PATH := "res://game/animations/player/player_action_library.tres"
const TREE_PATH := "res://game/animations/player/player_locomotion_tree.tres"

var current_state := &"IDLE"
var animation_player: AnimationPlayer
var animation_tree: AnimationTree
var _playback: AnimationNodeStateMachinePlayback
var _avatar_root: Node3D
var active_skeleton: Skeleton3D
var action_override_active := false
var binding_error := "AVATAR_SKELETON_NOT_BOUND"
var _last_pose: Dictionary = {}
var _observed_states: Dictionary = {}
var _walk_displacement_seen := false
var runtime_snapshot: Dictionary = {
	"movementMode": "WALK", "actualHorizontalDisplacement": 0.0,
	"requestedLocomotionState": "IDLE", "actualAnimationTreeState": "IDLE",
	"currentClip": "player/Idle", "physicalMovementObserved": false,
}

func bind(player: GymPlayerController, avatar_loader: PocketPTAvatarLoader) -> void:
	player.locomotion_sampled.connect(_on_locomotion_sampled)
	avatar_loader.avatar_mounted.connect(_on_avatar_mounted)

func _on_avatar_mounted(avatar_root: Node3D) -> void:
	_avatar_root = avatar_root
	active_skeleton = null
	binding_error = "AVATAR_SKELETON_NOT_BOUND"
	_last_pose.clear()
	_observed_states.clear()
	_walk_displacement_seen = false
	var skeletons := avatar_root.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty(): return
	var skeleton := skeletons[0] as Skeleton3D
	var source_library := load(LIBRARY_PATH) as AnimationLibrary
	var source_actions := load(ACTION_LIBRARY_PATH) as AnimationLibrary
	var state_machine := load(TREE_PATH) as AnimationNodeStateMachine
	if source_library == null or source_actions == null or state_machine == null: return
	var target_path := str(avatar_root.get_path_to(skeleton))
	var mounted_library := _mount_library(source_library, target_path)
	var mounted_actions := _mount_library(source_actions, target_path)
	animation_player = AnimationPlayer.new(); animation_player.name = "PocketPTLocomotionPlayer"; avatar_root.add_child(animation_player)
	animation_player.root_node = NodePath(".."); animation_player.add_animation_library(&"player", mounted_library); animation_player.add_animation_library(&"action", mounted_actions)
	animation_player.animation_finished.connect(_on_animation_finished)
	animation_tree = AnimationTree.new(); animation_tree.name = "PocketPTLocomotionTree"; avatar_root.add_child(animation_tree)
	animation_tree.root_node = NodePath(".."); animation_tree.anim_player = NodePath("../PocketPTLocomotionPlayer")
	animation_tree.tree_root = state_machine.duplicate(true); animation_tree.active = true
	_playback = animation_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	active_skeleton = skeleton
	binding_error = _validate_track_targets()
	if not binding_error.is_empty():
		animation_tree.active = false
		runtime_evidence_changed.emit()
		return
	_playback.start(&"IDLE")
	avatar_root.set_meta("pocketpt_shared_locomotion", true)
	set_process(true)
	runtime_evidence_changed.emit()

func _process(_delta: float) -> void:
	if active_skeleton == null or not is_instance_valid(active_skeleton) or not binding_error.is_empty(): return
	var pose := _sample_pose()
	if not _last_pose.is_empty() and _pose_changed(_last_pose, pose):
		var evidence_state := &"ACTION_OVERRIDE" if action_override_active else current_state
		if not bool(_observed_states.get(evidence_state, false)):
			_observed_states[evidence_state] = true
			runtime_evidence_changed.emit()
	_last_pose = pose

func diagnostic_status(state_name: StringName) -> Dictionary:
	if not binding_error.is_empty(): return {"status": "FAIL", "reason": binding_error}
	var actual_state := StringName(runtime_snapshot.get("actualAnimationTreeState", ""))
	var requested_state := StringName(runtime_snapshot.get("requestedLocomotionState", ""))
	var moving := bool(runtime_snapshot.get("physicalMovementObserved", false))
	if moving and actual_state == &"IDLE": return {"status": "FAIL", "reason": "MOVING_BODY_STUCK_IN_IDLE"}
	if moving and requested_state == &"WALK" and actual_state != &"WALK": return {"status": "FAIL", "reason": "WALK_STATE_NOT_ACTIVE"}
	if moving and requested_state == &"RUN" and actual_state != &"RUN": return {"status": "FAIL", "reason": "RUN_STATE_NOT_ACTIVE"}
	if state_name == &"WALK" and not _walk_displacement_seen: return {"status": "WAITING", "reason": "WALK_NOT_PLAYING"}
	if bool(_observed_states.get(state_name, false)): return {"status": "PASS", "reason": ""}
	return {"status": "WAITING", "reason": "%s_NOT_PLAYING" % String(state_name)}

func locomotion_diagnostic_status() -> Dictionary:
	if not binding_error.is_empty(): return {"status": "FAIL", "reason": binding_error}
	var actual_state := StringName(runtime_snapshot.get("actualAnimationTreeState", ""))
	var requested_state := StringName(runtime_snapshot.get("requestedLocomotionState", ""))
	var moving := bool(runtime_snapshot.get("physicalMovementObserved", false))
	if moving and actual_state == &"IDLE": return {"status": "FAIL", "reason": "MOVING_BODY_STUCK_IN_IDLE"}
	if moving and requested_state == &"WALK" and actual_state != &"WALK": return {"status": "FAIL", "reason": "WALK_STATE_NOT_ACTIVE"}
	if moving and requested_state == &"RUN" and actual_state != &"RUN": return {"status": "FAIL", "reason": "RUN_STATE_NOT_ACTIVE"}
	if bool(_observed_states.get(&"WALK", false)) or bool(_observed_states.get(&"RUN", false)): return {"status": "PASS", "reason": ""}
	return {"status": "WAITING", "reason": "WALK_NOT_PLAYING"}

func _validate_track_targets() -> String:
	if animation_player == null or active_skeleton == null: return "ANIMATION_PLAYER_NOT_BOUND"
	var animation_root := animation_player.get_node_or_null(animation_player.root_node)
	if animation_root == null: return "ANIMATION_PLAYER_NOT_BOUND"
	for animation_name in [&"player/Idle", &"player/Walk", &"player/Run", &"action/ThrillerPart1"]:
		var clip := animation_player.get_animation(animation_name)
		if clip == null: return "ANIMATION_PLAYER_NOT_BOUND"
		for track_index in clip.get_track_count():
			var path_text := str(clip.track_get_path(track_index))
			var target := animation_root.get_node_or_null(NodePath(path_text.get_slice(":", 0)))
			var bone_name := path_text.get_slice(":", 1)
			if target != active_skeleton or active_skeleton.find_bone(bone_name) < 0:
				return "ANIMATION_TRACK_PATH_UNRESOLVED"
	return ""

func _sample_pose() -> Dictionary:
	var pose := {}
	for bone_name in [&"Hips", &"LeftArm", &"RightArm", &"LeftUpLeg", &"RightUpLeg"]:
		var index := active_skeleton.find_bone(bone_name)
		if index >= 0: pose[bone_name] = active_skeleton.get_bone_pose(index)
	return pose

func _pose_changed(before: Dictionary, after: Dictionary) -> bool:
	for bone_name in before:
		if after.has(bone_name) and not (before[bone_name] as Transform3D).is_equal_approx(after[bone_name]): return true
	return false

func _mount_library(source: AnimationLibrary, target_path: String) -> AnimationLibrary:
	var mounted := AnimationLibrary.new()
	for clip_name in source.get_animation_list():
		var clip := source.get_animation(clip_name).duplicate(true) as Animation
		for track_index in clip.get_track_count():
			var old_path := str(clip.track_get_path(track_index))
			var separator := old_path.find(":")
			if separator >= 0: clip.track_set_path(track_index, NodePath(target_path + old_path.substr(separator)))
		mounted.add_animation(clip_name, clip)
	return mounted

func can_request_action(semantic_id: StringName) -> bool:
	if action_override_active or animation_player == null or animation_tree == null or not binding_error.is_empty(): return false
	var qualified := StringName(semantic_id if String(semantic_id).begins_with("action/") else "action/" + String(semantic_id))
	return animation_player.has_animation(qualified)

func request_action(semantic_id: StringName) -> bool:
	if not can_request_action(semantic_id): return false
	var qualified := StringName(semantic_id if String(semantic_id).begins_with("action/") else "action/" + String(semantic_id))
	action_override_active = true
	current_state = &"ACTION_OVERRIDE"
	animation_tree.active = false
	animation_player.play(qualified, 0.15)
	action_override_changed.emit(true)
	return true

func _on_animation_finished(animation_name: StringName) -> void:
	if not action_override_active or not String(animation_name).begins_with("action/"): return
	action_override_active = false
	current_state = &"IDLE"
	animation_tree.active = true
	_playback = animation_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	_playback.start(&"IDLE")
	action_override_changed.emit(false)

func _on_locomotion_sampled(sample: Dictionary) -> void:
	if action_override_active: return
	var actual_displacement := float(sample.get("actualHorizontalDisplacement", 0.0))
	var movement_mode := str(sample.get("movementMode", "WALK"))
	var next_state := &"IDLE"
	if actual_displacement > 0.0005: next_state = &"RUN" if movement_mode == "RUN" else &"WALK"
	if next_state == &"WALK": _walk_displacement_seen = true
	if next_state != current_state:
		current_state = next_state
		if _playback != null: _playback.travel(current_state)
	_update_runtime_snapshot(sample, next_state)

func _update_runtime_snapshot(sample: Dictionary, requested_state: StringName) -> void:
	var actual_state := StringName("UNBOUND")
	if _playback != null: actual_state = _playback.get_current_node()
	var clip := _clip_for_state(actual_state)
	if action_override_active and animation_player != null: clip = str(animation_player.current_animation)
	runtime_snapshot = {
		"controlAction": sample.get("controlAction", "NONE"),
		"requestedDirection": sample.get("requestedDirection", Vector2.ZERO),
		"velocity": sample.get("velocity", Vector3.ZERO),
		"actualHorizontalDisplacement": sample.get("actualHorizontalDisplacement", 0.0),
		"actualHorizontalSpeed": sample.get("actualHorizontalSpeed", 0.0),
		"movementMode": sample.get("movementMode", "WALK"),
		"requestedLocomotionState": String(requested_state),
		"actualAnimationTreeState": String(actual_state),
		"currentClip": clip,
		"physicalMovementObserved": sample.get("physicalMovementObserved", false),
	}
	runtime_evidence_changed.emit()

func _clip_for_state(state_name: StringName) -> String:
	match state_name:
		&"IDLE": return "player/Idle"
		&"WALK": return "player/Walk"
		&"RUN": return "player/Run"
		_: return ""
