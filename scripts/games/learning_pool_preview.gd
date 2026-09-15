class_name LearningPoolPreview
extends Node3D

signal pool_state_changed(state: Dictionary)

const POOL_WIDTH := 25.0
const POOL_LENGTH := 50.0
const POOL_ORIGIN := Vector3(0.0, 0.0, -105.0)
const POOL_SPAWN_LOCAL := Vector3(0.0, 0.76, 20.0)
const GYM_ENTRY_POSITION := Vector3(0.0, 0.10, 5.15)
const GYM_RETURN_POSITION := Vector3(0.0, 0.76, 3.0)
const WATER_SURFACE_Y := 0.88

var state: Dictionary = {
	"poolReady": false,
	"status": "IDLE",
	"controlMode": "EXISTING_LOCOMOTION",
	"swimAnimation": "PENDING",
	"waterContact": false,
	"poolWidthMeters": POOL_WIDTH,
	"poolLengthMeters": POOL_LENGTH,
	"lastEvent": "NONE",
	"firstFailure": "NONE"
}

var _player: GymPlayerController
var _pool_root: Node3D
var _entry_area: Area3D
var _return_area: Area3D
var _water_area: Area3D
var _hud_layer: CanvasLayer
var _hud_label: Label

func _ready() -> void:
	name = "LearningPoolPreview"
	_player = _resolve_player()
	_build_entry_gate()
	_build_pool_world()
	_build_hud()
	_validate_structure()
	set_process(true)
	_publish()

func _process(_delta: float) -> void:
	if str(state.get("status", "IDLE")) != "IN_POOL":
		return
	if _player == null or not is_instance_valid(_player):
		_set_first_failure("POOL_PLAYER_BIND", "PLAYER_MISSING_DURING_PREVIEW")
		return
	if _player.global_position.y < -3.0:
		_set_first_failure("POOL_PLAYER_FELL", "PLAYER_BELOW_POOL")
		_player.global_position = _pool_root.global_position + POOL_SPAWN_LOCAL
		_player.velocity = Vector3.ZERO
		state["lastEvent"] = "PLAYER_RECOVERED"
		_publish()
	_update_hud()

func diagnostic_snapshot() -> Dictionary:
	return state.duplicate(true)

func enter_pool_for_test() -> bool:
	return _enter_pool()

func return_to_gym_for_test() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	_return_to_gym()
	return true

func _resolve_player() -> GymPlayerController:
	var current_scene := get_tree().current_scene
	if current_scene != null:
		var current_player := current_scene.get_node_or_null("player") as GymPlayerController
		if current_player != null:
			return current_player
	return get_tree().root.find_child("player", true, false) as GymPlayerController

func _build_entry_gate() -> void:
	var gate := Node3D.new()
	gate.name = "LearningPoolEntryGate"
	gate.position = GYM_ENTRY_POSITION
	add_child(gate)

	var pad := MeshInstance3D.new()
	pad.name = "LearningPoolPortalPad"
	var pad_mesh := CylinderMesh.new()
	pad_mesh.top_radius = 1.35
	pad_mesh.bottom_radius = 1.35
	pad_mesh.height = 0.10
	pad_mesh.material = _material(Color(0.015, 0.11, 0.17), Color(0.0, 0.75, 1.0), 2.8)
	pad.mesh = pad_mesh
	gate.add_child(pad)

	var halo := MeshInstance3D.new()
	halo.name = "PortalHalo"
	var halo_mesh := TorusMesh.new()
	halo_mesh.inner_radius = 1.05
	halo_mesh.outer_radius = 1.25
	halo_mesh.material = _material(Color(0.02, 0.12, 0.18), Color(0.1, 0.9, 1.0), 4.0)
	halo.mesh = halo_mesh
	halo.position = Vector3(0.0, 1.45, 0.0)
	halo.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	gate.add_child(halo)

	var sign := Label3D.new()
	sign.name = "LearningPoolSign"
	sign.text = "LEARNING POOL\nSTAGE 1 PREVIEW"
	sign.position = Vector3(0.0, 2.75, 0.0)
	sign.font_size = 66
	sign.outline_size = 10
	sign.modulate = Color.WHITE
	sign.outline_modulate = Color(0.0, 0.08, 0.12)
	sign.pixel_size = 0.0042
	gate.add_child(sign)

	_entry_area = Area3D.new()
	_entry_area.name = "LearningPoolEntryArea"
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 1.25
	shape.height = 1.9
	collision.shape = shape
	collision.position.y = 0.9
	_entry_area.add_child(collision)
	gate.add_child(_entry_area)
	_entry_area.body_entered.connect(_on_entry_body_entered)

