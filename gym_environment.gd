extends Node3D

const BRAND_RED := Color(0.92, 0.06, 0.08)
const CHARCOAL := Color(0.035, 0.04, 0.05)
const RUBBER := Color(0.055, 0.06, 0.07)
const WALL := Color(0.72, 0.74, 0.76)
const STEEL := Color(0.14, 0.16, 0.18)

var status_label: Label
var phase_label: Label
var mirror_viewport: SubViewport

func _ready() -> void:
	_build_environment()
	_build_status_overlay()

func _material(color: Color, metallic := 0.0, roughness := 0.7, emission := Color.BLACK, emission_energy := 1.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	if emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = emission_energy
	return material

func _box(node_name: String, size: Vector3, pos: Vector3, material: Material, parent: Node = self) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.position = pos
	parent.add_child(mesh_instance)
	return mesh_instance

func _cylinder(node_name: String, radius: float, height: float, pos: Vector3, material: Material, parent: Node = self) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.position = pos
	parent.add_child(mesh_instance)
	return mesh_instance

func _sphere(node_name: String, radius: float, pos: Vector3, material: Material, parent: Node = self) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.position = pos
	parent.add_child(mesh_instance)
	return mesh_instance

func _build_environment() -> void:
	var env_node := WorldEnvironment.new()
	env_node.name = "GymWorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.025, 0.028, 0.035)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.48, 0.52, 0.60)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_node.environment = env
	add_child(env_node)

	var floor_material := _material(RUBBER, 0.0, 0.93)
	var floor_body := StaticBody3D.new()
	floor_body.name = "RubberFloor"
	add_child(floor_body)
	_box("FloorMesh", Vector3(18.0, 0.24, 14.0), Vector3(0, -0.12, 0), floor_material, floor_body)
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(18.0, 0.24, 14.0)
	floor_collision.shape = floor_shape
	floor_collision.position = Vector3(0, -0.12, 0)
	floor_body.add_child(floor_collision)

	var stripe_material := _material(Color(0.095, 0.10, 0.115), 0.0, 0.88)
	for x in range(-8, 9):
		if x % 2 == 0:
			_box("FloorMatStripe_%d" % x, Vector3(0.025, 0.008, 13.5), Vector3(float(x), 0.01, 0), stripe_material)

	var ceiling_material := _material(CHARCOAL, 0.15, 0.82)
	_box("CharcoalCeiling", Vector3(18.0, 0.25, 14.0), Vector3(0, 5.9, 0), ceiling_material)
	var wall_material := _material(WALL, 0.0, 0.78)
	_box("BrandWall", Vector3(18.0, 6.0, 0.25), Vector3(0, 2.9, -7.0), wall_material)
	_box("RightWall", Vector3(0.25, 6.0, 14.0), Vector3(9.0, 2.9, 0), wall_material)
	_box("EntryWall", Vector3(18.0, 6.0, 0.25), Vector3(0, 2.9, 7.0), _material(Color(0.60, 0.62, 0.65), 0.0, 0.75))

	_build_ceiling_lights()
	_build_mirror_wall()
	_build_brand_wall()
	_build_test_zone()
	_build_power_rack(Vector3(5.9, 0, -3.7))
	_build_bench(Vector3(5.9, 0, -1.0))
	_build_dumbbell_rack(Vector3(5.9, 0, 3.0))
	_build_mat_area(Vector3(2.6, 0, 3.7))
	_build_scoreboard()
	_build_camera()

func _build_ceiling_lights() -> void:
	var panel_material := _material(Color(0.9, 0.94, 1.0), 0.0, 0.15, Color(0.9, 0.95, 1.0), 5.0)
	for x in [-5.5, 0.0, 5.5]:
		for z in [-3.8, 0.0, 3.8]:
			_box("CeilingLight", Vector3(2.6, 0.08, 0.65), Vector3(x, 5.72, z), panel_material)
			var light := OmniLight3D.new()
			light.name = "CeilingOmni"
			light.position = Vector3(x, 5.45, z)
			light.light_color = Color(0.86, 0.91, 1.0)
			light.light_energy = 1.45
			light.omni_range = 7.0
			light.shadow_enabled = x == 0.0 and z == 0.0
			add_child(light)

	var key := DirectionalLight3D.new()
	key.name = "GymKeyLight"
	key.rotation_degrees = Vector3(-55, -25, 0)
	key.light_color = Color(1.0, 0.93, 0.86)
	key.light_energy = 0.65
	key.shadow_enabled = true
	add_child(key)

func _build_mirror_wall() -> void:
	var mirror_frame := Node3D.new()
	mirror_frame.name = "MirrorWall"
	add_child(mirror_frame)
	var frame_mat := _material(Color(0.035, 0.04, 0.045), 0.75, 0.22)
	var mirror_mat := _material(Color(0.52, 0.60, 0.68), 0.9, 0.08)

	mirror_viewport = SubViewport.new()
	mirror_viewport.name = "MirrorViewport"
	mirror_viewport.size = Vector2i(1024, 512)
	mirror_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	mirror_viewport.transparent_bg = false
	mirror_viewport.own_world_3d = false
	add_child(mirror_viewport)
	var mirror_camera := Camera3D.new()
	mirror_camera.name = "MirrorCamera"
	mirror_camera.position = Vector3(-6.4, 2.0, 4.2)
	mirror_camera.look_at_from_position(mirror_camera.position, Vector3(0, 0.75, 0), Vector3.UP)
	mirror_camera.fov = 48.0
	mirror_camera.cull_mask = 1
	mirror_viewport.add_child(mirror_camera)

	for panel_index in range(4):
		var z := -5.15 + panel_index * 3.45
		_box("MirrorFrame_%d" % panel_index, Vector3(0.16, 4.75, 3.35), Vector3(-8.86, 2.55, z), frame_mat, mirror_frame)
		var panel := _box("MirrorPanel_%d" % panel_index, Vector3(0.08, 4.55, 3.18), Vector3(-8.76, 2.55, z), mirror_mat, mirror_frame)
		panel.layers = 2

	# One functional live mirror surface spans the central panels.
	var live_surface := MeshInstance3D.new()
	live_surface.name = "LiveMirrorSurface"
	var quad := QuadMesh.new()
	quad.size = Vector2(6.65, 4.45)
	var live_mat := StandardMaterial3D.new()
	live_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	live_mat.albedo_texture = mirror_viewport.get_texture()
	live_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = live_mat
	live_surface.mesh = quad
	live_surface.position = Vector3(-8.69, 2.55, 0)
	live_surface.rotation_degrees = Vector3(0, 90, 0)
	live_surface.layers = 2
	mirror_frame.add_child(live_surface)

func _build_brand_wall() -> void:
	var backing := _box("BrandSignBacking", Vector3(8.2, 3.8, 0.16), Vector3(0, 3.0, -6.78), _material(Color(0.025, 0.028, 0.035), 0.25, 0.38))
	var accent := _box("BrandAccent", Vector3(8.4, 0.10, 0.09), Vector3(0, 0.98, -6.65), _material(BRAND_RED, 0.15, 0.3, BRAND_RED, 2.5))
	var label := Label3D.new()
	label.name = "UnleashDaBeastSign"
	label.text = "UNLEASH\nDA\nBEAST"
	label.font_size = 96
	label.outline_size = 12
	label.modulate = Color.WHITE
	label.outline_modulate = Color(0.05, 0.05, 0.06)
	label.position = Vector3(0, 2.55, -6.60)
	label.pixel_size = 0.0045
	label.no_depth_test = false
	add_child(label)
	var sub := Label3D.new()
	sub.name = "BrandTagline"
	sub.text = "TRAIN • TEST • TRANSFORM"
	sub.font_size = 42
	sub.modulate = BRAND_RED
	sub.position = Vector3(0, 1.42, -6.60)
	sub.pixel_size = 0.005
	add_child(sub)

func _build_test_zone() -> void:
	var zone_mat := _material(Color(0.12, 0.13, 0.15), 0.0, 0.92)
	_box("MovementTestZone", Vector3(5.2, 0.025, 4.4), Vector3(-1.7, 0.025, 0.2), zone_mat)
	var line_mat := _material(BRAND_RED, 0.1, 0.45, BRAND_RED, 1.3)
	_box("ZoneLineFront", Vector3(5.2, 0.018, 0.055), Vector3(-1.7, 0.045, 2.4), line_mat)
	_box("ZoneLineBack", Vector3(5.2, 0.018, 0.055), Vector3(-1.7, 0.045, -2.0), line_mat)
	_box("ZoneLineLeft", Vector3(0.055, 0.018, 4.4), Vector3(-4.3, 0.045, 0.2), line_mat)
	_box("ZoneLineRight", Vector3(0.055, 0.018, 4.4), Vector3(0.9, 0.045, 0.2), line_mat)

func _build_power_rack(origin: Vector3) -> void:
	var rack := Node3D.new()
	rack.name = "PowerRack"
	rack.position = origin
	add_child(rack)
	var steel := _material(STEEL, 0.75, 0.28)
	var red := _material(BRAND_RED, 0.45, 0.32)
	for x in [-1.15, 1.15]:
		for z in [-0.9, 0.9]:
			_box("RackPost", Vector3(0.14, 3.2, 0.14), Vector3(x, 1.6, z), steel, rack)
	for z in [-0.9, 0.9]:
		_box("RackTop", Vector3(2.45, 0.14, 0.14), Vector3(0, 3.17, z), red, rack)
	_box("PullupBar", Vector3(2.5, 0.08, 0.08), Vector3(0, 3.42, -0.9), steel, rack)
	var bar := _cylinder("Barbell", 0.045, 3.0, Vector3(0, 2.0, 0), steel, rack)
	bar.rotation_degrees.z = 90
	for x in [-1.38, 1.38]:
		var plate := _cylinder("WeightPlate", 0.38, 0.16, Vector3(x, 2.0, 0), red, rack)
		plate.rotation_degrees.z = 90

func _build_bench(origin: Vector3) -> void:
	var bench := Node3D.new()
	bench.name = "Bench"
	bench.position = origin
	add_child(bench)
	var pad := _material(Color(0.09, 0.095, 0.105), 0.0, 0.72)
	var steel := _material(STEEL, 0.7, 0.3)
	_box("BenchPad", Vector3(0.8, 0.18, 2.4), Vector3(0, 0.72, 0), pad, bench)
	for z in [-0.75, 0.75]:
		_box("BenchLeg", Vector3(0.12, 0.65, 0.12), Vector3(0, 0.34, z), steel, bench)
		_box("BenchFoot", Vector3(1.1, 0.10, 0.18), Vector3(0, 0.05, z), steel, bench)

func _build_dumbbell_rack(origin: Vector3) -> void:
	var rack := Node3D.new()
	rack.name = "DumbbellRack"
	rack.position = origin
	add_child(rack)
	var steel := _material(STEEL, 0.72, 0.3)
	_box("RackShelf", Vector3(3.6, 0.12, 0.65), Vector3(0, 0.75, 0), steel, rack)
	_box("RackBase", Vector3(3.6, 0.12, 0.75), Vector3(0, 0.08, 0), steel, rack)
	for x in [-1.55, 1.55]:
		_box("RackSupport", Vector3(0.12, 0.8, 0.12), Vector3(x, 0.4, 0), steel, rack)
	var weight_mat := _material(Color(0.035, 0.038, 0.045), 0.45, 0.45)
	for i in range(6):
		var dumbbell := Node3D.new()
		dumbbell.name = "Dumbbell_%d" % i
		dumbbell.position = Vector3(-1.35 + i * 0.54, 1.0, 0)
		rack.add_child(dumbbell)
		var handle := _cylinder("Handle", 0.035, 0.34, Vector3.ZERO, steel, dumbbell)
		handle.rotation_degrees.z = 90
		for x in [-0.20, 0.20]:
			var end := _cylinder("Weight", 0.14 + i * 0.008, 0.11, Vector3(x, 0, 0), weight_mat, dumbbell)
			end.rotation_degrees.z = 90

func _build_mat_area(origin: Vector3) -> void:
	var mats := Node3D.new()
	mats.name = "ExerciseMatArea"
	mats.position = origin
	add_child(mats)
	var arrival := Marker3D.new()
	arrival.name = "PocketPTMatArrival"
	arrival.position = Vector3(0.0, 0.0, -2.0)
	arrival.add_to_group("pocketpt_mat_target")
	mats.add_child(arrival)
	var mat_body := StaticBody3D.new()
	mat_body.name = "ExerciseMatSelectable"
	mat_body.add_to_group("pocketpt_mat")
	mats.add_child(mat_body)
	_box("ExerciseMat", Vector3(1.3, 0.035, 3.0), Vector3.ZERO, _material(Color(0.12, 0.16, 0.20), 0.0, 0.88), mat_body)
	var mat_collision := CollisionShape3D.new()
	var mat_shape := BoxShape3D.new()
	mat_shape.size = Vector3(1.3, 0.05, 3.0)
	mat_collision.shape = mat_shape
	mat_collision.position.y = 0.025
	mat_body.add_child(mat_collision)
	_sphere("MedicineBall", 0.38, Vector3(1.4, 0.39, -0.8), _material(BRAND_RED, 0.0, 0.72), mats)
	_sphere("StabilityBall", 0.62, Vector3(1.65, 0.63, 1.0), _material(Color(0.16, 0.20, 0.25), 0.0, 0.62), mats)

func _build_scoreboard() -> void:
	_box("Scoreboard", Vector3(3.1, 1.45, 0.12), Vector3(5.3, 3.7, -6.72), _material(Color(0.015, 0.018, 0.022), 0.3, 0.28))
	var title := Label3D.new()
	title.name = "ScoreboardText"
	title.text = "MOVEMENT LAB\nREADY  •  00:00"
	title.font_size = 48
	title.modulate = Color(0.20, 1.0, 0.55)
	title.position = Vector3(5.3, 3.72, -6.62)
	title.pixel_size = 0.005
	add_child(title)

func _build_camera() -> void:
	var camera := Camera3D.new()
	camera.name = "GymTestCamera"
	camera.position = Vector3(2.8, 1.65, 3.8)
	camera.look_at_from_position(camera.position, Vector3(0, 0.68, 0), Vector3.UP)
	camera.fov = 48.0
	camera.current = true
	add_child(camera)

func _build_status_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "MovementLabHUD"
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 24)
	panel.custom_minimum_size = Vector2(290, 128)
	layer.add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.028, 0.035, 0.90)
	style.border_color = BRAND_RED
	style.set_border_width_all(2)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	panel.add_child(stack)
	var brand := Label.new()
	brand.text = "UNLEASH DA BEAST"
	brand.add_theme_font_size_override("font_size", 22)
	brand.add_theme_color_override("font_color", BRAND_RED)
	stack.add_child(brand)
	var lab := Label.new()
	lab.text = "MOVEMENT LAB"
	lab.add_theme_font_size_override("font_size", 15)
	stack.add_child(lab)
	status_label = Label.new()
	status_label.text = "STATUS: READY"
	status_label.add_theme_font_size_override("font_size", 16)
	stack.add_child(status_label)
	phase_label = Label.new()
	phase_label.text = "1: RUN SQUAT   R: RESTORE"
	phase_label.add_theme_font_size_override("font_size", 13)
	phase_label.add_theme_color_override("font_color", Color(0.72, 0.76, 0.82))
	stack.add_child(phase_label)

func set_movement_status(status: String, detail := "") -> void:
	if status_label:
		status_label.text = "STATUS: " + status
	if phase_label:
		phase_label.text = detail
