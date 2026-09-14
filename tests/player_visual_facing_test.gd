extends SceneTree

const PlayerScript = preload("res://player.gd")
const EPSILON := 0.001

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
	# The personalized avatar's authored forward axis requires a 180-degree model-facing offset.
	var failure := _direction_failure(player, anchor, fallback, Vector3.LEFT, -PI / 2.0, "LEFT")
	if failure != "": return _fail(failure)
	failure = _direction_failure(player, anchor, fallback, Vector3.RIGHT, PI / 2.0, "RIGHT")
	if failure != "": return _fail(failure)
	failure = _direction_failure(player, anchor, fallback, Vector3.FORWARD, -PI, "FORWARD")
	if failure != "": return _fail(failure)
	failure = _direction_failure(player, anchor, fallback, Vector3.BACK, 0.0, "BACK")
	if failure != "": return _fail(failure)
	if not is_equal_approx(player._visual_facing_yaw(), fallback.rotation.y): return _fail("FALLBACK_TELEMETRY_NOT_ACTIVE")
	fallback.visible = false
	if not is_equal_approx(player._visual_facing_yaw(), anchor.rotation.y): return _fail("PERSONAL_TELEMETRY_NOT_ACTIVE")
	print("PLAYER_VISUAL_FACING_TEST: PASS movement_direction_matches_visual_forward")
	quit(0)

func _direction_failure(player: Node, anchor: Node3D, fallback: Node3D, direction: Vector3, expected: float, label: String) -> String:
	player._face_visual_direction(direction, 1.0)
	if absf(angle_difference(anchor.rotation.y, expected)) > EPSILON:
		return "PERSONAL_%s_WRONG_WAY yaw=%.4f expected=%.4f" % [label, anchor.rotation.y, expected]
	if absf(angle_difference(fallback.rotation.y, expected)) > EPSILON:
		return "FALLBACK_%s_WRONG_WAY yaw=%.4f expected=%.4f" % [label, fallback.rotation.y, expected]
	return ""

func _fail(reason: String) -> void:
	push_error("PLAYER_VISUAL_FACING_TEST: FAIL " + reason)
	quit(1)