func _build_pool_world() -> void:
	_pool_root = Node3D.new()
	_pool_root.name = "OlympicLearningPool"
	_pool_root.position = POOL_ORIGIN
	add_child(_pool_root)

	var tile_white := _material(Color(0.72, 0.82, 0.88), Color.BLACK, 0.0)
	var tile_blue := _material(Color(0.015, 0.16, 0.26), Color(0.0, 0.15, 0.25), 0.3)
	var lane_blue := _material(Color(0.01, 0.22, 0.56), Color(0.0, 0.15, 0.85), 0.8)
	var lane_red := _material(Color(0.75, 0.03, 0.05), Color(0.9, 0.03, 0.04), 1.2)

	# Pool floor: 25 m x 50 m, matching Olympic competition dimensions.
	_static_box("PoolFloor", Vector3(POOL_WIDTH, 0.24, POOL_LENGTH), Vector3(0.0, -0.12, 0.0), tile_blue, _pool_root)

	# Raised deck surrounding the pool.
	_static_box("DeckLeft", Vector3(4.0, 0.22, 58.0), Vector3(-14.5, 1.00, 0.0), tile_white, _pool_root)
	_static_box("DeckRight", Vector3(4.0, 0.22, 58.0), Vector3(14.5, 1.00, 0.0), tile_white, _pool_root)
	_static_box("DeckNear", Vector3(25.0, 0.22, 4.0), Vector3(0.0, 1.00, 27.0), tile_white, _pool_root)
	_static_box("DeckFar", Vector3(25.0, 0.22, 4.0), Vector3(0.0, 1.00, -27.0), tile_white, _pool_root)

	# Pool retaining walls keep the existing CharacterBody inside the preview water.
	_static_box("PoolWallLeft", Vector3(0.35, 1.35, POOL_LENGTH), Vector3(-12.65, 0.56, 0.0), tile_white, _pool_root)
	_static_box("PoolWallRight", Vector3(0.35, 1.35, POOL_LENGTH), Vector3(12.65, 0.56, 0.0), tile_white, _pool_root)
	_static_box("PoolWallNear", Vector3(POOL_WIDTH, 1.35, 0.35), Vector3(0.0, 0.56, 25.15), tile_white, _pool_root)
	_static_box("PoolWallFar", Vector3(POOL_WIDTH, 1.35, 0.35), Vector3(0.0, 0.56, -25.15), tile_white, _pool_root)

	# Translucent water surface. There is deliberately no collision on this mesh;
	# Stage 1 reuses proven ground locomotion so the avatar can wade/run immediately.
	var water_surface := MeshInstance3D.new()
	water_surface.name = "WaterSurface"
	var water_mesh := BoxMesh.new()
	water_mesh.size = Vector3(POOL_WIDTH - 0.4, 0.035, POOL_LENGTH - 0.4)
	var water_material := StandardMaterial3D.new()
	water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_material.albedo_color = Color(0.02, 0.48, 0.82, 0.48)
	water_material.roughness = 0.12
	water_material.metallic = 0.05
	water_material.emission_enabled = true
	water_material.emission = Color(0.0, 0.16, 0.28)
	water_material.emission_energy_multiplier = 0.45
	water_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	water_mesh.material = water_material
	water_surface.mesh = water_mesh
	water_surface.position = Vector3(0.0, WATER_SURFACE_Y, 0.0)
	_pool_root.add_child(water_surface)

	# Ten 2.5 m lanes. Ropes are visual only in this first proof.
	for rope_index in range(1, 10):
		var x := -POOL_WIDTH * 0.5 + float(rope_index) * 2.5
		var rope := MeshInstance3D.new()
		rope.name = "LaneRope_%02d" % rope_index
		var rope_mesh := BoxMesh.new()
		rope_mesh.size = Vector3(0.055, 0.035, POOL_LENGTH - 0.8)
		rope_mesh.material = lane_red if rope_index in [1, 9] else lane_blue
		rope.mesh = rope_mesh
		rope.position = Vector3(x, WATER_SURFACE_Y + 0.035, 0.0)
		_pool_root.add_child(rope)

	# Starting blocks sell the Olympic-pool scale even before swim animations exist.
	for lane_index in range(10):
		var lane_x := -11.25 + float(lane_index) * 2.5
		var block := MeshInstance3D.new()
		block.name = "StartingBlock_%02d" % (lane_index + 1)
		var block_mesh := BoxMesh.new()
		block_mesh.size = Vector3(0.9, 0.45, 0.9)
		block_mesh.material = tile_white
		block.mesh = block_mesh
		block.position = Vector3(lane_x, 1.33, 26.0)
		_pool_root.add_child(block)

	var title := Label3D.new()
	title.name = "PoolTitle"
	title.text = "50 m × 25 m LEARNING POOL\nMOVE FIRST • SWIM ANIMATION NEXT"
	title.position = Vector3(0.0, 4.6, -25.7)
	title.font_size = 80
	title.outline_size = 12
	title.modulate = Color.WHITE
	title.outline_modulate = Color(0.0, 0.08, 0.16)
	title.pixel_size = 0.004
	_pool_root.add_child(title)

	_build_water_area()
	_build_return_gate()
	_build_pool_lighting()

