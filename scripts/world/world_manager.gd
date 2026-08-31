class_name WorldManager
extends Node

signal destination_changed(destination_id: StringName, area: Node)
signal transition_rejected(destination_id: StringName, reason: StringName)
signal transition_started(destination_id: StringName)

const UNKNOWN_DESTINATION := &"UNKNOWN_DESTINATION"
const DISABLED_DESTINATION := &"DISABLED_DESTINATION"
const TRANSITION_BUSY := &"TRANSITION_BUSY"
const INVALID_REGISTRY := &"INVALID_REGISTRY"
const INSTANTIATION_FAILED := &"INSTANTIATION_FAILED"

@export var registry: Resource
@export var initial_destination: StringName = &"city_intro"
@export var world_container_path: NodePath = ^"../WorldContainer"
@export var transition_path: NodePath = ^"../PersistentUI/TransitionOverlay"

var current_destination_id: StringName
var current_area: Node
var transition_in_progress := false

@onready var world_container: Node = get_node(world_container_path)
@onready var scene_transition: CanvasLayer = get_node(transition_path)

func _ready() -> void:
	var errors := PackedStringArray()
	if registry == null:
		errors.append("Registry is null")
	else:
		errors = registry.call("validation_errors")
	if not errors.is_empty():
		for error in errors:
			push_error("WorldRegistry: " + error)
		transition_rejected.emit(initial_destination, INVALID_REGISTRY)
		return
	call_deferred("request_destination", initial_destination)

func request_destination(destination_id: StringName) -> bool:
	if transition_in_progress:
		transition_rejected.emit(destination_id, TRANSITION_BUSY)
		return false
	if registry == null:
		transition_rejected.emit(destination_id, INVALID_REGISTRY)
		return false
	var destination: Resource = registry.call("resolve", destination_id)
	if destination == null:
		transition_rejected.emit(destination_id, UNKNOWN_DESTINATION)
		return false
	if not destination.enabled:
		transition_rejected.emit(destination_id, DISABLED_DESTINATION)
		return false
	if not destination.is_valid():
		transition_rejected.emit(destination_id, INVALID_REGISTRY)
		return false
	transition_in_progress = true
	transition_started.emit(destination_id)
	_perform_transition(destination)
	return true

func _perform_transition(destination: Resource) -> void:
	await scene_transition.call("cover", destination.get("display_name"))
	var packed_scene: PackedScene = destination.get("scene")
	var next_area: Node = packed_scene.instantiate()
	if next_area == null:
		transition_in_progress = false
		await scene_transition.call("reveal")
		transition_rejected.emit(destination.get("id"), INSTANTIATION_FAILED)
		return
	if is_instance_valid(current_area):
		world_container.remove_child(current_area)
		current_area.queue_free()
	world_container.add_child(next_area)
	current_area = next_area
	current_destination_id = destination.get("id")
	await scene_transition.call("reveal")
	transition_in_progress = false
	destination_changed.emit(destination.get("id"), current_area)

func destination_count() -> int:
	return world_container.get_child_count()
