extends Node3D

@onready var playback: AnimationNodeStateMachinePlayback = $AnimationTree.get("parameters/playback")
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var state_label: Label = $UI/State

func _ready() -> void:
	animation_player.animation_finished.connect(_on_animation_finished)
	playback.start(&"IDLE")
	_set_state("IDLE")

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed: return
	if event.keycode == KEY_1: _travel(&"IDLE")
	elif event.keycode == KEY_2: _travel(&"WALK")
	elif event.keycode == KEY_3: _travel(&"RUN")
	elif event.keycode == KEY_4: play_thriller()

func _travel(state: StringName) -> void:
	animation_tree.active = true
	playback.travel(state)
	_set_state(String(state))

func play_thriller() -> void:
	animation_tree.active = false
	animation_player.play(&"action/ThrillerPart1", 0.15)
	_set_state("ACTION_OVERRIDE: THRILLER PART 1")

func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name != &"action/ThrillerPart1": return
	animation_tree.active = true
	playback = animation_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	playback.start(&"IDLE")
	_set_state("IDLE")

func _set_state(value: String) -> void:
	state_label.text = "CURRENT STATE: " + value + "\n1 Idle   2 Walk   3 Run   4 Thriller Part 1"
