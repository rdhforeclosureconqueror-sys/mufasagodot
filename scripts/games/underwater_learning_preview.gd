class_name UnderwaterLearningPreview
extends Node3D

signal preview_state_changed(state: Dictionary)

const REEF_ORIGIN := Vector3(0.0, 0.0, -125.0)
const REEF_SIZE := Vector3(34.0, 0.3, 52.0)
const REEF_SPAWN_LOCAL := Vector3(0.0, 0.76, 22.0)
const GYM_ENTRY_POSITION := Vector3(6.1, 0.10, -4.8)
const GYM_RETURN_POSITION := Vector3(4.2, 0.76, -4.0)
const OXYGEN_MAX := 100.0
const OXYGEN_DRAIN_PER_SECOND := 5.0
const OXYGEN_REFILL_PER_SECOND := 38.0

# Eleven rounds cover every make-ten partner from 0 through 10. Reversed facts
# are separate rounds so 9+1 and 1+9 are both practiced.
const PAIR_ROUNDS := [9, 1, 8, 2, 7, 3, 6, 4, 5, 10, 0]
const NUMBER_POSITIONS := {
	0: Vector3(-13.0, 1.0, -19.0),
	1: Vector3(10.5, 1.0, 18.0),
	2: Vector3(-11.5, 1.0, 13.0),
	3: Vector3(12.5, 1.0, 8.0),
	4: Vector3(-8.0, 1.0, 4.0),
	5: Vector3(0.0, 1.0, -1.0),
	6: Vector3(10.5, 1.0, -5.0),
	7: Vector3(-12.0, 1.0, -9.0),
	8: Vector3(8.0, 1.0, -14.0),
	9: Vector3(-5.0, 1.0, -19.0),
	10: Vector3(13.0, 1.0, -22.0)
}

var state: Dictionary = {
	"reefReady": false,
	"status": "IDLE",
	"controlMode": "EXISTING_LOCOMOTION",
	"swimAnimation": "PENDING",
	"oxygen": OXYGEN_MAX,
	"inAirBubble": false,
	"roundIndex": 0,
	"roundTotal": PAIR_ROUNDS.size(),
	"treasure": 0,
	"lastEvent": "NONE",
	"firstFailure": "NONE"
}

var _player: GymPlayerController
var _reef_root: Node3D
var _entry_area: Area3D
var _return_area: Area3D
var _hud_layer: CanvasLayer
var _hud_label: Label
var _last_safe_global := Vector3.ZERO
var _number_orbs: Dictionary = {}
var _fish: Array[Node3D] = []
var _fish_bases: Array[Vector3] = []
var _fish_time := 0.0
var _air_contacts := 0

func _ready() -> void:
	name = "UnderwaterLearningPreview"
	_player = _resolve_player()
	_build_entry_gate()
	_build_reef_world()
	_build_hud()
	_validate_structure()
	set_process(true)
	_publish()

func _process(delta: float) -> void:
	_animate_fish(delta)
	if str(state.get("status", "IDLE")) != "ACTIVE":
		return
	if _player == null or not is_instance_valid(_player):
		_set_first_failure("REEF_PLAYER_BIND", "PLAYER_MISSING_DURING_PREVIEW")
		return
	if bool(state.get("inAirBubble", false)):
		state["oxygen"] = minf(OXYGEN_MAX, float(state.get("oxygen", OXYGEN_MAX)) + OXYGEN_REFILL_PER_SECOND * delta)
	else:
		state["oxygen"] = maxf(0.0, float(state.get("oxygen", OXYGEN_MAX)) - OXYGEN_DRAIN_PER_SECOND * delta)
	if float(state.get("oxygen", 0.0)) <= 0.0:
		_soft_air_reset()
	if _player.global_position.y < -3.0:
		_set_first_failure("REEF_PLAYER_FELL", "PLAYER_BELOW_SEABED")
		_soft_air_reset()
	_update_hud()

func diagnostic_snapshot() -> Dictionary:
	return state.duplicate(true)

