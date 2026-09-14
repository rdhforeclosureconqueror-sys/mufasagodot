class_name PocketPTRemotePlayer
extends Node3D

signal remote_moved(presence_id: String)
signal avatar_animation_bound(presence_id: String)

const LIBRARY_PATH := "res://game/animations/player/player_locomotion_library.tres"
const ACTION_LIBRARY_PATH := "res://game/animations/player/player_action_library.tres"
const TREE_PATH := "res://game/animations/player/player_locomotion_tree.tres"
const RestRetarget = preload("res://scripts/pocketpt/pocketpt_animation_rest_retarget.gd")
const MAX_SAFE_SEQUENCE := 9007199254740991.0

@export var position_lerp_speed := 12.0
@export var yaw_lerp_speed := 14.0

var presence_id := ""
var member_id := ""
var display_name := ""
var last_sequence := -1
var locomotion := "IDLE"
var target_position := Vector3.ZERO
var target_yaw := 0.0
var avatar_loaded := false
var animation_binding_error := "REMOTE_AVATAR_NOT_MOUNTED"

var visual_anchor: Node3D
var _animation_player: AnimationPlayer
var _animation_tree: AnimationTree
var _playback: AnimationNodeStateMachinePlayback
var _active_skeleton: Skeleton3D
var _action_override_active := false
var _fallback_visual: Node3D

func _ready() -> void:
	if visual_anchor == null:
		visual_anchor = Node3D.new()
		visual_anchor.name = "VisualAnchor"
		visual_anchor.position = Vector3(0.0, -0.75, 0.0)
		add_child(visual_anchor)
	ensure_fallback_visual()

func configure(player_record: Dictionary) -> bool:
	presence_id = str(player_record.get("presenceId", ""))
	var member = player_record.get("member")
	if presence_id.is_empty() or not member is Dictionary:
		return false
	member_id = str(member.get("id", ""))
	display_name = str(member.get("displayName", "Member"))
	ensure_fallback_visual()
	var state = player_record.get("state")
	if state is Dictionary:
		_apply_state_internal(state, true)
	return not member_id.is_empty()

func apply_network_state(state: Dictionary) -> bool:
	if sequence_is_stale(state.get("seq")):
		return true
	return _apply_state_internal(state, false)

func sequence_is_stale(value: Variant) -> bool:
	var sequence_value := _sequence_value(value)
	return sequence_value >= 0 and sequence_value <= last_sequence

func has_fallback_visual() -> bool:
	return _fallback_visual != null and is_instance_valid(_fallback_visual) and _fallback_visual.visible

func ensure_fallback_visual() -> void:
	if visual_anchor == null or not is_instance_valid(visual_anchor):
		return
	if _fallback_visual != null and is_instance_valid(_fallback_visual):
		_fallback_visual.visible = true
		return
	var fallback := Node3D.new()
	fallback.name = "RemoteFallbackVisual"
	visual_anchor.add_child(fallback)

	var body := MeshInstance3D.new()
	body.name = "Body"
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.28
	body_mesh.height = 1.2
	body.mesh = body_mesh
	body.position = Vector3(0.0, 1.35, 0.0)
	fallback.add_child(body)

	var head := MeshInstance3D.new()
	head.name = "Head"
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.21
	head_mesh.height = 0.42
	head.mesh = head_mesh
	head.position = Vector3(0.0, 2.15, 0.0)
	fallback.add_child(head)

	_fallback_visual = fallback

func _clear_fallback_visual() -> void:
	if _fallback_visual != null and is_instance_valid(_fallback_visual):
		_fallback_visual.queue_free()
	_fallback_visual = null

func bind_avatar_root(avatar_root: Node3D) -> bool:
	avatar_loaded = false
	animation_binding_error = "REMOTE_AVATAR_NOT_MOUNTED"
	_animation_player = null
	_animation_tree = null
	_playback = null
	_active_skeleton = null
	_action_override_active = false
	if avatar_root == null or not is_instance_valid(avatar_root):
		return false
	var skeletons := avatar_root.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		animation_binding_error = "REMOTE_SKELETON_NOT_FOUND"
		return false
	var skeleton := skeletons[0] as Skeleton3D
	var source_library := load(LIBRARY_PATH) as AnimationLibrary
	var source_actions := load(ACTION_LIBRARY_PATH) as AnimationLibrary
	var state_machine := load(TREE_PATH) as AnimationNodeStateMachine
	if source_library == null or source_actions == null or state_machine == null:
		animation_binding_error = "REMOTE_ANIMATION_RESOURCES_MISSING"
		return false
	var target_path := str(avatar_root.get_path_to(skeleton))
	var locomotion_result := RestRetarget.mount_library(source_library, target_path, skeleton)
	var action_result := RestRetarget.mount_library(source_actions, target_path, skeleton)
	var retarget_error := str(locomotion_result.get("error", ""))
	if retarget_error.is_empty():
		retarget_error = str(action_result.get("error", ""))
	if not retarget_error.is_empty():
		animation_binding_error = "REMOTE_REST_RETARGET_FAILED:%s" % retarget_error
		return false
	var mounted_library = locomotion_result.get("library") as AnimationLibrary
	var mounted_actions = action_result.get("library") as AnimationLibrary
	if mounted_library == null or mounted_actions == null:
		animation_binding_error = "REMOTE_REST_RETARGET_FAILED:LIBRARY_MISSING"
		return false
	_animation_player = AnimationPlayer.new()
	_animation_player.name = "RemoteLocomotionPlayer"
	avatar_root.add_child(_animation_player)
	_animation_player.root_node = NodePath("..")
	_animation_player.add_animation_library(&"player", mounted_library)
	_animation_player.add_animation_library(&"action", mounted_actions)
	_animation_player.animation_finished.connect(_on_animation_finished)
	_animation_tree = AnimationTree.new()
	_animation_tree.name = "RemoteLocomotionTree"
	avatar_root.add_child(_animation_tree)
	_animation_tree.root_node = NodePath("..")
	_animation_tree.anim_player = NodePath("../RemoteLocomotionPlayer")
	_animation_tree.tree_root = state_machine.duplicate(true)
	_animation_tree.active = true
	_playback = _animation_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	_active_skeleton = skeleton
	animation_binding_error = _validate_track_targets()
	if not animation_binding_error.is_empty():
		_animation_tree.active = false
		return false
	_playback.start(&"IDLE")
	avatar_loaded = true
	_clear_fallback_visual()
	_apply_locomotion(locomotion)
	avatar_animation_bound.emit(presence_id)
	return true

