class_name PocketPTPhoneFlow
extends Node

signal flow_state_changed(state: Dictionary)
signal bridge_message_prepared(payload: Dictionary)

const PROTOCOL_VERSION := 1
const FLOW_VERSION := 1
const DIAGNOSTIC_VERSION := 1
const MAX_SAFE_INTEGER := 9007199254740991
const DIRECTIONS := {
	"MOVE_LEFT": Vector2.LEFT,
	"MOVE_RIGHT": Vector2.RIGHT,
	"MOVE_FORWARD": Vector2.UP,
	"MOVE_BACKWARD": Vector2.DOWN
}
const CONTEXTS := ["GYM_NAVIGATION", "CAMERA_SETUP", "LOCKED"]
const DIAGNOSTIC_STAGES := ["AVATAR_DOWNLOAD", "AVATAR_IMPORT", "AVATAR_MOUNT", "AVATAR_FALLBACK", "ANIMATION_IDLE", "LOCOMOTION", "MAT_APPROACH", "CHALLENGE_STATE", "GHOST_PLAYBACK"]

var state: Dictionary = {
	"connected": false,
	"request_id": "",
	"context": "LOCKED",
	"incoming_sequence": 0,
	"outgoing_sequence": 0,
	"pending_command": "",
	"last_action": "NONE",
	"movementMode": "WALK",
	"animations": PackedStringArray()
}

var _client: PocketPTGameClient
var _player: GymPlayerController
var _avatar_loader: PocketPTAvatarLoader
var _locomotion_animator: PocketPTLocomotionAnimator
var _browser_callback = null
var _diagnostic_request_id := ""
var _diagnostic_sequence := 0
var _pending_reply_to := 0
var _mat_target: Node3D
var _animation_player: AnimationPlayer
var _idle_clip := ""
var _walk_clip := ""
var _strafe_left_clip := ""
var _strafe_right_clip := ""
var _requested_motion_action := ""
var _session_expiry_unix := -1.0

func bind(client: PocketPTGameClient, player: GymPlayerController, avatar_loader: PocketPTAvatarLoader, locomotion_animator: PocketPTLocomotionAnimator = null) -> void:
	_client = client
	_player = player
	_avatar_loader = avatar_loader
	_locomotion_animator = locomotion_animator
	_client.connection_state_changed.connect(_on_connection_state_changed)
	_client.bootstrap_accepted.connect(_on_bootstrap_accepted)
	_client.session_ending.connect(_disconnect_flow)
	_player.route_finished.connect(_on_route_finished)
	_player.mat_selected.connect(_on_mat_selected)
	_player.navigation_state_changed.connect(_on_navigation_state_changed)
	_avatar_loader.avatar_state_changed.connect(_on_avatar_state_changed)
	_avatar_loader.avatar_mounted.connect(_on_avatar_mounted)
	_avatar_loader.fallback_activated.connect(_on_fallback_activated)
	if _locomotion_animator != null:
		_locomotion_animator.runtime_evidence_changed.connect(_on_animation_evidence_changed)
	call_deferred("_resolve_mat_target")
	_install_browser_receiver()
	set_process(true)

func _process(_delta: float) -> void:
	if _session_expiry_unix > 0.0 and Time.get_unix_time_from_system() >= _session_expiry_unix:
		_session_expiry_unix = -1.0
		_client.invalidate_session()

func _exit_tree() -> void:
	_disconnect_flow()
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		JavaScriptBridge.eval("window.__pocketptGodotFlowRemove && window.__pocketptGodotFlowRemove();")

func ingest_message_for_test(message: Dictionary) -> bool:
	return _accept_message(message)

func expire_navigation_for_test() -> void:
	_player._remote_lease_deadline_ms = 1
	_player._resolve_movement()

func capabilities() -> Dictionary:
	return {
		"contextLock": true,
		"touchNavigation": true,
		"matApproach": _mat_target != null and is_instance_valid(_mat_target) and _player != null and _player.navigation_ready(),
		"pushUpTransition": _has_push_up_transitions()
	}