func enter_preview_for_test() -> bool:
	return _enter_reef()

func _resolve_player() -> GymPlayerController:
	var current_scene := get_tree().current_scene
	if current_scene != null:
		var current_player := current_scene.get_node_or_null("player") as GymPlayerController
		if current_player != null:
			return current_player
	return get_tree().root.find_child("player", true, false) as GymPlayerController

func _build_entry_gate() -> void:
	var gate := Node3D.new()
	gate.name = "UnderwaterLearningEntryGate"
	gate.position = GYM_ENTRY_POSITION
	add_child(gate)

	var pad := MeshInstance3D.new()
	pad.name = "UnderwaterPortalPad"
	var pad_mesh := CylinderMesh.new()
	pad_mesh.top_radius = 1.35
	pad_mesh.bottom_radius = 1.35
	pad_mesh.height = 0.10
	pad_mesh.material = _material(Color(0.01, 0.10, 0.15), Color(0.0, 0.9, 0.75), 3.2)
	pad.mesh = pad_mesh
	gate.add_child(pad)

	var halo := MeshInstance3D.new()
	halo.name = "UnderwaterPortalHalo"
	var halo_mesh := TorusMesh.new()
	halo_mesh.inner_radius = 1.05
	halo_mesh.outer_radius = 1.25
	halo_mesh.material = _material(Color(0.02, 0.10, 0.16), Color(0.15, 0.9, 1.0), 4.0)
	halo.mesh = halo_mesh
	halo.position = Vector3(0.0, 1.45, 0.0)
	halo.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	gate.add_child(halo)

	var sign := Label3D.new()
	sign.name = "UnderwaterLearningSign"
	sign.text = "UNDERWATER LEARNING\nMAKE 10 TREASURE HUNT"
	sign.position = Vector3(0.0, 2.75, 0.0)
	sign.font_size = 60
	sign.outline_size = 10
	sign.modulate = Color.WHITE
	sign.outline_modulate = Color(0.0, 0.06, 0.10)
	sign.pixel_size = 0.0042
	gate.add_child(sign)

	_entry_area = Area3D.new()
	_entry_area.name = "UnderwaterLearningEntryArea"
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 1.25
	shape.height = 1.9
	collision.shape = shape
	collision.position.y = 0.9
	_entry_area.add_child(collision)
	gate.add_child(_entry_area)
	_entry_area.body_entered.connect(_on_entry_body_entered)

