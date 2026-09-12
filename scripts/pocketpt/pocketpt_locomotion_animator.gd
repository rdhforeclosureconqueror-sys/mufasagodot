class_name PocketPTLocomotionAnimator
extends Node

const LIBRARY_PATH := "res://game/animations/player/player_locomotion_library.tres"
const ACTION_LIBRARY_PATH := "res://game/animations/player/player_action_library.tres"
const TREE_PATH := "res://game/animations/player/player_locomotion_tree.tres"

var current_state := &"IDLE"
var animation_player: AnimationPlayer
var animation_tree: AnimationTree
var _playback: AnimationNodeStateMachinePlayback
var _avatar_root: Node3D
var action_override_active := false

func bind(player: GymPlayerController, avatar_loader: PocketPTAvatarLoader) -> void:
	player.locomotion_speed_changed.connect(_on_locomotion_speed_changed.bind(player.speed, player.speed * player.run_speed_multiplier))
	avatar_loader.avatar_mounted.connect(_on_avatar_mounted)

func _on_avatar_mounted(avatar_root: Node3D) -> void:
	_avatar_root = avatar_root
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
	_playback.start(&"IDLE")
	avatar_root.set_meta("pocketpt_shared_locomotion", true)

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

func request_action(semantic_id: StringName) -> bool:
	if animation_player == null or animation_tree == null: return false
	var qualified := StringName(semantic_id if String(semantic_id).begins_with("action/") else "action/" + String(semantic_id))
	if not animation_player.has_animation(qualified): return false
	action_override_active = true
	current_state = &"ACTION_OVERRIDE"
	animation_tree.active = false
	animation_player.play(qualified, 0.15)
	return true

func _on_animation_finished(animation_name: StringName) -> void:
	if not action_override_active or not String(animation_name).begins_with("action/"): return
	action_override_active = false
	current_state = &"IDLE"
	animation_tree.active = true
	_playback = animation_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	_playback.start(&"IDLE")

func _on_locomotion_speed_changed(actual_speed: float, _source: String, walk_speed: float, run_speed: float) -> void:
	if action_override_active: return
	var next_state := &"IDLE"
	if actual_speed > 0.05: next_state = &"RUN" if actual_speed >= lerpf(walk_speed, run_speed, 0.5) else &"WALK"
	if next_state == current_state: return
	current_state = next_state
	if _playback != null: _playback.travel(current_state)