func _install_browser_receiver() -> void:
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		return
	var window = JavaScriptBridge.get_interface("window")
	if window == null:
		return
	_browser_callback = JavaScriptBridge.create_callback(_on_browser_message)
	window.__pocketptGodotFlowCallback = _browser_callback
	JavaScriptBridge.eval("""
(() => {
	if (window.__pocketptGodotFlowRemove) window.__pocketptGodotFlowRemove();
	const handler = (event) => {
		if (event.source !== window.parent || event.origin !== window.location.origin) return;
		const callback = window.__pocketptGodotFlowCallback;
		if (typeof callback !== "function") return;
		try { callback(JSON.stringify(event.data)); } catch (_error) {}
	};
	window.addEventListener("message", handler);
	window.__pocketptGodotFlowRemove = () => {
		window.removeEventListener("message", handler);
		delete window.__pocketptGodotFlowRemove;
	};
	return true;
})()
""")

func _on_browser_message(args: Array) -> void:
	if args.is_empty() or not args[0] is String:
		return
	var parsed = JSON.parse_string(args[0])
	if parsed is Dictionary:
		_accept_message(parsed)

func _accept_message(message: Dictionary) -> bool:
	if message.get("type") != "POCKETPT_GODOT_BRIDGE" or not _exact_number(message.get("protocolVersion"), PROTOCOL_VERSION):
		return false
	var event_name := str(message.get("event", ""))
	if event_name == "DIAGNOSTICS_REQUEST":
		return _accept_diagnostics_request(message)
	if not _exact_number(message.get("flowVersion"), FLOW_VERSION):
		return false
	var request_id := str(message.get("requestId", ""))
	if request_id.is_empty() or not _safe_sequence(message.get("sequence")):
		return false
	var sequence := int(message["sequence"])
	if event_name == "ARENA_FLOW_REQUEST":
		if str(message.get("experience", "")) != PocketPTGameClient.EXPECTED_EXPERIENCE:
			return false
		if bool(state["connected"]) and request_id == str(state["request_id"]):
			return false
		_disconnect_flow()
		state["connected"] = true
		state["request_id"] = request_id
		state["incoming_sequence"] = sequence
		_send_flow("ARENA_FLOW_CAPABILITIES", {"capabilities": capabilities()})
		_publish()
		return true
	if not bool(state["connected"]) or request_id != str(state["request_id"]) or sequence <= int(state["incoming_sequence"]):
		return false
	if event_name != "CONTROL_INTENT":
		return false
	var action := str(message.get("action", ""))
	var context := str(message.get("context", ""))
	if action == "STOP":
		state["last_action"] = action
		state["incoming_sequence"] = sequence
		_player.stop_navigation()
		_clear_navigation_command()
		_publish()
		return true
	if context not in CONTEXTS:
		return false
	if action == "SET_CONTEXT":
		state["last_action"] = action
		state["incoming_sequence"] = sequence
		state["context"] = context
		_player.set_navigation_context(context)
		_clear_navigation_command()
		_publish()
		return true
	if action == "SET_LOCOMOTION_MODE":
		var mode := str(message.get("mode", ""))
		if context != str(state["context"]) or not _player.set_locomotion_mode(mode): return false
		state["last_action"] = action
		state["incoming_sequence"] = sequence
		state["movementMode"] = mode
		_publish()
		return true
	if action == "PLAY_ACTION":
		var action_name := str(message.get("name", ""))
		if context != str(state["context"]) or context != "GYM_NAVIGATION" or action_name != "ThrillerPart1":
			return false
		if _locomotion_animator == null:
			return false
		_player.stop_navigation()
		_clear_navigation_command()
		if not _locomotion_animator.request_action(&"ThrillerPart1"):
			return false
		_requested_motion_action = ""
		state["last_action"] = action
		state["incoming_sequence"] = sequence
		_publish()
		return true
	if context != str(state["context"]):
		return false
	if action == "MOVE_VECTOR":
		var valid_for = message.get("validForMs")
		var x_value = message.get("x")
		var y_value = message.get("y")
		if not _exact_bounded_number(valid_for, 1.0, 300.0) or not _exact_bounded_number(x_value, -1.0, 1.0) or not _exact_bounded_number(y_value, -1.0, 1.0):
			return false
		var movement_vector := Vector2(float(x_value), float(y_value))
		if movement_vector.length_squared() <= 0.0025:
			return false
		movement_vector = movement_vector.normalized()
		if not _player.set_remote_intent(movement_vector, int(valid_for), action):
			return false
		_requested_motion_action = action
		state["last_action"] = action
		state["incoming_sequence"] = sequence
		_publish()
		return true
	if action in DIRECTIONS:
		var valid_for = message.get("validForMs")
		var intensity_value = message.get("intensity", 1.0)
		if not _exact_bounded_number(valid_for, 1.0, 300.0) or not _exact_bounded_number(intensity_value, 0.0, 1.0):
			return false
		if not _player.set_remote_intent(DIRECTIONS[action] * float(intensity_value), int(valid_for), action):
			return false
		_requested_motion_action = action
		state["last_action"] = action
		state["incoming_sequence"] = sequence
		_publish()
		return true
	if action == "GO_TO_MAT":
		if not bool(capabilities()["matApproach"]) or not str(state["pending_command"]).is_empty():
			return false
		if not _player.start_route(_mat_target.global_position):
			return false
		_requested_motion_action = ""
		state["last_action"] = action
		state["incoming_sequence"] = sequence
		state["pending_command"] = action
		_pending_reply_to = sequence
		_publish()
		return true
	# Never acknowledge presentation commands unless compatible clips exist and complete.
	if action in ["PUSH_UP_START", "STAND_UP"]:
		return false
	return false