func _build_reef_world() -> void:
	_reef_root = Node3D.new()
	_reef_root.name = "UnderwaterLearningReef"
	_reef_root.position = REEF_ORIGIN
	add_child(_reef_root)

	var sand := _material(Color(0.78, 0.68, 0.46), Color(0.10, 0.075, 0.035), 0.18)
	var rock := _material(Color(0.08, 0.12, 0.14), Color(0.0, 0.12, 0.14), 0.25)
	var reef_blue := _material(Color(0.04, 0.24, 0.28), Color(0.0, 0.38, 0.45), 0.55)
	var coral := _material(Color(0.55, 0.12, 0.22), Color(0.55, 0.04, 0.20), 0.9)
	var seaweed := _material(Color(0.02, 0.26, 0.12), Color(0.0, 0.32, 0.16), 0.45)

	_static_box("ReefFloor", REEF_SIZE, Vector3(0.0, -0.15, 0.0), sand, _reef_root)
	_static_box("ReefLeftBoundary", Vector3(0.7, 4.0, 52.0), Vector3(-17.0, 2.0, 0.0), rock, _reef_root)
	_static_box("ReefRightBoundary", Vector3(0.7, 4.0, 52.0), Vector3(17.0, 2.0, 0.0), rock, _reef_root)
	_static_box("ReefFarBoundary", Vector3(34.0, 4.0, 0.7), Vector3(0.0, 2.0, -26.0), rock, _reef_root)
	_static_box("ReefNearBoundary", Vector3(34.0, 4.0, 0.7), Vector3(0.0, 2.0, 26.0), rock, _reef_root)

	# A translucent water ceiling and side veils make the distant world read as
	# underwater without changing the gym's global WorldEnvironment.
	_visual_box("WaterCeiling", Vector3(34.0, 0.08, 52.0), Vector3(0.0, 7.0, 0.0), _water_material(0.30), _reef_root)
	_visual_box("WaterVeilLeft", Vector3(0.05, 10.0, 52.0), Vector3(-16.5, 4.5, 0.0), _water_material(0.20), _reef_root)
	_visual_box("WaterVeilRight", Vector3(0.05, 10.0, 52.0), Vector3(16.5, 4.5, 0.0), _water_material(0.20), _reef_root)

	for rock_data in [
		[Vector3(-11.0, 0.9, 18.0), Vector3(3.5, 1.8, 2.8)],
		[Vector3(11.5, 1.2, 13.0), Vector3(3.0, 2.4, 3.2)],
		[Vector3(-9.0, 1.0, -3.0), Vector3(4.2, 2.0, 2.5)],
		[Vector3(12.0, 1.3, -12.0), Vector3(3.2, 2.6, 3.2)],
		[Vector3(-12.5, 1.2, -20.0), Vector3(3.0, 2.4, 3.0)]
	]:
		_static_box("ReefRock", rock_data[1], rock_data[0], rock, _reef_root)

	for coral_pos in [Vector3(-13.0, 0.7, 8.0), Vector3(7.0, 0.7, 14.0), Vector3(-4.0, 0.7, -11.0), Vector3(11.0, 0.7, -20.0)]:
		_add_coral(coral_pos, coral)

	for seaweed_pos in [
		Vector3(-15.0, 1.0, 20.0), Vector3(-14.0, 1.0, 2.0), Vector3(-15.0, 1.0, -15.0),
		Vector3(15.0, 1.0, 16.0), Vector3(14.0, 1.0, -2.0), Vector3(15.0, 1.0, -18.0),
		Vector3(-6.0, 1.0, 10.0), Vector3(6.0, 1.0, -7.0)
	]:
		_add_seaweed(seaweed_pos, seaweed)

	_build_air_bubble(Vector3(-12.0, 0.0, 17.0), "AIR 1")
	_build_air_bubble(Vector3(12.0, 0.0, 1.0), "AIR 2")
	_build_air_bubble(Vector3(-10.0, 0.0, -16.0), "AIR 3")
	_build_number_pearls()
	_build_treasure_chest()
	_build_return_gate()
	_build_fish()
	_build_unicorn_visual()
	_build_lighting(reef_blue)

	var title := Label3D.new()
	title.name = "ReefTitle"
	title.text = "MAKE 10 REEF\nFIND THE PARTNER • COLLECT THE TREASURE"
	title.position = Vector3(0.0, 5.2, 23.5)
	title.font_size = 66
	title.outline_size = 10
	title.modulate = Color.WHITE
	title.outline_modulate = Color(0.0, 0.08, 0.12)
	title.pixel_size = 0.004
	_reef_root.add_child(title)

func _build_number_pearls() -> void:
	for value in range(11):
		var orb := Area3D.new()
		orb.name = "NumberPearl_%02d" % value
		orb.position = NUMBER_POSITIONS[value]
		_reef_root.add_child(orb)

		var mesh_instance := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		var pearl_material := _material(Color(0.04, 0.36, 0.46), Color(0.0, 0.95, 1.0), 2.4)
		sphere.material = pearl_material
		mesh_instance.mesh = sphere
		mesh_instance.scale = Vector3(0.60, 0.60, 0.60)
		orb.add_child(mesh_instance)

		var label := Label3D.new()
		label.text = str(value)
		label.position = Vector3(0.0, 1.15, 0.0)
		label.font_size = 96
		label.outline_size = 12
		label.modulate = Color(1.0, 0.92, 0.35)
		label.outline_modulate = Color(0.0, 0.05, 0.08)
		label.pixel_size = 0.0045
		orb.add_child(label)

		var collision := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 0.95
		collision.shape = shape
		orb.add_child(collision)
		orb.body_entered.connect(_on_number_pearl_entered.bind(value, orb))
		_number_orbs[value] = orb