func _build_water_area() -> void:
	_water_area = Area3D.new()
	_water_area.name = "LearningPoolWaterArea"
	_water_area.position = Vector3(0.0, 0.62, 0.0)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(POOL_WIDTH - 0.8, 1.55, POOL_LENGTH - 0.8)
	collision.shape = shape
	_water_area.add_child(collision)
	_pool_root.add_child(_water_area)
	_water_area.body_entered.connect(_on_water_body_entered)
	_water_area.body_exited.connect(_on_water_body_exited)

func _build_return_gate() -> void:
	var gate := Node3D.new()
	gate.name = "PoolReturnGate"
	gate.position = Vector3(-9.6, 0.04, 21.5)
	_pool_root.add_child(gate)

	var pad := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.15
	mesh.bottom_radius = 1.15
	mesh.height = 0.07
	mesh.material = _material(Color(0.12, 0.025, 0.025), Color(1.0, 0.08, 0.05), 2.8)
	pad.mesh = mesh
	gate.add_child(pad)

	var label := Label3D.new()
	label.text = "RETURN\nTO GYM"
	label.position = Vector3(0.0, 1.9, 0.0)
	label.font_size = 62
	label.outline_size = 9
	label.modulate = Color.WHITE
	label.pixel_size = 0.0042
	gate.add_child(label)

	_return_area = Area3D.new()
	_return_area.name = "PoolReturnArea"
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 1.05
	shape.height = 1.8
	collision.shape = shape
	collision.position.y = 0.9
	_return_area.add_child(collision)
	gate.add_child(_return_area)
	_return_area.body_entered.connect(_on_return_body_entered)

func _build_pool_lighting() -> void:
	var key := DirectionalLight3D.new()
	key.name = "PoolSun"
	key.rotation_degrees = Vector3(-58.0, -22.0, 0.0)
	key.light_color = Color(0.82, 0.94, 1.0)
	key.light_energy = 1.25
	key.shadow_enabled = true
	_pool_root.add_child(key)

	for light_position in [Vector3(-9.0, 6.0, 16.0), Vector3(9.0, 6.0, 16.0), Vector3(-9.0, 6.0, -16.0), Vector3(9.0, 6.0, -16.0)]:
		var light := OmniLight3D.new()
		light.position = light_position
		light.light_color = Color(0.65, 0.88, 1.0)
		light.light_energy = 2.0
		light.omni_range = 24.0
		_pool_root.add_child(light)

