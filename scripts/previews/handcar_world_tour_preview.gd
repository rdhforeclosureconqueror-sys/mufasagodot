extends Node3D

# Standalone visual prototype only.
# Open res://scenes/previews/handcar_world_tour_preview.tscn and Run Current Scene.
# SPACE = one simulated push-up/handcar pump, A = autoplay, R = reset, C = camera view.

const MAX_REPS := 60
const TRACK_GAUGE := 1.8
const TRACK_SAMPLE_STEP := 2.0

@export var autoplay := true
@export_range(0.4, 4.0, 0.1) var autoplay_reps_per_second := 1.25

var route: Path3D
var route_curve: Curve3D
var follower: PathFollow3D
var handcar: Node3D
var pump_pivot: Node3D
var follow_camera: Camera3D
var showcase_camera: Camera3D
var rep_label: Label
var zone_label: Label
var status_label: Label
var instructions_label: Label

var course_length := 1.0
var distance_per_rep := 1.0
var current_distance := 0.0
var target_distance := 0.0
var rep_count := 0
var autoplay_accumulator := 0.0
var camera_mode := 0
var pump_tween: Tween

var rail_material: StandardMaterial3D
var sleeper_material: StandardMaterial3D
var cart_red_material: StandardMaterial3D
var cart_gold_material: StandardMaterial3D
var dark_material: StandardMaterial3D
var subway_material: StandardMaterial3D
var subway_light_material: StandardMaterial3D
var city_material: StandardMaterial3D
var city_light_material: StandardMaterial3D
var mountain_material: StandardMaterial3D
var snow_material: StandardMaterial3D

func _ready() -> void:
	name = "HandcarWorldTourPreview"
	_build_materials()
	_build_world_environment()
	_build_route()
	_build_track()
	_build_subway_zone()
	_build_city_zone()
	_build_mountain_zone()
	_build_milestones()
	_build_handcar()
	_build_hud()
	_reset_preview()

func _process(delta: float) -> void:
	if autoplay and rep_count < MAX_REPS:
		autoplay_accumulator += delta
		var interval: float = 1.0 / maxf(autoplay_reps_per_second, 0.1)
		if autoplay_accumulator >= interval:
			autoplay_accumulator -= interval
			simulate_rep()

	current_distance = move_toward(current_distance, target_distance, delta * max(10.0, distance_per_rep * 7.0))
	if follower != null:
		follower.progress = current_distance
	_update_hud()

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE:
			autoplay = false
			simulate_rep()
		KEY_A:
			autoplay = not autoplay
			autoplay_accumulator = 0.0
		KEY_R:
			_reset_preview()
		KEY_C:
			_toggle_camera()

func simulate_rep() -> void:
	if rep_count >= MAX_REPS:
		return
	rep_count += 1
	target_distance = min(course_length, float(rep_count) * distance_per_rep)
	_animate_pump()

func _reset_preview() -> void:
	rep_count = 0
	current_distance = 0.0
	target_distance = 0.0
	autoplay_accumulator = 0.0
	if follower != null:
		follower.progress = 0.0
	if pump_pivot != null:
		pump_pivot.rotation_degrees = Vector3(0.0, 0.0, -18.0)
	_update_hud()

func _toggle_camera() -> void:
	camera_mode = (camera_mode + 1) % 2
	if follow_camera != null:
		follow_camera.current = camera_mode == 0
	if showcase_camera != null:
		showcase_camera.current = camera_mode == 1

func _build_materials() -> void:
	rail_material = _material(Color("#4f5661"), 0.85, 0.28)
	sleeper_material = _material(Color("#4a2c1a"), 0.0, 0.82)
	cart_red_material = _material(Color("#7b1118"), 0.62, 0.3)
	cart_gold_material = _material(Color("#d7a928"), 0.78, 0.24, Color("#5b3900"), 0.9)
	dark_material = _material(Color("#090b11"), 0.28, 0.5)
	subway_material = _material(Color("#151a23"), 0.18, 0.72)
	subway_light_material = _material(Color("#0d1820"), 0.0, 0.35, Color("#26d6ff"), 5.2)
	city_material = _material(Color("#111725"), 0.45, 0.48)
	city_light_material = _material(Color("#171105"), 0.0, 0.36, Color("#ffbf31"), 4.3)
	mountain_material = _material(Color("#263142"), 0.0, 0.94)
	snow_material = _material(Color("#dce9f3"), 0.0, 0.9)

func _material(color: Color, metallic := 0.0, roughness := 0.6, emission := Color(0, 0, 0), emission_energy := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = emission_energy
	return material

func _build_world_environment() -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.72
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#08101e")
	sky_material.sky_horizon_color = Color("#6e4050")
	sky_material.ground_bottom_color = Color("#05070b")
	sky_material.ground_horizon_color = Color("#18243a")
	sky.sky_material = sky_material
	environment.sky = sky
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "RouteSun"
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)