func _build_air_bubble(local_position: Vector3, bubble_name: String) -> void:
	var area := Area3D.new()
	area.name = bubble_name.replace(" ", "")
	area.position = local_position
	_reef_root.add_child(area)

	var dome := MeshInstance3D.new()
	var dome_mesh := SphereMesh.new()
	dome_mesh.material = _bubble_material()
	dome.mesh = dome_mesh
	dome.scale = Vector3(2.2, 2.2, 2.2)
	dome.position.y = 1.65
	area.add_child(dome)

	var label := Label3D.new()
	label.text = "%s\nSAFE AIR" % bubble_name
	label.position = Vector3(0.0, 3.8, 0.0)
	label.font_size = 48
	label.outline_size = 8
	label.modulate = Color.WHITE
	label.pixel_size = 0.004
	area.add_child(label)

	for bubble_index in range(7):
		var bubble := MeshInstance3D.new()
		var bubble_mesh := SphereMesh.new()
		bubble_mesh.material = _bubble_material()
		bubble.mesh = bubble_mesh
		var size := 0.12 + float(bubble_index % 3) * 0.05
		bubble.scale = Vector3(size, size, size)
		bubble.position = Vector3(sin(float(bubble_index) * 2.1) * 0.45, 0.25 + float(bubble_index) * 0.55, cos(float(bubble_index) * 1.7) * 0.35)
		area.add_child(bubble)

	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 2.25
	collision.shape = shape
	collision.position.y = 1.65
	area.add_child(collision)
	area.body_entered.connect(_on_air_bubble_entered.bind(local_position))
	area.body_exited.connect(_on_air_bubble_exited)

func _build_treasure_chest() -> void:
	var chest := Node3D.new()
	chest.name = "Make10TreasureChest"
	chest.position = Vector3(0.0, 0.55, -23.0)
	_reef_root.add_child(chest)
	var gold := _material(Color(0.38, 0.20, 0.03), Color(1.0, 0.52, 0.02), 1.8)
	_visual_box("ChestBase", Vector3(2.4, 1.0, 1.4), Vector3.ZERO, gold, chest)
	_visual_box("ChestLid", Vector3(2.5, 0.45, 1.5), Vector3(0.0, 0.72, 0.0), gold, chest)
	var label := Label3D.new()
	label.text = "MAKE 10\nTREASURE"
	label.position = Vector3(0.0, 2.0, 0.0)
	label.font_size = 48
	label.outline_size = 8
	label.modulate = Color(1.0, 0.92, 0.35)
	label.pixel_size = 0.004
	chest.add_child(label)

func _build_return_gate() -> void:
	var gate := Node3D.new()
	gate.name = "UnderwaterReturnGate"
	gate.position = Vector3(13.0, 0.04, 22.0)
	_reef_root.add_child(gate)

	var pad := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.15
	mesh.bottom_radius = 1.15
	mesh.height = 0.08
	mesh.material = _material(Color(0.12, 0.025, 0.025), Color(1.0, 0.08, 0.05), 2.8)
	pad.mesh = mesh
	gate.add_child(pad)

	var label := Label3D.new()
	label.text = "RETURN\nTO GYM"
	label.position = Vector3(0.0, 1.9, 0.0)
	label.font_size = 58
	label.outline_size = 9
	label.modulate = Color.WHITE
	label.pixel_size = 0.0042
	gate.add_child(label)

	_return_area = Area3D.new()
	_return_area.name = "UnderwaterReturnArea"
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 1.05
	shape.height = 1.8
	collision.shape = shape
	collision.position.y = 0.9
	_return_area.add_child(collision)
	gate.add_child(_return_area)
	_return_area.body_entered.connect(_on_return_body_entered)

