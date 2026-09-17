class_name PocketPTPhoneFlowLiveMocap
extends PocketPTPhoneFlow

const MOCAP_VERSION := 1
const MOCAP_TIMEOUT_MS := 750
const MIN_MOCAP_CONFIDENCE := 0.35
const REQUIRED_JOINTS := [
	"Hips", "Spine", "Spine1", "Spine2", "Neck", "Head",
	"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand",
	"LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot"
]
const MOCAP_EVENTS := ["LIVE_MOCAP_ACQUIRE", "LIVE_MOCAP_FRAME", "LIVE_MOCAP_RELEASE"]

var _mocap_mapping_state: Dictionary = {}
var _mocap_mapping_profile: Dictionary = {}
var _mocap_avatar_root: Node3D
var _mocap_skeleton: Skeleton3D
var _mocap_bones: Dictionary = {}
var _mocap_touched_bones: Dictionary = {}
var _mocap_active := false
var _mocap_session_id := ""
var _mocap_frame_sequence := 0
var _mocap_last_frame_ticks := 0
var _mocap_frames_applied := 0
var _mocap_last_reason := "MOCAP_NOT_ACQUIRED"

func _process(delta: float) -> void:
	super._process(delta)
	_check_mocap_timeout(Time.get_ticks_msec())

func _check_mocap_timeout(now_ticks: int) -> bool:
	if not _mocap_active or _mocap_last_frame_ticks <= 0:
		return false
	if now_ticks - _mocap_last_frame_ticks <= MOCAP_TIMEOUT_MS:
		return false
	_release_live_mocap("MOCAP_FRAME_TIMEOUT")
	_report_mocap_diagnostic("GODOT_LIVE_MOCAP", "WAITING", "MOCAP_FRAME_TIMEOUT")
	return true

func capabilities() -> Dictionary:
	var result := super.capabilities()
	result["liveMocap"] = _mocap_ready()
	result["restRelativePose"] = true
	return result

func _accept_message(message: Dictionary) -> bool:
	var event_name := str(message.get("event", ""))
	if event_name not in MOCAP_EVENTS:
		return super._accept_message(message)
	if message.get("type") != "POCKETPT_GODOT_BRIDGE" or not _exact_number(message.get("protocolVersion"), PROTOCOL_VERSION):
		return false
	if not _exact_number(message.get("flowVersion"), FLOW_VERSION) or not _exact_number(message.get("mocapVersion"), MOCAP_VERSION):
		return false
	var request_id := str(message.get("requestId", ""))
	if not bool(state.get("connected", false)) or request_id.is_empty() or request_id != str(state.get("request_id", "")):
		return false
	if not _safe_sequence(message.get("sequence")):
		return false
	var sequence := int(message["sequence"])
	if sequence <= int(state.get("incoming_sequence", 0)):
		return false
	if str(state.get("context", "LOCKED")) != "LOCKED":
		return false
	var accepted := false
	match event_name:
		"LIVE_MOCAP_ACQUIRE": accepted = _accept_live_mocap_acquire(message)
		"LIVE_MOCAP_FRAME": accepted = _accept_live_mocap_frame(message)
		"LIVE_MOCAP_RELEASE": accepted = _accept_live_mocap_release(message)
	if not accepted:
		return false
	state["incoming_sequence"] = sequence
	state["last_action"] = event_name
	_publish()
	return true

func _accept_live_mocap_acquire(message: Dictionary) -> bool:
	if _mocap_active or not _mocap_ready():
		return false
	if message.get("restBaseReady") != true or str(message.get("trackingState", "")) != "TRACKING":
		return false
	var session_id := str(message.get("mocapSessionId", "")).strip_edges()
	if session_id.is_empty() or session_id.length() > 128:
		return false
	if _locomotion_animator == null or _locomotion_animator.action_override_active or _locomotion_animator.environment_override_active:
		return false
	if _locomotion_animator.animation_tree == null or not is_instance_valid(_locomotion_animator.animation_tree):
		return false
	_player.stop_navigation()
	_player.set_navigation_context("LOCKED")
	_locomotion_animator.animation_tree.active = false
	if _locomotion_animator.animation_player != null and is_instance_valid(_locomotion_animator.animation_player):
		_locomotion_animator.animation_player.stop()
	_mocap_active = true
	_mocap_session_id = session_id
	_mocap_frame_sequence = 0
	_mocap_last_frame_ticks = Time.get_ticks_msec()
	_mocap_frames_applied = 0
	_mocap_last_reason = "MOCAP_ACQUIRED"
	_report_mocap_diagnostic("GODOT_LIVE_MOCAP", "PASS", "MOCAP_ACQUIRED")
	_report_mocap_diagnostic("MOCAP_BONE_BIND", "PASS", "MOCAP_CANONICAL_MAP_BOUND")
	return true

