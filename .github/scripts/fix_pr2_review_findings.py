from pathlib import Path


def replace_once(path_str: str, old: str, new: str, label: str) -> None:
    path = Path(path_str)
    text = path.read_text()
    if old not in text:
        raise SystemExit(f"FIRST FAILURE: {label}")
    path.write_text(text.replace(old, new, 1))


replace_once(
    "player.gd",
    '@onready var avatar_anchor: Node3D = get_node_or_null("avataranchor") as Node3D\n',
    '@onready var avatar_anchor: Node3D = get_node_or_null("avataranchor") as Node3D\n'
    '@onready var fallback_visual: Node3D = get_node_or_null("Sketchfab_Scene") as Node3D\n',
    "player avatar_anchor declaration not found",
)

replace_once(
    "player.gd",
    '\t\t"visualFacingYaw": avatar_anchor.rotation.y if avatar_anchor != null else 0.0,\n',
    '\t\t"visualFacingYaw": _visual_facing_yaw(),\n',
    "player visualFacingYaw telemetry not found",
)

replace_once(
    "player.gd",
    '''func _face_visual_direction(world_direction: Vector3, delta: float) -> void:
\tif avatar_anchor == null:
\t\treturn
\tvar local_direction := global_transform.basis.inverse() * world_direction
\tlocal_direction.y = 0.0
\tif local_direction.length_squared() <= 0.0001:
\t\treturn
\tlocal_direction = local_direction.normalized()
\tvar target_yaw := atan2(-local_direction.x, -local_direction.z)
\tavatar_anchor.rotation.y = lerp_angle(avatar_anchor.rotation.y, target_yaw, clampf(visual_turn_speed * delta, 0.0, 1.0))
''',
    '''func _face_visual_direction(world_direction: Vector3, delta: float) -> void:
\tif avatar_anchor == null and fallback_visual == null:
\t\treturn
\tvar local_direction := global_transform.basis.inverse() * world_direction
\tlocal_direction.y = 0.0
\tif local_direction.length_squared() <= 0.0001:
\t\treturn
\tlocal_direction = local_direction.normalized()
\tvar target_yaw := atan2(-local_direction.x, -local_direction.z)
\tvar weight := clampf(visual_turn_speed * delta, 0.0, 1.0)
\tif avatar_anchor != null and is_instance_valid(avatar_anchor):
\t\tavatar_anchor.rotation.y = lerp_angle(avatar_anchor.rotation.y, target_yaw, weight)
\tif fallback_visual != null and is_instance_valid(fallback_visual):
\t\tfallback_visual.rotation.y = lerp_angle(fallback_visual.rotation.y, target_yaw, weight)

func _visual_facing_yaw() -> float:
\tif fallback_visual != null and is_instance_valid(fallback_visual) and fallback_visual.visible:
\t\treturn fallback_visual.rotation.y
\tif avatar_anchor != null and is_instance_valid(avatar_anchor):
\t\treturn avatar_anchor.rotation.y
\treturn 0.0
''',
    "player facing function not found",
)

replace_once(
    "scripts/pocketpt/pocketpt_locomotion_animator.gd",
    '''func _on_avatar_mounted(avatar_root: Node3D) -> void:
\t_avatar_root = avatar_root
\tactive_skeleton = null
''',
    '''func _on_avatar_mounted(avatar_root: Node3D) -> void:
\t_cancel_action_override_for_rebind()
\tset_process(false)
\tanimation_player = null
\tanimation_tree = null
\t_playback = null
\t_avatar_root = avatar_root
\tactive_skeleton = null
''',
    "animator mount function not found",
)

replace_once(
    "scripts/pocketpt/pocketpt_locomotion_animator.gd",
    'func can_request_action(semantic_id: StringName) -> bool:\n',
    '''func _cancel_action_override_for_rebind() -> void:
\tif not action_override_active:
\t\treturn
\tif animation_player != null and is_instance_valid(animation_player):
\t\tanimation_player.stop()
\tif animation_tree != null and is_instance_valid(animation_tree):
\t\tanimation_tree.active = false
\taction_override_active = false
\tcurrent_state = &"IDLE"
\taction_override_changed.emit(false)

func can_request_action(semantic_id: StringName) -> bool:
''',
    "animator action marker not found",
)

replace_once(
    "scripts/pocketpt/pocketpt_phone_flow.gd",
    '''\t\tif not _player.set_remote_intent(DIRECTIONS[action] * float(intensity_value), int(valid_for), action):
\t\t\treturn false
\t\t_requested_motion_action = action
''',
    '''\t\tif not _player.set_remote_intent(DIRECTIONS[action] * float(intensity_value), int(valid_for), action):
\t\t\treturn false
\t\t_clear_navigation_command()
\t\t_requested_motion_action = action
''',
    "legacy direction block not found",
)

replace_once(
    "tests/player_locomotion_library_test.gd",
    '\tprint("PLAYER_LOCOMOTION_TEST: PASS clips=player/Idle,player/Walk,player/Run root_motion=IN_PLACE transitions=IDLE-WALK-RUN")\n',
    '''\tvar override_released := false
\tanimator.action_override_changed.connect(func(active: bool):
\t\tif not active: override_released = true
\t)
\tif not animator.request_action(&"ThrillerPart1"): return _fail("ACTION_START")
\tif not animator.action_override_active: return _fail("ACTION_OVERRIDE_NOT_ACTIVE")
\tvar replacement_wrapper := Node3D.new(); root.add_child(replacement_wrapper)
\tvar replacement_avatar := (load("res://assets/characters/pocketpt/source/rashad1.glb") as PackedScene).instantiate(); replacement_wrapper.add_child(replacement_avatar)
\tanimator._on_avatar_mounted(replacement_wrapper)
\tif animator.action_override_active: return _fail("ACTION_OVERRIDE_STUCK_AFTER_REBIND")
\tif not override_released: return _fail("ACTION_OVERRIDE_RELEASE_SIGNAL")
\tif not animator.can_request_action(&"ThrillerPart1"): return _fail("ACTION_NOT_READY_AFTER_REBIND")
\tprint("PLAYER_LOCOMOTION_TEST: PASS clips=player/Idle,player/Walk,player/Run root_motion=IN_PLACE transitions=IDLE-WALK-RUN")
''',
    "locomotion test PASS marker not found",
)

Path("tests/player_visual_facing_test.gd").write_text('''extends SceneTree

const PlayerScript = preload("res://player.gd")

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
\tplayer._face_visual_direction(Vector3(1.0, 0.0, 0.0), 1.0)
\tif is_zero_approx(anchor.rotation.y): return _fail("PERSONAL_ANCHOR_DID_NOT_TURN")
\tif is_zero_approx(fallback.rotation.y): return _fail("FALLBACK_DID_NOT_TURN")
\tif not is_equal_approx(player._visual_facing_yaw(), fallback.rotation.y): return _fail("FALLBACK_TELEMETRY_NOT_ACTIVE")
\tfallback.visible = false
\tif not is_equal_approx(player._visual_facing_yaw(), anchor.rotation.y): return _fail("PERSONAL_TELEMETRY_NOT_ACTIVE")
\tprint("PLAYER_VISUAL_FACING_TEST: PASS personal_and_fallback_turn")
\tquit(0)

func _fail(reason: String) -> void:
\tpush_error("PLAYER_VISUAL_FACING_TEST: FAIL " + reason)
\tquit(1)
''')

print("PR2_PATCH: PASS")