func _build_fish() -> void:
	var fish_colors := [
		Color(1.0, 0.38, 0.08), Color(0.25, 0.85, 1.0), Color(0.9, 0.25, 0.75),
		Color(0.45, 0.95, 0.25), Color(1.0, 0.82, 0.12)
	]
	for index in range(5):
		var fish := Node3D.new()
		fish.name = "ReefFish_%02d" % (index + 1)
		var base := Vector3(-10.0 + float(index) * 5.0, 2.4 + float(index % 2), 12.0 - float(index) * 7.0)
		fish.position = base
		_reef_root.add_child(fish)

		var body := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.material = _material(fish_colors[index], fish_colors[index] * 0.25, 0.35)
		body.mesh = sphere
		body.scale = Vector3(0.9, 0.35, 0.35)
		fish.add_child(body)

		var tail := MeshInstance3D.new()
		var tail_mesh := BoxMesh.new()
		tail_mesh.size = Vector3(0.08, 0.65, 0.65)
		tail_mesh.material = sphere.material
		tail.mesh = tail_mesh
		tail.position.x = -0.75
		tail.rotation_degrees.x = 45.0
		fish.add_child(tail)
		_fish.append(fish)
		_fish_bases.append(base)

func _build_unicorn_visual() -> void:
	var unicorn_path := "res://public/generated/unicorn_FINAL_GODOT.glb"

	if not ResourceLoader.exists(unicorn_path):
		_set_first_failure("UNICORN_VISUAL", "GLB_NOT_FOUND")
		return

	var packed := load(unicorn_path) as PackedScene

	if packed == null:
		_set_first_failure("UNICORN_VISUAL", "GLB_LOAD_FAILED")
		return

	var instance = packed.instantiate()

	if not (instance is Node3D):
		if instance != null:
			instance.queue_free()
		_set_first_failure("UNICORN_VISUAL", "ROOT_NOT_NODE3D")
		return

	var unicorn := instance as Node3D
	unicorn.name = "UnderwaterUnicorn"

	# First visual placement beside Nia's reef entrance.
	unicorn.position = Vector3(-5.0, 1.10, 18.0)

	# Blender/STL source is large, so start horse-sized.
	unicorn.scale = Vector3.ONE * 0.028

	_reef_root.add_child(unicorn)

	# Start the first real imported unicorn animation, if one exists.
	var players := unicorn.find_children("*", "AnimationPlayer", true, false)

	if not players.is_empty():
		var animation_player := players[0] as AnimationPlayer

		if animation_player != null:
			for clip_name in animation_player.get_animation_list():
				if String(clip_name).to_upper().contains("RESET"):
					continue

				animation_player.play(clip_name)
				break

func _build_lighting(_reef_material: Material) -> void:
	var key := DirectionalLight3D.new()
	key.name = "FilteredSunlight"
	key.rotation_degrees = Vector3(-62.0, -18.0, 0.0)
	key.light_color = Color(0.38, 0.78, 0.88)
	key.light_energy = 0.72
	key.shadow_enabled = true
	_reef_root.add_child(key)
	for light_position in [Vector3(-11.0, 5.0, 16.0), Vector3(11.0, 5.0, 3.0), Vector3(-8.0, 5.0, -14.0), Vector3(10.0, 5.0, -21.0)]:
		var light := OmniLight3D.new()
		light.position = light_position
		light.light_color = Color(0.12, 0.70, 0.78)
		light.light_energy = 1.45
		light.omni_range = 18.0
		_reef_root.add_child(light)

func _add_coral(pos: Vector3, material: Material) -> void:
	var root := Node3D.new()
	root.position = pos
	_reef_root.add_child(root)
	for branch in range(4):
		var mesh_instance := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.10
		mesh.bottom_radius = 0.22
		mesh.height = 1.4 + float(branch) * 0.18
		mesh.material = material
		mesh_instance.mesh = mesh
		mesh_instance.position = Vector3((float(branch) - 1.5) * 0.28, 0.7 + float(branch) * 0.06, 0.0)
		mesh_instance.rotation_degrees.z = -18.0 + float(branch) * 12.0
		root.add_child(mesh_instance)

