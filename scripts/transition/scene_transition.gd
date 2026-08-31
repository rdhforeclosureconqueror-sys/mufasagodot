class_name SceneTransition
extends CanvasLayer

@export_range(0.0, 2.0, 0.05) var duration := 0.22

@onready var curtain: ColorRect = $Overlay/Curtain
@onready var destination_label: Label = $Overlay/DestinationLabel

func _ready() -> void:
	curtain.modulate.a = 0.0
	destination_label.modulate.a = 0.0
	$Overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

func cover(destination_name: String) -> void:
	destination_label.text = "ENTERING\n" + destination_name.to_upper()
	$Overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween().set_parallel(true)
	tween.tween_property(curtain, "modulate:a", 1.0, duration)
	tween.tween_property(destination_label, "modulate:a", 1.0, duration)
	await tween.finished

func reveal() -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(curtain, "modulate:a", 0.0, duration)
	tween.tween_property(destination_label, "modulate:a", 0.0, duration)
	await tween.finished
	$Overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
