extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://Main.tscn") as PackedScene
	if packed == null or change_scene_to_packed(packed) != OK:
		return _fail("MAIN_SCENE")
	await scene_changed
	for frame in 8:
		await physics_frame
	var player := current_scene.get_node_or_null("player") as GymPlayerController
	var bootstrap := current_scene.get_node_or_null("PocketPTBootstrap")
	var animator := bootstrap.get_node_or_null("PocketPTLocomotionAnimator") if bootstrap != null else null
	if player == null or animator == null:
		return _fail("PRODUCTION_PLAYER_ANIMATOR")
	var wall := StaticBody3D.new()
	wall.name = "CollisionIdleGateWall"
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.0, 3.0, 0.2)
	shape_node.shape = shape
	wall.add_child(shape_node)
	current_scene.add_child(wall)
	wall.global_position = player.global_position + player.transform.basis * Vector3(0.0, 0.0, -0.6)
	var actual_speeds: Array[float] = []
	player.locomotion_speed_changed.connect(func(value: float, _source: String): actual_speeds.append(value))
	if not player.set_remote_intent(Vector2.UP, 300):
		return _fail("REMOTE_INTENT")
	for frame in 12:
		await physics_frame
	if actual_speeds.is_empty() or actual_speeds[-1] > 0.05:
		return _fail("POST_COLLISION_ZERO_DISPLACEMENT")
	if animator.current_state != &"IDLE":
		return _fail("COLLISION_TO_IDLE")
	print("PLAYER_COLLISION_IDLE_TEST: PASS blocked_displacement=%.4f state=IDLE" % actual_speeds[-1])
	quit(0)

func _fail(boundary: String) -> void:
	push_error("PLAYER_COLLISION_IDLE_TEST: FAIL " + boundary)
	quit(1)
