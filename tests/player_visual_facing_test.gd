extends SceneTree

const PlayerScript = preload("res://player.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var player := PlayerScript.new()
	var spring := SpringArm3D.new(); spring.name = "SpringArm3D"; player.add_child(spring)
	var agent := NavigationAgent3D.new(); agent.name = "NavigationAgent3D"; player.add_child(agent)
	var anchor := Node3D.new(); anchor.name = "avataranchor"; player.add_child(anchor)
	var fallback := Node3D.new(); fallback.name = "Sketchfab_Scene"; fallback.visible = true; player.add_child(fallback)
	root.add_child(player)
	await process_frame
	player._face_visual_direction(Vector3(1.0, 0.0, 0.0), 1.0)
	if is_zero_approx(anchor.rotation.y): return _fail("PERSONAL_ANCHOR_DID_NOT_TURN")
	if is_zero_approx(fallback.rotation.y): return _fail("FALLBACK_DID_NOT_TURN")
	if not is_equal_approx(player._visual_facing_yaw(), fallback.rotation.y): return _fail("FALLBACK_TELEMETRY_NOT_ACTIVE")
	fallback.visible = false
	if not is_equal_approx(player._visual_facing_yaw(), anchor.rotation.y): return _fail("PERSONAL_TELEMETRY_NOT_ACTIVE")
	print("PLAYER_VISUAL_FACING_TEST: PASS personal_and_fallback_turn")
	quit(0)

func _fail(reason: String) -> void:
	push_error("PLAYER_VISUAL_FACING_TEST: FAIL " + reason)
	quit(1)