func _accept_diagnostics_request(message: Dictionary) -> bool:
	if not _exact_number(message.get("diagnosticVersion"), DIAGNOSTIC_VERSION):
		return false
	var request_id := str(message.get("requestId", ""))
	if request_id.is_empty():
		return false
	_diagnostic_request_id = request_id
	_diagnostic_sequence = 0
	_report_current_diagnostics()
	return true

func _send_flow(event_name: String, extra: Dictionary = {}) -> bool:
	if not bool(state["connected"]):
		return false
	state["outgoing_sequence"] = int(state["outgoing_sequence"]) + 1
	var payload := {
		"type": "POCKETPT_GODOT_BRIDGE",
		"protocolVersion": PROTOCOL_VERSION,
		"event": event_name,
		"flowVersion": FLOW_VERSION,
		"requestId": state["request_id"],
		"sequence": state["outgoing_sequence"]
	}
	payload.merge(extra, true)
	return _post_to_parent(payload)

func _post_to_parent(payload: Dictionary) -> bool:
	bridge_message_prepared.emit(payload.duplicate(true))
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		return false
	var literal := JSON.stringify(JSON.stringify(payload))
	return JavaScriptBridge.eval("""
(() => {
	try {
		if (window.parent === window || !window.location.origin) return false;
		window.parent.postMessage(JSON.parse(%s), window.location.origin);
		return true;
	} catch (_error) { return false; }
})()
""" % literal) == true

func _on_mat_selected() -> void:
	if bool(state["connected"]) and str(state["context"]) == "GYM_NAVIGATION" and bool(capabilities()["matApproach"]):
		_send_flow("ARENA_MAT_SELECTED")

func _on_route_finished(arrived: bool) -> void:
	if arrived and str(state["pending_command"]) == "GO_TO_MAT":
		_send_flow("ARENA_FLOW_EVENT", {"replyTo": _pending_reply_to, "result": "AT_MAT"})
		_report_diagnostic("MAT_APPROACH", "PASS")
		state["pending_command"] = ""
		_pending_reply_to = 0
		_publish()

func _clear_navigation_command() -> void:
	_requested_motion_action = ""
	if str(state["pending_command"]) == "GO_TO_MAT":
		state["pending_command"] = ""
		_pending_reply_to = 0

func _resolve_mat_target() -> void:
	var nodes := get_tree().get_nodes_in_group("pocketpt_mat_target")
	_mat_target = nodes[0] as Node3D if not nodes.is_empty() else null