func _add_seaweed(pos: Vector3, material: Material) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.05
	mesh.bottom_radius = 0.16
	mesh.height = 2.2
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.position = pos
	_reef_root.add_child(mesh_instance)

func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "UnderwaterLearningHUD"
	_hud_layer.layer = 45
	add_child(_hud_layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 150)
	panel.custom_minimum_size = Vector2(410, 158)
	_hud_layer.add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.005, 0.045, 0.075, 0.92)
	style.border_color = Color(0.0, 0.82, 0.72)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", style)
	_hud_label = Label.new()
	_hud_label.add_theme_font_size_override("font_size", 17)
	_hud_label.add_theme_color_override("font_color", Color.WHITE)
	panel.add_child(_hud_label)
	_hud_layer.visible = false
	_update_hud()

func _validate_structure() -> void:
	if _player == null:
		_set_first_failure("REEF_PLAYER_BIND", "PLAYER_NOT_FOUND")
	elif _reef_root == null:
		_set_first_failure("REEF_BUILD", "REEF_ROOT_MISSING")
	elif _entry_area == null:
		_set_first_failure("REEF_ENTRY", "ENTRY_TRIGGER_MISSING")
	elif _return_area == null:
		_set_first_failure("REEF_RETURN", "RETURN_TRIGGER_MISSING")
	elif _number_orbs.size() != 11:
		_set_first_failure("REEF_NUMBERS", "NUMBER_PEARLS_MISSING")
	else:
		state["reefReady"] = true

func _on_entry_body_entered(body: Node) -> void:
	if body == _player and str(state.get("status", "IDLE")) != "ACTIVE":
		_enter_reef()

func _enter_reef() -> bool:
	if not bool(state.get("reefReady", false)) or _player == null or not is_instance_valid(_player):
		_set_first_failure("REEF_ENTER", "STRUCTURE_NOT_READY")
		return false
	_player.stop_navigation()
	_player.global_position = _reef_root.global_position + REEF_SPAWN_LOCAL
	_player.global_rotation = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	_last_safe_global = _player.global_position
	state["status"] = "ACTIVE"
	state["oxygen"] = OXYGEN_MAX
	state["inAirBubble"] = false
	state["lastEvent"] = "REEF_ENTERED"
	_hud_layer.visible = true
	_update_hud()
	_publish()
	return true

func _on_return_body_entered(body: Node) -> void:
	if body == _player and str(state.get("status", "IDLE")) == "ACTIVE":
		_return_to_gym()

func _return_to_gym() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_player.stop_navigation()
	_player.global_position = GYM_RETURN_POSITION
	_player.global_rotation = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	state["status"] = "IDLE"
	state["inAirBubble"] = false
	state["oxygen"] = OXYGEN_MAX
	state["lastEvent"] = "RETURNED_TO_GYM"
	_hud_layer.visible = false
	_publish()

func _on_air_bubble_entered(body: Node, local_position: Vector3) -> void:
	if body != _player or str(state.get("status", "IDLE")) != "ACTIVE":
		return
	_air_contacts += 1
	state["inAirBubble"] = true
	state["oxygen"] = OXYGEN_MAX
	_last_safe_global = _reef_root.global_position + local_position + Vector3(0.0, 0.76, 0.0)
	state["lastEvent"] = "AIR_BUBBLE_REACHED"
	_update_hud()
	_publish()

func _on_air_bubble_exited(body: Node) -> void:
	if body != _player:
		return
	_air_contacts = maxi(0, _air_contacts - 1)
	state["inAirBubble"] = _air_contacts > 0
	state["lastEvent"] = "AIR_BUBBLE_LEFT"
	_update_hud()
	_publish()

