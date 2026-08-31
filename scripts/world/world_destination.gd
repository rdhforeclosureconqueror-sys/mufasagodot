class_name WorldDestination
extends Resource

@export var id: StringName
@export var display_name: String
@export var scene: PackedScene
@export var default_spawn_id: StringName = &"PlayerSpawn"
@export var enabled := true

func is_valid() -> bool:
	return not id.is_empty() and scene != null