func _process(delta: float) -> void:
	var before := global_position
	var position_weight := clampf(position_lerp_speed * delta, 0.0, 1.0)
	global_position = global_position.lerp(target_position, position_weight)
	if visual_anchor != null and is_instance_valid(visual_anchor):
		var yaw_weight := clampf(yaw_lerp_speed * delta, 0.0, 1.0)
		visual_anchor.rotation.y = lerp_angle(visual_anchor.rotation.y, target_yaw, yaw_weight)
	if global_position.distance_to(before) > 0.0001:
		remote_moved.emit(presence_id)

func _apply_state_internal(state: Dictionary, snap: bool) -> bool:
	var sequence_value := _sequence_value(state.get("seq"))
	var position = state.get("position")
	var yaw = state.get("yaw")
	var next_locomotion := str(state.get("locomotion", "IDLE")).to_upper()
	if sequence_value < 0 or sequence_value <= last_sequence:
		return false
	if not position is Array or position.size() != 3:
		return false
	if not _finite(position[0]) or not _finite(position[1]) or not _finite(position[2]) or not _finite(yaw):
		return false
	if next_locomotion not in ["IDLE", "WALK", "RUN", "STOP", "ACTION_OVERRIDE"]:
		return false
	last_sequence = sequence_value
	target_position = Vector3(float(position[0]), float(position[1]), float(position[2]))
	target_yaw = float(yaw)
	locomotion = next_locomotion
	if snap:
		global_position = target_position
		if visual_anchor != null and is_instance_valid(visual_anchor):
			visual_anchor.rotation.y = target_yaw
	_apply_locomotion(locomotion)
	return true

func _apply_locomotion(value: String) -> void:
	if not avatar_loaded or _playback == null or _animation_tree == null:
		return
	var normalized := value.to_upper()
	if normalized == "STOP":
		normalized = "IDLE"
	if normalized == "ACTION_OVERRIDE":
		# Protocol v1 carries only ACTION_OVERRIDE. ThrillerPart1 is currently the arena's sole authored action.
		if not _action_override_active and _animation_player != null and _animation_player.has_animation(&"action/ThrillerPart1"):
			_action_override_active = true
			_animation_tree.active = false
			_animation_player.play(&"action/ThrillerPart1", 0.15)
		return
	if _action_override_active:
		_animation_player.stop()
		_action_override_active = false
		_animation_tree.active = true
		_playback = _animation_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	if normalized not in ["IDLE", "WALK", "RUN"]:
		normalized = "IDLE"
	_playback.travel(StringName(normalized))

func _on_animation_finished(animation_name: StringName) -> void:
	if not _action_override_active or not String(animation_name).begins_with("action/"):
		return
	_action_override_active = false
	if _animation_tree != null:
		_animation_tree.active = true
		_playback = _animation_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
		if _playback != null:
			_playback.start(&"IDLE")
	locomotion = "IDLE"

func _validate_track_targets() -> String:
	if _animation_player == null or _active_skeleton == null:
		return "REMOTE_ANIMATION_PLAYER_NOT_BOUND"
	var animation_root := _animation_player.get_node_or_null(_animation_player.root_node)
	if animation_root == null:
		return "REMOTE_ANIMATION_PLAYER_NOT_BOUND"
	for animation_name in [&"player/Idle", &"player/Walk", &"player/Run", &"action/ThrillerPart1"]:
		var clip := _animation_player.get_animation(animation_name)
		if clip == null:
			return "REMOTE_ANIMATION_CLIP_MISSING"
		for track_index in clip.get_track_count():
			var path_text := str(clip.track_get_path(track_index))
			var target := animation_root.get_node_or_null(NodePath(path_text.get_slice(":", 0)))
			var bone_name := path_text.get_slice(":", 1)
			if target != _active_skeleton or _active_skeleton.find_bone(bone_name) < 0:
				return "REMOTE_ANIMATION_TRACK_PATH_UNRESOLVED"
	return ""

func _sequence_value(value: Variant) -> int:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return -1
	var numeric := float(value)
	if not is_finite(numeric) or numeric < 0.0 or numeric > MAX_SAFE_SEQUENCE or floor(numeric) != numeric:
		return -1
	return int(numeric)

func _finite(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))
