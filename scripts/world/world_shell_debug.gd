extends Node

const ORDER: Array[StringName] = [&"city_intro", &"pyramid_exterior", &"pyramid_lobby", &"training_floor"]

@export var manager_path: NodePath = ^"../WorldManager"
@export var status_label_path: NodePath = ^"../PersistentUI/DeveloperHUD/Panel/Margin/VBox/Status"

@onready var manager: Node = get_node(manager_path)
@onready var status_label: Label = get_node(status_label_path)

func _ready() -> void:
	manager.destination_changed.connect(_on_destination_changed)
	manager.transition_rejected.connect(_on_transition_rejected)
	status_label.text = "LOADING CITY INTRO"

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	if event.keycode >= KEY_1 and event.keycode <= KEY_4:
		manager.request_destination(ORDER[event.keycode - KEY_1])
	elif event.keycode == KEY_N:
		_move_relative(1)
	elif event.keycode == KEY_P:
		_move_relative(-1)
	elif event.keycode == KEY_U:
		manager.request_destination(&"unknown_destination")
	elif event.keycode == KEY_D:
		_test_disabled_destination()
	elif event.keycode == KEY_O:
		_test_overlapping_request()

func _move_relative(offset: int) -> void:
	var current_index := ORDER.find(manager.current_destination_id)
	var next_index := posmod(current_index + offset, ORDER.size())
	manager.request_destination(ORDER[next_index])

func _test_disabled_destination() -> void:
	var registry: Resource = manager.get("registry")
	var destination: Resource = registry.call("resolve", &"training_floor")
	if destination == null:
		return
	var was_enabled: bool = destination.get("enabled")
	destination.set("enabled", false)
	manager.call("request_destination", destination.get("id"))
	destination.set("enabled", was_enabled)

func _test_overlapping_request() -> void:
	var first: StringName = &"pyramid_exterior" if manager.get("current_destination_id") != &"pyramid_exterior" else &"pyramid_lobby"
	manager.request_destination(first)
	manager.request_destination(&"training_floor")

func _on_destination_changed(destination_id: StringName, _area: Node) -> void:
	status_label.text = "ACTIVE: %s  •  AREAS: %d" % [destination_id.to_upper(), manager.destination_count()]

func _on_transition_rejected(destination_id: StringName, reason: StringName) -> void:
	status_label.text = "SAFE REJECT: %s  •  %s  •  ACTIVE: %s" % [reason, destination_id, manager.current_destination_id]