func _disconnect_flow() -> void:
	if _player != null:
		_player.stop_navigation()
	state["connected"] = false
	state["request_id"] = ""
	state["context"] = "LOCKED"
	state["incoming_sequence"] = 0
	state["outgoing_sequence"] = 0
	state["pending_command"] = ""
	_pending_reply_to = 0
	_requested_motion_action = ""

func _on_connection_state_changed(connection: Dictionary) -> void:
	if str(connection.get("status", "")) == "ERROR":
		_disconnect_flow()

func _on_bootstrap_accepted(payload: Dictionary) -> void:
	_session_expiry_unix = -1.0
	var session = payload.get("session")
	if session is Dictionary:
		var expires_at := str(session.get("expiresAt", ""))
		if not expires_at.is_empty():
			_session_expiry_unix = float(Time.get_unix_time_from_datetime_string(expires_at))

func _on_avatar_mounted(root: Node3D) -> void:
	_inspect_animations(root)

func _on_fallback_activated(_reason: String) -> void:
	var fallback := get_tree().current_scene.get_node_or_null("player/Sketchfab_Scene")
	if fallback != null:
		_inspect_animations(fallback)

func _inspect_animations(root: Node) -> void:
	_animation_player = null
	_idle_clip = ""
	_walk_clip = ""
	_strafe_left_clip = ""
	_strafe_right_clip = ""
	if bool(root.get_meta("pocketpt_shared_locomotion", false)):
		if _locomotion_animator != null:
			_animation_player = _locomotion_animator.animation_player
			_idle_clip = "player/Idle"
			_walk_clip = "player/Walk"
		state["animations"] = PackedStringArray(["player/Idle", "player/Walk", "player/Run"])
		_publish()
		return
	var clips := PackedStringArray()
	var players := root.find_children("*", "AnimationPlayer", true, false)
	if root is AnimationPlayer:
		players.push_back(root)
	for value in players:
		var animation_player := value as AnimationPlayer
		for library_name in animation_player.get_animation_library_list():
			var library := animation_player.get_animation_library(library_name)
			for clip in library.get_animation_list():
				var qualified := str(clip) if str(library_name).is_empty() else "%s/%s" % [library_name, clip]
				if qualified not in clips:
					clips.push_back(qualified)
				var normalized := str(clip).to_lower()
				if _animation_player == null and ("idle" in normalized or "walk" in normalized):
					_animation_player = animation_player
				if _idle_clip.is_empty() and "idle" in normalized:
					_idle_clip = qualified
				if _walk_clip.is_empty() and ("walk" in normalized or "locomotion" in normalized):
					_walk_clip = qualified
				if _strafe_left_clip.is_empty() and ("strafe_left" in normalized or "left_strafe" in normalized):
					_strafe_left_clip = qualified
				if _strafe_right_clip.is_empty() and ("strafe_right" in normalized or "right_strafe" in normalized):
					_strafe_right_clip = qualified
	state["animations"] = clips
	if _animation_player != null and not _idle_clip.is_empty():
		_animation_player.play(_idle_clip)
	_publish()

func _on_animation_evidence_changed() -> void:
	if _locomotion_animator != null and _locomotion_animator._avatar_root != null:
		_inspect_animations(_locomotion_animator._avatar_root)
	if not _diagnostic_request_id.is_empty(): _report_animation_diagnostics()

func _report_animation_diagnostics() -> void:
	if _locomotion_animator == null:
		_report_diagnostic("ANIMATION_IDLE", "NOT_CONNECTED", "ANIMATION_PLAYER_NOT_BOUND")
		_report_diagnostic("LOCOMOTION", "NOT_CONNECTED", "ANIMATION_PLAYER_NOT_BOUND")
		return
	var idle := _locomotion_animator.diagnostic_status(&"IDLE")
	var walk := _locomotion_animator.locomotion_diagnostic_status()
	_report_diagnostic("ANIMATION_IDLE", str(idle.status), str(idle.reason), _locomotion_animator.runtime_snapshot)
	_report_diagnostic("LOCOMOTION", str(walk.status), str(walk.reason), _locomotion_animator.runtime_snapshot)