func _build_route() -> void:
	route = Path3D.new()
	route.name = "WorldTourRoute"
	route_curve = Curve3D.new()
	route_curve.bake_interval = 0.45
	route_curve.add_point(Vector3(0.0, 1.2, 8.0))
	route_curve.add_point(Vector3(0.0, 1.2, -28.0))
	route_curve.add_point(Vector3(3.5, 2.0, -58.0))
	route_curve.add_point(Vector3(-4.0, 4.0, -92.0))
	route_curve.add_point(Vector3(4.5, 6.5, -128.0))
	route_curve.add_point(Vector3(0.0, 9.5, -172.0))
	route.curve = route_curve
	add_child(route)
	course_length = route_curve.get_baked_length()
	distance_per_rep = course_length / float(MAX_REPS)

func _build_track() -> void:
	var track_root := Node3D.new()
	track_root.name = "Track"
	add_child(track_root)
	var d := 0.0
	while d < course_length - 0.25:
		var d2: float = minf(d + TRACK_SAMPLE_STEP, course_length)
		var p1 := route_curve.sample_baked(d, true)
		var p2 := route_curve.sample_baked(d2, true)
		var direction := (p2 - p1).normalized()
		if direction.length() < 0.001:
			d += TRACK_SAMPLE_STEP
			continue
		var right := Vector3.UP.cross(direction).normalized()
		if right.length() < 0.001:
			right = Vector3.RIGHT
		var midpoint := (p1 + p2) * 0.5
		var length := p1.distance_to(p2) + 0.12
		_add_oriented_box(track_root, "RailL", Vector3(0.11, 0.12, length), midpoint - right * (TRACK_GAUGE * 0.5), direction, rail_material)
		_add_oriented_box(track_root, "RailR", Vector3(0.11, 0.12, length), midpoint + right * (TRACK_GAUGE * 0.5), direction, rail_material)
		_add_oriented_box(track_root, "Sleeper", Vector3(2.45, 0.11, 0.28), p1 - Vector3(0, 0.08, 0), direction, sleeper_material)
		d += TRACK_SAMPLE_STEP

func _build_subway_zone() -> void:
	var root := Node3D.new()
	root.name = "Zone_Subway"
	add_child(root)
	_add_box(root, "TunnelFloor", Vector3(11.0, 0.5, 58.0), Vector3(0, -0.15, -18), subway_material)
	_add_box(root, "TunnelLeft", Vector3(0.5, 7.0, 58.0), Vector3(-5.25, 3.25, -18), subway_material)
	_add_box(root, "TunnelRight", Vector3(0.5, 7.0, 58.0), Vector3(5.25, 3.25, -18), subway_material)
	_add_box(root, "TunnelRoof", Vector3(11.0, 0.45, 58.0), Vector3(0, 6.7, -18), subway_material)
	for z in range(4, -47, -7):
		_add_box(root, "CeilingLight", Vector3(3.6, 0.08, 0.45), Vector3(0, 6.42, float(z)), subway_light_material)
		_add_box(root, "WallGlowL", Vector3(0.06, 0.18, 3.0), Vector3(-4.96, 2.8, float(z)), subway_light_material)
		_add_box(root, "WallGlowR", Vector3(0.06, 0.18, 3.0), Vector3(4.96, 2.8, float(z)), subway_light_material)
	_add_zone_title(root, "SUBWAY GRIND", Vector3(0, 4.5, 3.0), Color("#34d7ff"))

func _build_city_zone() -> void:
	var root := Node3D.new()
	root.name = "Zone_City"
	add_child(root)
	_add_box(root, "Viaduct", Vector3(8.0, 0.8, 72.0), Vector3(0, 0.4, -86), dark_material)
	var heights := [10.0, 16.0, 22.0, 13.0, 26.0, 18.0, 30.0, 15.0, 24.0, 19.0]
	for i in range(heights.size()):
		var side := -1.0 if i % 2 == 0 else 1.0
		var z := -52.0 - float(i) * 7.0
		var x := side * (8.0 + float(i % 3) * 2.4)
		var height: float = heights[i]
		_add_box(root, "Tower", Vector3(5.2, height, 5.2), Vector3(x, height * 0.5, z), city_material)
		for window_y in range(3, int(height) - 1, 3):
			var window_x := x - side * 2.63
			_add_box(root, "WindowStrip", Vector3(0.05, 0.55, 3.7), Vector3(window_x, float(window_y), z), city_light_material)
	_add_zone_title(root, "CITY BREAKOUT", Vector3(0, 13.0, -79.0), Color("#ffd04c"))