func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "LearningPoolDebugHUD"
	_hud_layer.layer = 45
	add_child(_hud_layer)

	var panel := PanelContainer.new()
	panel.position = Vector2(18, 150)
	panel.custom_minimum_size = Vector2(370, 142)
	_hud_layer.add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.005, 0.045, 0.075, 0.90)
	style.border_color = Color(0.0, 0.72, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", style)
	_hud_label = Label.new()
	_hud_label.add_theme_font_size_override("font_size", 16)
	_hud_label.add_theme_color_override("font_color", Color.WHITE)
	panel.add_child(_hud_label)
	_hud_layer.visible = false
	_update_hud()

func _validate_structure() -> void:
	if _player == null:
		_set_first_failure("POOL_PLAYER_BIND", "PLAYER_NOT_FOUND")
	elif _pool_root == null:
		_set_first_failure("POOL_BUILD", "POOL_ROOT_MISSING")
	elif _entry_area == null:
		_set_first_failure("POOL_ENTRY", "ENTRY_TRIGGER_MISSING")
	elif _return_area == null:
		_set_first_failure("POOL_RETURN", "RETURN_TRIGGER_MISSING")
	elif _water_area == null:
		_set_first_failure("POOL_WATER", "WATER_TRIGGER_MISSING")
	else:
		state["poolReady"] = true

func _on_entry_body_entered(body: Node) -> void:
	if body == _player and str(state.get("status", "IDLE")) != "IN_POOL":
		_enter_pool()

func _enter_pool() -> bool:
	if not bool(state.get("poolReady", false)) or _player == null or not is_instance_valid(_player):
		_set_first_failure("POOL_ENTER", "STRUCTURE_NOT_READY")
		return false
	_player.stop_navigation()
	_player.global_position = _pool_root.global_position + POOL_SPAWN_LOCAL
	_player.global_rotation = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	state["status"] = "IN_POOL"
	state["lastEvent"] = "POOL_ENTERED"
	_hud_layer.visible = true
	_update_hud()
	_publish()
	return true

func _on_return_body_entered(body: Node) -> void:
	if body == _player and str(state.get("status", "IDLE")) == "IN_POOL":
		_return_to_gym()

func _return_to_gym() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_player.stop_navigation()
	_player.global_position = GYM_RETURN_POSITION
	_player.global_rotation = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	state["status"] = "IDLE"
	state["waterContact"] = false
	state["lastEvent"] = "RETURNED_TO_GYM"
	_hud_layer.visible = false
	_publish()

func _on_water_body_entered(body: Node) -> void:
	if body != _player:
		return
	state["waterContact"] = true
	state["lastEvent"] = "WATER_ENTERED"
	_update_hud()
	_publish()

func _on_water_body_exited(body: Node) -> void:
	if body != _player:
		return
	state["waterContact"] = false
	state["lastEvent"] = "WATER_EXITED"
	_update_hud()
	_publish()

func _material(albedo: Color, emission: Color, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = 0.66
	if emission != Color.BLACK and emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = emission_energy
	return material

func _static_box(node_name: String, size: Vector3, pos: Vector3, material: Material, parent: Node3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	parent.add_child(body)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	mesh_instance.mesh = mesh
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body

func _set_first_failure(stage: String, reason: String) -> void:
	if str(state.get("firstFailure", "NONE")) != "NONE":
		return
	state["firstFailure"] = "%s:%s" % [stage, reason]
	push_error("LEARNING_POOL_FIRST_FAILURE %s" % state["firstFailure"])
	_publish()

func _update_hud() -> void:
	if _hud_label == null:
		return
	var position_text := "n/a"
	if _player != null and is_instance_valid(_player):
		position_text = "(%.1f, %.1f, %.1f)" % [_player.global_position.x, _player.global_position.y, _player.global_position.z]
	_hud_label.text = "LEARNING POOL — STAGE 1\nStatus: %s | Water: %s | Swim anim: %s\nPool: 50m × 25m | Player: %s\nFirst failure: %s" % [
		str(state.get("status", "IDLE")),
		"YES" if bool(state.get("waterContact", false)) else "NO",
		str(state.get("swimAnimation", "PENDING")),
		position_text,
		str(state.get("firstFailure", "NONE"))
	]

func _publish() -> void:
	pool_state_changed.emit(diagnostic_snapshot())
