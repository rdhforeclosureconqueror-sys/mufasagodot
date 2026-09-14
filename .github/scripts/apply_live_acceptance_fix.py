from pathlib import Path


def replace_once(path_str: str, old: str, new: str, label: str) -> None:
    path = Path(path_str)
    text = path.read_text()
    if old not in text:
        raise SystemExit(f"FIRST FAILURE: {label}")
    path.write_text(text.replace(old, new, 1))


replace_once(
    "player.gd",
    "\tvar target_yaw := atan2(-local_direction.x, -local_direction.z)\n",
    "\t# The imported personalized avatar's visual forward axis is opposite Godot's -Z controller forward.\n"
    "\t# Apply the model-facing half turn only to the visual nodes; CharacterBody/NavAgent motion is unchanged.\n"
    "\tvar target_yaw := wrapf(atan2(-local_direction.x, -local_direction.z) + PI, -PI, PI)\n",
    "player visual facing formula not found",
)

replace_once(
    "scripts/pocketpt/pocketpt_bridge_debug.gd",
    "\tadd_child(panel)\n",
    "\tadd_child(panel)\n\t# Browser builds publish diagnostics to the parent PocketPT page; keep the in-world panel out of the player's view.\n\tpanel.visible = not OS.has_feature(\"web\")\n",
    "bridge debug panel attach point not found",
)

Path("tests/player_visual_facing_test.gd").write_text('''extends SceneTree

const PlayerScript = preload("res://player.gd")
const EPSILON := 0.001

func _initialize() -> void:
\tcall_deferred("_run")

func _run() -> void:
\tvar player := PlayerScript.new()
\tvar spring := SpringArm3D.new(); spring.name = "SpringArm3D"; player.add_child(spring)
\tvar agent := NavigationAgent3D.new(); agent.name = "NavigationAgent3D"; player.add_child(agent)
\tvar anchor := Node3D.new(); anchor.name = "avataranchor"; player.add_child(anchor)
\tvar fallback := Node3D.new(); fallback.name = "Sketchfab_Scene"; fallback.visible = true; player.add_child(fallback)
\troot.add_child(player)
\tawait process_frame
\t# The personalized avatar's authored forward axis requires a 180-degree model-facing offset.
\t_assert_direction(player, anchor, fallback, Vector3.LEFT, -PI / 2.0, "LEFT")
\t_assert_direction(player, anchor, fallback, Vector3.RIGHT, PI / 2.0, "RIGHT")
\t_assert_direction(player, anchor, fallback, Vector3.FORWARD, -PI, "FORWARD")
\t_assert_direction(player, anchor, fallback, Vector3.BACK, 0.0, "BACK")
\tif not is_equal_approx(player._visual_facing_yaw(), fallback.rotation.y): return _fail("FALLBACK_TELEMETRY_NOT_ACTIVE")
\tfallback.visible = false
\tif not is_equal_approx(player._visual_facing_yaw(), anchor.rotation.y): return _fail("PERSONAL_TELEMETRY_NOT_ACTIVE")
\tprint("PLAYER_VISUAL_FACING_TEST: PASS movement_direction_matches_visual_forward")
\tquit(0)

func _assert_direction(player: Node, anchor: Node3D, fallback: Node3D, direction: Vector3, expected: float, label: String) -> void:
\tplayer._face_visual_direction(direction, 1.0)
\tif absf(angle_difference(anchor.rotation.y, expected)) > EPSILON: _fail("PERSONAL_%s_WRONG_WAY yaw=%.4f expected=%.4f" % [label, anchor.rotation.y, expected])
\tif absf(angle_difference(fallback.rotation.y, expected)) > EPSILON: _fail("FALLBACK_%s_WRONG_WAY yaw=%.4f expected=%.4f" % [label, fallback.rotation.y, expected])

func _fail(reason: String) -> void:
\tpush_error("PLAYER_VISUAL_FACING_TEST: FAIL " + reason)
\tquit(1)
''')

print("LIVE_ACCEPTANCE_SOURCE_PATCH: PASS")