func _build_mountain_zone() -> void:
	var root := Node3D.new()
	root.name = "Zone_Mountain"
	add_child(root)
	for i in range(9):
		var side := -1.0 if i % 2 == 0 else 1.0
		var z := -116.0 - float(i) * 8.0
		var x := side * (11.0 + float(i % 3) * 4.5)
		var height := 14.0 + float((i * 5) % 13)
		_add_cone(root, "Mountain", 8.0 + float(i % 3) * 2.0, height, Vector3(x, height * 0.5 - 0.5, z), mountain_material)
		_add_cone(root, "SnowCap", 3.0 + float(i % 2), height * 0.26, Vector3(x, height - 1.7, z), snow_material)
	var finish_sun := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 5.0
	sphere.height = 10.0
	finish_sun.mesh = sphere
	finish_sun.material_override = _material(Color("#ff9c31"), 0.0, 0.4, Color("#ff6a19"), 4.2)
	finish_sun.position = Vector3(-18, 23, -181)
	root.add_child(finish_sun)
	_add_zone_title(root, "MOUNTAIN CLIMB", Vector3(0, 17.0, -139.0), Color("#ffb353"))

func _build_milestones() -> void:
	var root := Node3D.new()
	root.name = "RepMilestones"
	add_child(root)
	for reps in [20, 30, 40, 50, 60]:
		var distance: float = minf(course_length, float(reps) * distance_per_rep)
		var p := route_curve.sample_baked(distance, true)
		var p2 := route_curve.sample_baked(min(distance + 0.7, course_length), true)
		var direction := (p2 - p).normalized()
		if direction.length() < 0.001:
			direction = Vector3.FORWARD
		var right := Vector3.UP.cross(direction).normalized()
		_add_oriented_box(root, "GateLeft", Vector3(0.18, 4.4, 0.18), p - right * 2.0 + Vector3(0, 2.1, 0), direction, cart_gold_material)
		_add_oriented_box(root, "GateRight", Vector3(0.18, 4.4, 0.18), p + right * 2.0 + Vector3(0, 2.1, 0), direction, cart_gold_material)
		_add_oriented_box(root, "GateTop", Vector3(4.15, 0.22, 0.22), p + Vector3(0, 4.25, 0), direction, cart_gold_material)
		var label := Label3D.new()
		label.text = "%d REPS" % reps if reps < 60 else "60 REPS · FINISH"
		label.font_size = 42
		label.modulate = Color("#ffd24a")
		label.outline_size = 7
		label.outline_modulate = Color("#160b00")
		label.position = p + Vector3(0, 4.85, 0)
		root.add_child(label)

func _build_handcar() -> void:
	follower = PathFollow3D.new()
	follower.name = "HandcarFollower"
	follower.loop = false
	follower.rotation_mode = PathFollow3D.ROTATION_ORIENTED
	route.add_child(follower)

	handcar = Node3D.new()
	handcar.name = "Handcar"
	follower.add_child(handcar)
	_add_box(handcar, "Deck", Vector3(2.55, 0.28, 2.05), Vector3(0, 0.52, 0), cart_red_material)
	_add_box(handcar, "GoldTrim", Vector3(2.7, 0.08, 2.18), Vector3(0, 0.7, 0), cart_gold_material)
	_add_box(handcar, "PumpBase", Vector3(0.35, 1.65, 0.35), Vector3(0, 1.4, 0), cart_gold_material)

	for x in [-0.96, 0.96]:
		for z in [-0.72, 0.72]:
			_add_wheel(handcar, Vector3(x, 0.28, z))

	pump_pivot = Node3D.new()
	pump_pivot.name = "PumpHandlePivot"
	pump_pivot.position = Vector3(0, 2.22, 0)
	pump_pivot.rotation_degrees = Vector3(0, 0, -18)
	handcar.add_child(pump_pivot)
	_add_box(pump_pivot, "PumpBeam", Vector3(3.5, 0.16, 0.18), Vector3.ZERO, cart_gold_material)
	_add_box(pump_pivot, "GripLeft", Vector3(0.18, 0.5, 0.28), Vector3(-1.72, -0.16, 0), dark_material)
	_add_box(pump_pivot, "GripRight", Vector3(0.18, 0.5, 0.28), Vector3(1.72, 0.16, 0), dark_material)

	var emblem := Label3D.new()
	emblem.text = "BEAST RAIL"
	emblem.font_size = 28
	emblem.modulate = Color("#ffd24a")
	emblem.outline_size = 5
	emblem.position = Vector3(0, 1.0, 1.04)
	emblem.rotation_degrees = Vector3(0, 180, 0)
	handcar.add_child(emblem)

	follow_camera = Camera3D.new()
	follow_camera.name = "FollowCamera"
	follow_camera.position = Vector3(0, 4.6, 8.2)
	follow_camera.rotation_degrees = Vector3(-16.0, 0, 0)
	follow_camera.fov = 72.0
	follow_camera.current = true
	handcar.add_child(follow_camera)

	showcase_camera = Camera3D.new()
	showcase_camera.name = "ShowcaseCamera"
	showcase_camera.position = Vector3(13.0, 16.0, 22.0)
	showcase_camera.rotation_degrees = Vector3(-23.0, 28.0, 0)
	showcase_camera.fov = 68.0
	showcase_camera.current = false
	add_child(showcase_camera)