func _has_push_up_transitions() -> bool:
	# Phase capability stays false until named clips have been independently bound,
	# played to completion, and interruption/restoration behavior is implemented.
	return false

func _on_navigation_state_changed(moving: bool, _source: String) -> void:
	if _locomotion_animator == null and _animation_player != null:
		var target_clip := _walk_clip if moving else _idle_clip
		if moving and _requested_motion_action == "MOVE_LEFT" and not _strafe_left_clip.is_empty():
			target_clip = _strafe_left_clip
		elif moving and _requested_motion_action == "MOVE_RIGHT" and not _strafe_right_clip.is_empty():
			target_clip = _strafe_right_clip
		if not target_clip.is_empty() and _animation_player.current_animation != target_clip:
			_animation_player.play(target_clip, 0.15)
	if not _diagnostic_request_id.is_empty():
		if _locomotion_animator != null: _report_animation_diagnostics()
		else: _report_diagnostic("LOCOMOTION", ("RUNNING" if moving else "PASS") if not _walk_clip.is_empty() else "NOT_CONNECTED")

func _on_avatar_state_changed(avatar: Dictionary) -> void:
	if str(avatar.get("error_code", "")) == PocketPTAvatarLoader.ERROR_SESSION_EXPIRED:
		_disconnect_flow()
	if _diagnostic_request_id.is_empty():
		return
	_report_avatar_stage("AVATAR_DOWNLOAD", str(avatar.get("download", "")))
	_report_avatar_stage("AVATAR_IMPORT", str(avatar.get("import", "")))
	_report_avatar_stage("AVATAR_MOUNT", str(avatar.get("mount", "")))
	if bool(avatar.get("fallback", false)): _report_diagnostic("AVATAR_FALLBACK", "PASS")

func _report_avatar_stage(stage: String, evidence: String) -> void:
	if evidence == "PASS":
		_report_diagnostic(stage, "PASS")
	elif evidence == "FAIL":
		_report_diagnostic(stage, "FAIL")

func _report_current_diagnostics() -> void:
	# Send a valid non-success result first so the parent can prove the reporter
	# connection without inferring that any downstream runtime stage passed.
	_report_diagnostic("CHALLENGE_STATE", "NOT_CONNECTED")
	var avatar := _avatar_loader.avatar_state
	_on_avatar_state_changed(avatar)
	_report_animation_diagnostics()
	_report_diagnostic("MAT_APPROACH", "WAITING" if bool(capabilities()["matApproach"]) else "NOT_CONNECTED")
	_report_diagnostic("GHOST_PLAYBACK", "SKIP")
	if not bool(avatar.get("fallback", false)):
		_report_diagnostic("AVATAR_FALLBACK", "SKIP")

func _report_diagnostic(stage: String, status: String, reason_code := "", details: Dictionary = {}) -> void:
	if _diagnostic_request_id.is_empty() or stage not in DIAGNOSTIC_STAGES:
		return
	_diagnostic_sequence += 1
	var payload := {
		"type": "POCKETPT_GODOT_BRIDGE", "event": "DIAGNOSTIC",
		"protocolVersion": PROTOCOL_VERSION, "diagnosticVersion": DIAGNOSTIC_VERSION,
		"requestId": _diagnostic_request_id, "sequence": _diagnostic_sequence,
		"stage": stage, "status": status
	}
	if not reason_code.is_empty(): payload["reasonCode"] = reason_code
	payload.merge(details, true)
	_post_to_parent(payload)

func _safe_sequence(value: Variant) -> bool:
	return _exact_bounded_number(value, 1.0, float(MAX_SAFE_INTEGER)) and floor(float(value)) == float(value)

func _exact_number(value: Variant, expected: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == float(expected)

func _exact_bounded_number(value: Variant, minimum: float, maximum: float) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

func _publish() -> void:
	flow_state_changed.emit(state.duplicate(true))