func _on_number_pearl_entered(body: Node, value: int, orb: Area3D) -> void:
	if body != _player or str(state.get("status", "IDLE")) != "ACTIVE":
		return
	var round_index := int(state.get("roundIndex", 0))
	if round_index >= PAIR_ROUNDS.size():
		return
	var first_addend := int(PAIR_ROUNDS[round_index])
	var expected := 10 - first_addend
	if value != expected:
		state["lastEvent"] = "TRY_AGAIN_%d_PLUS_%d" % [first_addend, value]
		_update_hud()
		_publish()
		return
	state["treasure"] = int(state.get("treasure", 0)) + 1
	state["roundIndex"] = round_index + 1
	state["oxygen"] = minf(OXYGEN_MAX, float(state.get("oxygen", OXYGEN_MAX)) + 24.0)
	state["lastEvent"] = "MAKE_10_%d_PLUS_%d" % [first_addend, value]
	_number_orbs.erase(value)
	if is_instance_valid(orb):
		orb.queue_free()
	if int(state.get("roundIndex", 0)) >= PAIR_ROUNDS.size():
		state["lastEvent"] = "MAKE_10_TREASURE_COMPLETE"
	_update_hud()
	_publish()

func _soft_air_reset() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_player.stop_navigation()
	var reset_position := _last_safe_global
	if reset_position == Vector3.ZERO:
		reset_position = _reef_root.global_position + REEF_SPAWN_LOCAL
	_player.global_position = reset_position
	_player.velocity = Vector3.ZERO
	state["oxygen"] = OXYGEN_MAX
	state["lastEvent"] = "AIR_RESET_TO_SAFE_BUBBLE"
	_publish()

func _animate_fish(delta: float) -> void:
	_fish_time += delta
	for index in range(_fish.size()):
		var fish := _fish[index]
		if fish == null or not is_instance_valid(fish):
			continue
		var base := _fish_bases[index]
		fish.position = base + Vector3(sin(_fish_time * 0.65 + float(index)) * 3.0, sin(_fish_time * 1.1 + float(index)) * 0.25, cos(_fish_time * 0.55 + float(index)) * 2.0)
		fish.rotation.y = _fish_time * 0.35 + float(index)

func _material(albedo: Color, emission: Color, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = 0.66
	if emission != Color.BLACK and emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = emission_energy
	return material

func _water_material(alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.0, 0.35, 0.52, alpha)
	material.roughness = 0.14
	material.emission_enabled = true
	material.emission = Color(0.0, 0.12, 0.18)
	material.emission_energy_multiplier = 0.35
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _bubble_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.55, 0.92, 1.0, 0.18)
	material.roughness = 0.05
	material.emission_enabled = true
	material.emission = Color(0.12, 0.72, 0.95)
	material.emission_energy_multiplier = 0.9
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
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

func _visual_box(node_name: String, size: Vector3, pos: Vector3, material: Material, parent: Node3D) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.position = pos
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	mesh_instance.mesh = mesh
	parent.add_child(mesh_instance)
	return mesh_instance

func _set_first_failure(stage: String, reason: String) -> void:
	if str(state.get("firstFailure", "NONE")) != "NONE":
		return
	state["firstFailure"] = "%s:%s" % [stage, reason]
	push_error("UNDERWATER_LEARNING_FIRST_FAILURE %s" % state["firstFailure"])
	_publish()

func _update_hud() -> void:
	if _hud_label == null:
		return
	var round_index := int(state.get("roundIndex", 0))
	var question := "ALL MAKE-10 PAIRS FOUND!"
	if round_index < PAIR_ROUNDS.size():
		var first_addend := int(PAIR_ROUNDS[round_index])
		question = "Find the pearl: %d + ? = 10" % first_addend
	_hud_label.text = "UNDERWATER MAKE-10 TREASURE HUNT\n%s\nAir: %d%% %s | Treasure: %d/%d\nSwim animation: %s | First failure: %s" % [
		question,
		int(round(float(state.get("oxygen", OXYGEN_MAX)))),
		"• SAFE AIR" if bool(state.get("inAirBubble", false)) else "• FIND AIR BUBBLES",
		int(state.get("treasure", 0)),
		PAIR_ROUNDS.size(),
		str(state.get("swimAnimation", "PENDING")),
		str(state.get("firstFailure", "NONE"))
	]

func _publish() -> void:
	preview_state_changed.emit(diagnostic_snapshot())