func _accept_live_mocap_frame(message: Dictionary) -> bool:
	if not _mocap_active or str(message.get("mocapSessionId", "")) != _mocap_session_id:
		return false
	if message.get("restBaseReady") != true or str(message.get("trackingState", "")) != "TRACKING":
		return false
	if not _safe_sequence(message.get("frameSequence")):
		return false
	var frame_sequence := int(message["frameSequence"])
	if frame_sequence <= _mocap_frame_sequence:
		return false
	var source_timestamp = message.get("sourceTimestamp")
	if typeof(source_timestamp) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(source_timestamp)) or float(source_timestamp) < 0.0:
		return false
	var joints = message.get("joints")
	if not joints is Dictionary or joints.is_empty() or joints.size() > REQUIRED_JOINTS.size():
		return false
	var rotations: Dictionary = {}
	for canonical_value in joints:
		var canonical := str(canonical_value)
		if canonical not in REQUIRED_JOINTS or not _mocap_bones.has(canonical):
			return false
		var entry = joints[canonical_value]
		if not entry is Dictionary or entry.get("valid") != true:
			return false
		var confidence = entry.get("confidence")
		if typeof(confidence) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(confidence)) or float(confidence) < MIN_MOCAP_CONFIDENCE or float(confidence) > 1.0:
			return false
		var rotation = entry.get("rotation")
		if not rotation is Array or rotation.size() != 4:
			return false
		var values: Array[float] = []
		for value in rotation:
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
				return false
			values.push_back(float(value))
		var quaternion := Quaternion(values[0], values[1], values[2], values[3])
		if quaternion.length_squared() < 0.000001:
			return false
		rotations[canonical] = quaternion.normalized()
	if rotations.size() < 4:
		return false
	for canonical in _mocap_touched_bones.keys():
		if not rotations.has(canonical) and _mocap_bones.has(canonical):
			_mocap_skeleton.set_bone_pose_rotation(int(_mocap_bones[canonical]), Quaternion.IDENTITY)
			_mocap_touched_bones.erase(canonical)
	for canonical in rotations:
		_mocap_skeleton.set_bone_pose_rotation(int(_mocap_bones[canonical]), rotations[canonical])
		_mocap_touched_bones[canonical] = true
	_mocap_frame_sequence = frame_sequence
	_mocap_last_frame_ticks = Time.get_ticks_msec()
	_mocap_frames_applied += 1
	_mocap_last_reason = "MOCAP_FRAME_APPLIED"
	_report_mocap_diagnostic("MOCAP_FRAME_APPLIED", "PASS", "MOCAP_FRAME_APPLIED")
	return true

func _accept_live_mocap_release(message: Dictionary) -> bool:
	if not _mocap_active or str(message.get("mocapSessionId", "")) != _mocap_session_id:
		return false
	_release_live_mocap(str(message.get("reason", "MOCAP_RELEASED")))
	return true

func _release_live_mocap(reason: String) -> void:
	if _mocap_skeleton != null and is_instance_valid(_mocap_skeleton):
		for canonical in _mocap_touched_bones.keys():
			if _mocap_bones.has(canonical):
				_mocap_skeleton.set_bone_pose_rotation(int(_mocap_bones[canonical]), Quaternion.IDENTITY)
	_mocap_touched_bones.clear()
	_mocap_active = false
	_mocap_session_id = ""
	_mocap_frame_sequence = 0
	_mocap_last_frame_ticks = 0
	_mocap_last_reason = reason
	if _locomotion_animator != null and _locomotion_animator.animation_tree != null and is_instance_valid(_locomotion_animator.animation_tree):
		_locomotion_animator.animation_tree.active = true
		var playback := _locomotion_animator.animation_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
		if playback != null:
			playback.start(&"IDLE")
		_locomotion_animator.current_state = &"IDLE"
	_report_mocap_diagnostic("GODOT_LIVE_MOCAP", "WAITING", reason)

func _disconnect_flow() -> void:
	if _mocap_active:
		_release_live_mocap("FLOW_DISCONNECTED")
	super._disconnect_flow()

func _on_bootstrap_accepted(payload: Dictionary) -> void:
	super._on_bootstrap_accepted(payload)
	_mocap_mapping_state = payload.get("gymMappingState", {}) if payload.get("gymMappingState") is Dictionary else {}
	_mocap_mapping_profile = payload.get("gymMappingProfile", {}) if payload.get("gymMappingProfile") is Dictionary else {}
	_resolve_mocap_mapping()

