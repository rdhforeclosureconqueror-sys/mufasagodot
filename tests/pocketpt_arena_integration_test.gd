extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://Main.tscn") as PackedScene
	if packed == null:
		return _finish(false, "Main.tscn failed to load")
	var change_error := change_scene_to_packed(packed)
	if change_error != OK:
		return _finish(false, "Main.tscn change failed: %s" % error_string(change_error))
	await scene_changed
	var arena := current_scene
	for frame in range(8):
		await physics_frame
	var player := arena.get_node_or_null("player") as GymPlayerController
	_expect(player != null, "PLAYER_BODY_FOUND")
	if player == null:
		return _finish(false, "player missing")
	_expect(player.get_node_or_null("CollisionShape3D") is CollisionShape3D, "PLAYER_COLLISION_FOUND")
	_expect(not get_nodes_in_group("pocketpt_floor_collision").is_empty(), "FLOOR_COLLISION_FOUND")
	_expect(player.is_on_floor(), "PLAYER_GROUNDED")
	_expect(absf(player.global_position.y - 0.75) < 0.08, "PLAYER_ROOT_Y aligns capsule to floor")
	_expect(player.navigation_ready(), "NAVIGATION_READY")
	_expect(get_nodes_in_group("pocketpt_navigation_region").size() == 1, "one navigation region")
	_expect(get_nodes_in_group("pocketpt_mat_target").size() == 1, "one mat target")
	_expect(get_nodes_in_group("pocketpt_mufasa").size() == 1, "one Mufasa instance")
	var fallback_animation_names: Array[String] = []
	for animation_node in arena.get_node("player/Sketchfab_Scene").find_children("*", "AnimationPlayer", true, false):
		for animation_name in (animation_node as AnimationPlayer).get_animation_list():
			fallback_animation_names.append(str(animation_name))
	print("PLAYER_ANIMATIONS: %s" % [fallback_animation_names])
	var lion := get_nodes_in_group("pocketpt_mufasa")[0] if not get_nodes_in_group("pocketpt_mufasa").is_empty() else null
	if lion != null:
		var skeletons := lion.find_children("*", "Skeleton3D", true, false)
		var players := lion.find_children("*", "AnimationPlayer", true, false)
		_expect(skeletons.size() == 1, "Mufasa skeleton preserved")
		_expect(not players.is_empty(), "Mufasa AnimationPlayer preserved")
		if not players.is_empty():
			var clips := Array((players[0] as AnimationPlayer).get_animation_list())
			for required in ["Mufasa_Idle_01", "Mufasa_Walk", "Mufasa_Run"]:
				_expect(clips.any(func(value): return str(value).ends_with(required)), "Mufasa clip %s preserved" % required)
	var start := player.global_position
	_expect(player.set_remote_intent(Vector2.UP, 300), "forward intent accepted")
	for frame in range(12): await physics_frame
	_expect(Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length() > 0.15, "forward intent moves physics body")
	player.stop_navigation()
	var stopped := player.global_position
	for frame in range(8): await physics_frame
	_expect(Vector2(player.global_position.x - stopped.x, player.global_position.z - stopped.z).length() < 0.03, "STOP halts body")
	var target := get_nodes_in_group("pocketpt_mat_target")[0] as Node3D
	var route_result := [false]
	player.route_finished.connect(func(value: bool): route_result[0] = value)
	_expect(player.start_route(target.global_position), "GO_TO_MAT route accepted")
	for frame in range(420):
		await physics_frame
		if route_result[0]: break
	var mat_distance := Vector2(player.global_position.x - target.global_position.x, player.global_position.z - target.global_position.z).length()
	print("ARENA_ROUTE_RESULT arrived=%s active=%s distance=%.3f player=%s target=%s next=%s" % [route_result[0], player.is_route_active(), mat_distance, player.global_position, target.global_position, player.navigation_agent.get_next_path_position()])
	_expect(route_result[0] and mat_distance <= player.mat_arrival_distance + 0.08, "player physically arrived at mat")
	_finish(failures.is_empty(), "; ".join(failures))

func _expect(condition: bool, description: String) -> void:
	if not condition: failures.append(description)

func _finish(ok: bool, reason: String) -> void:
	if ok:
		print("POCKETPT_ARENA_INTEGRATION_TEST: PASS")
		quit(0)
	else:
		push_error(reason)
		print("POCKETPT_ARENA_INTEGRATION_TEST: FAIL")
		quit(1)