func _add_wheel(parent: Node3D, position: Vector3) -> void:
	var wheel := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.34
	mesh.bottom_radius = 0.34
	mesh.height = 0.18
	mesh.radial_segments = 18
	wheel.mesh = mesh
	wheel.material_override = dark_material
	wheel.position = position
	wheel.rotation_degrees = Vector3(0, 0, 90)
	parent.add_child(wheel)

func _animate_pump() -> void:
	if pump_pivot == null:
		return
	if pump_tween != null and pump_tween.is_valid():
		pump_tween.kill()
	pump_tween = create_tween()
	pump_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pump_tween.tween_property(pump_pivot, "rotation_degrees", Vector3(0, 0, 18), 0.14)
	pump_tween.tween_property(pump_pivot, "rotation_degrees", Vector3(0, 0, -18), 0.14)

func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "PreviewHUD"
	add_child(canvas)

	var panel := ColorRect.new()
	panel.color = Color(0.02, 0.025, 0.04, 0.88)
	panel.position = Vector2(18, 18)
	panel.size = Vector2(430, 154)
	canvas.add_child(panel)

	var title := Label.new()
	title.text = "HANDCAR WORLD TOUR · PREVIEW"
	title.position = Vector2(34, 30)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("#ffd24a"))
	canvas.add_child(title)

	rep_label = Label.new()
	rep_label.position = Vector2(34, 66)
	rep_label.add_theme_font_size_override("font_size", 26)
	canvas.add_child(rep_label)

	zone_label = Label.new()
	zone_label.position = Vector2(34, 102)
	zone_label.add_theme_font_size_override("font_size", 20)
	zone_label.add_theme_color_override("font_color", Color("#ff5a45"))
	canvas.add_child(zone_label)

	status_label = Label.new()
	status_label.position = Vector2(34, 132)
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.add_theme_color_override("font_color", Color("#b9c6d8"))
	canvas.add_child(status_label)

	instructions_label = Label.new()
	instructions_label.text = "SPACE = PUSH-UP REP    A = AUTOPLAY    R = RESET    C = CAMERA"
	instructions_label.position = Vector2(20, 690)
	instructions_label.add_theme_font_size_override("font_size", 18)
	instructions_label.add_theme_color_override("font_color", Color("#f3f4f6"))
	canvas.add_child(instructions_label)

func _update_hud() -> void:
	if rep_label == null:
		return
	rep_label.text = "REPS  %02d / %02d" % [rep_count, MAX_REPS]
	zone_label.text = _zone_name(current_distance)
	if rep_count >= MAX_REPS:
		status_label.text = "FINISH CLEARED · 60-REP ROUTE COMPLETE"
	else:
		var next_target := 20
		for milestone in [20, 30, 40, 50, 60]:
			if rep_count < milestone:
				next_target = milestone
				break
		status_label.text = "%s · NEXT GATE %d REPS" % ["AUTOPLAY ON" if autoplay else "MANUAL REP MODE", next_target]

func _zone_name(distance: float) -> String:
	var ratio: float = distance / maxf(course_length, 0.001)
	if ratio < 0.34:
		return "ZONE 1 · SUBWAY GRIND"
	if ratio < 0.68:
		return "ZONE 2 · CITY BREAKOUT"
	return "ZONE 3 · MOUNTAIN CLIMB"

func _add_zone_title(parent: Node3D, text_value: String, position: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.text = text_value
	label.font_size = 72
	label.modulate = color
	label.outline_size = 10
	label.outline_modulate = Color("#05070b")
	label.position = position
	parent.add_child(label)

func _add_box(parent: Node3D, node_name: String, size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.name = node_name
	node.mesh = mesh
	node.material_override = material
	node.position = position
	parent.add_child(node)
	return node

func _add_oriented_box(parent: Node3D, node_name: String, size: Vector3, position: Vector3, direction: Vector3, material: Material) -> MeshInstance3D:
	var node := _add_box(parent, node_name, size, position, material)
	var safe_direction := direction.normalized()
	if safe_direction.length() < 0.001:
		safe_direction = Vector3.FORWARD
	node.basis = Basis.looking_at(safe_direction, Vector3.UP)
	return node

func _add_cone(parent: Node3D, node_name: String, radius: float, height: float, position: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	node.name = node_name
	node.mesh = mesh
	node.material_override = material
	node.position = position
	parent.add_child(node)
	return node