func _on_avatar_mounted(root: Node3D) -> void:
	super._on_avatar_mounted(root)
	if _mocap_active:
		_release_live_mocap("AVATAR_REBOUND")
	_mocap_avatar_root = root
	_resolve_mocap_mapping()

func _on_fallback_activated(reason: String) -> void:
	if _mocap_active:
		_release_live_mocap("AVATAR_FALLBACK")
	_mocap_avatar_root = null
	_mocap_skeleton = null
	_mocap_bones.clear()
	super._on_fallback_activated(reason)

func _resolve_mocap_mapping() -> bool:
	_mocap_skeleton = null
	_mocap_bones.clear()
	if _mocap_avatar_root == null or not is_instance_valid(_mocap_avatar_root):
		_mocap_last_reason = "MOCAP_AVATAR_NOT_MOUNTED"
		return false
	if str(_mocap_mapping_state.get("status", "")) != "AVAILABLE" or int(_mocap_mapping_state.get("schemaVersion", 0)) != 1:
		_mocap_last_reason = "MOCAP_MAPPING_STATE_UNAVAILABLE"
		return false
	if int(_mocap_mapping_profile.get("schemaVersion", 0)) != 1 or _mocap_mapping_profile.get("restPoseValid") != true:
		_mocap_last_reason = "MOCAP_REST_PROFILE_INVALID"
		return false
	if str(_mocap_mapping_state.get("profileId", "")) != str(_mocap_mapping_profile.get("profileId", "")):
		_mocap_last_reason = "MOCAP_PROFILE_ID_MISMATCH"
		return false
	var canonical_map = _mocap_mapping_profile.get("canonicalMap")
	if not canonical_map is Dictionary or canonical_map.size() != REQUIRED_JOINTS.size():
		_mocap_last_reason = "MOCAP_CANONICAL_MAP_INVALID"
		return false
	var skeletons := _mocap_avatar_root.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		_mocap_last_reason = "MOCAP_SKELETON_NOT_FOUND"
		return false
	var skeleton := skeletons[0] as Skeleton3D
	var seen := {}
	for canonical in REQUIRED_JOINTS:
		var target := str(canonical_map.get(canonical, "")).strip_edges()
		if target.is_empty() or seen.has(target):
			_mocap_last_reason = "MOCAP_MAPPING_DUPLICATE_OR_MISSING:%s" % canonical
			return false
		var index := skeleton.find_bone(StringName(target))
		if index < 0:
			_mocap_last_reason = "MOCAP_BONE_NOT_FOUND:%s" % canonical
			return false
		seen[target] = true
		_mocap_bones[canonical] = index
	_mocap_skeleton = skeleton
	_mocap_last_reason = "MOCAP_CANONICAL_MAP_BOUND"
	_report_mocap_diagnostic("MOCAP_BONE_BIND", "PASS", _mocap_last_reason)
	return true

func _mocap_ready() -> bool:
	return _mocap_skeleton != null and is_instance_valid(_mocap_skeleton) and _mocap_bones.size() == REQUIRED_JOINTS.size() and _locomotion_animator != null

func _report_current_diagnostics() -> void:
	super._report_current_diagnostics()
	_report_mocap_diagnostic("GODOT_LIVE_MOCAP", "PASS" if _mocap_active else "WAITING", _mocap_last_reason)
	_report_mocap_diagnostic("MOCAP_BONE_BIND", "PASS" if _mocap_ready() else "NOT_CONNECTED", _mocap_last_reason)
	_report_mocap_diagnostic("MOCAP_FRAME_APPLIED", "PASS" if _mocap_frames_applied > 0 else "WAITING", "MOCAP_FRAME_APPLIED" if _mocap_frames_applied > 0 else "MOCAP_FRAME_NOT_OBSERVED")

func _report_mocap_diagnostic(stage: String, status: String, reason_code := "") -> void:
	if _diagnostic_request_id.is_empty() or stage not in ["GODOT_LIVE_MOCAP", "MOCAP_BONE_BIND", "MOCAP_FRAME_APPLIED"]:
		return
	_diagnostic_sequence += 1
	var payload := {
		"type": "POCKETPT_GODOT_BRIDGE", "event": "DIAGNOSTIC",
		"protocolVersion": PROTOCOL_VERSION, "diagnosticVersion": DIAGNOSTIC_VERSION,
		"requestId": _diagnostic_request_id, "sequence": _diagnostic_sequence,
		"stage": stage, "status": status,
		"details": {"mocapActive": _mocap_active, "mocapFramesApplied": _mocap_frames_applied, "mocapFrameSequence": _mocap_frame_sequence}
	}
	if not reason_code.is_empty():
		payload["reasonCode"] = reason_code
	_post_to_parent(payload)
