class_name PocketPTGameClient
extends Node

signal connection_state_changed(state: Dictionary)
signal bootstrap_accepted(bootstrap: Dictionary)

const PROTOCOL_VERSION := 1
const EXPECTED_EXPERIENCE := "PUSH_UP_ARENA"
const EXPECTED_CHALLENGE := "push_up"
const BOOTSTRAP_PATH := "/api/game/bootstrap"

const ERROR_BOOTSTRAP_REQUEST_FAILED := "BOOTSTRAP_REQUEST_FAILED"
const ERROR_BOOTSTRAP_HTTP_FAILED := "BOOTSTRAP_HTTP_FAILED"
const ERROR_BOOTSTRAP_INVALID_JSON := "BOOTSTRAP_INVALID_JSON"
const ERROR_PROTOCOL_VERSION_MISMATCH := "PROTOCOL_VERSION_MISMATCH"
const ERROR_MEMBER_MISSING := "MEMBER_MISSING"
const ERROR_EXPERIENCE_MISMATCH := "EXPERIENCE_MISMATCH"
const ERROR_CHALLENGE_MISMATCH := "CHALLENGE_MISMATCH"
const ERROR_API_BASE_MISSING := "API_BASE_MISSING"
const ERROR_BROWSER_BRIDGE_UNAVAILABLE := "BROWSER_BRIDGE_UNAVAILABLE"
const ERROR_PARENT_HANDSHAKE_FAILED := "PARENT_HANDSHAKE_FAILED"
const ERROR_WEB_EXPORT_UNSUPPORTED := "WEB_EXPORT_UNSUPPORTED"

var connection_state: Dictionary = {
	"status": "IDLE",
	"error_code": "",
	"bootstrap_valid": false,
	"parent_handshake": false,
	"protocol_version": 0,
	"display_name": "",
	"member_id_short": "",
	"experience": "",
	"challenge_id": ""
}

var bootstrap: Dictionary = {}
var _bootstrap_callback = null
var _parent_handshake_callback = null
var _request_in_flight := false

func initialize() -> void:
	fetch_bootstrap()

func fetch_bootstrap() -> void:
	if _request_in_flight:
		return
	if not OS.has_feature("web"):
		report_error(ERROR_WEB_EXPORT_UNSUPPORTED)
		return
	if not Engine.has_singleton("JavaScriptBridge"):
		report_error(ERROR_BROWSER_BRIDGE_UNAVAILABLE)
		return
	_request_in_flight = true
	_publish_state({"status": "CONNECTING", "error_code": ""})
	_bootstrap_callback = JavaScriptBridge.create_callback(_on_browser_bootstrap_result)
	var window = JavaScriptBridge.get_interface("window")
	if window == null:
		_request_in_flight = false
		report_error(ERROR_BROWSER_BRIDGE_UNAVAILABLE)
		return
	window.__pocketptGodotBootstrapCallback = _bootstrap_callback
	var script := """
(() => {
	const callback = window.__pocketptGodotBootstrapCallback;
	if (typeof callback !== "function") {
		return false;
	}
	fetch("/api/game/bootstrap", {
		method: "GET",
		credentials: "include",
		cache: "no-store",
		headers: { "Accept": "application/json" }
	})
	.then(async (response) => {
		const body = await response.text();
		callback(JSON.stringify({
			ok: response.ok,
			status: response.status,
			body: body
		}));
	})
	.catch(() => {
		callback(JSON.stringify({
			ok: false,
			status: 0,
			networkError: true
		}));
	});
	return true;
})()
"""
	var started = JavaScriptBridge.eval(script)
	if started != true:
		_request_in_flight = false
		report_error(ERROR_BOOTSTRAP_REQUEST_FAILED)

func validate_bootstrap(candidate: Variant) -> String:
	if not candidate is Dictionary:
		return ERROR_BOOTSTRAP_INVALID_JSON
	var envelope: Dictionary = candidate
	if envelope.get("ok") != true:
		return ERROR_BOOTSTRAP_INVALID_JSON
	var data = envelope.get("data")
	if not data is Dictionary:
		return ERROR_BOOTSTRAP_INVALID_JSON
	var payload: Dictionary = data
	var protocol_version = payload.get("protocolVersion")
	if typeof(protocol_version) not in [TYPE_INT, TYPE_FLOAT] or float(protocol_version) != float(PROTOCOL_VERSION):
		return ERROR_PROTOCOL_VERSION_MISMATCH
	var member = payload.get("member")
	if not member is Dictionary or str(member.get("id", "")).strip_edges().is_empty():
		return ERROR_MEMBER_MISSING
	var experience = payload.get("experience")
	if not experience is Dictionary:
		return ERROR_EXPERIENCE_MISMATCH
	if str(experience.get("type", "")) != EXPECTED_EXPERIENCE:
		return ERROR_EXPERIENCE_MISMATCH
	if str(experience.get("challengeId", "")) != EXPECTED_CHALLENGE:
		return ERROR_CHALLENGE_MISMATCH
	var api = payload.get("api")
	if not api is Dictionary or str(api.get("baseUrl", "")).strip_edges().is_empty():
		return ERROR_API_BASE_MISSING
	return ""

func report_ready() -> void:
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		report_error(ERROR_PARENT_HANDSHAKE_FAILED)
		return
	var window = JavaScriptBridge.get_interface("window")
	if window == null:
		report_error(ERROR_PARENT_HANDSHAKE_FAILED)
		return
	_parent_handshake_callback = JavaScriptBridge.create_callback(_on_parent_handshake_result)
	window.__pocketptGodotHandshakeCallback = _parent_handshake_callback
	var payload := {
		"type": "POCKETPT_GODOT_BRIDGE",
		"event": "READY",
		"protocolVersion": PROTOCOL_VERSION,
		"experience": EXPECTED_EXPERIENCE,
		"challengeId": EXPECTED_CHALLENGE
	}
	var serialized := JSON.stringify(payload)
	var serialized_literal := JSON.stringify(serialized)
	var script := """
(() => {
	const callback = window.__pocketptGodotHandshakeCallback;
	if (typeof callback !== "function") {
		return;
	}
	try {
		if (window.parent === window || !window.location.origin) {
			callback("INVALID_CONTEXT");
			return;
		}
		const payload = JSON.parse(%s);
		window.parent.postMessage(payload, window.location.origin);
		callback("SENT");
	} catch (_error) {
		callback("ERROR");
	}
})()
""" % serialized_literal
	JavaScriptBridge.eval(script)

func report_error(error_code: String) -> void:
	_request_in_flight = false
	_publish_state({
		"status": "ERROR",
		"error_code": error_code,
		"parent_handshake": false
	})
	_post_error_to_parent(error_code)

func request_exit() -> bool:
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		return false
	var payload := {
		"type": "POCKETPT_GODOT_BRIDGE",
		"status": "EXIT_REQUESTED"
	}
	var serialized_literal := JSON.stringify(JSON.stringify(payload))
	var script := """
(() => {
	if (window.parent === window || !window.location.origin) {
		return false;
	}
	window.parent.postMessage(JSON.parse(%s), window.location.origin);
	return true;
})()
""" % serialized_literal
	return JavaScriptBridge.eval(script) == true

func debug_validate_mock() -> Dictionary:
	var fixture := {
		"ok": true,
		"data": {
			"protocolVersion": 1,
			"session": {"id": "mock-session", "expiresAt": "2099-01-01T00:00:00Z"},
			"member": {"id": "mock-member", "displayName": "PocketPT Member"},
			"avatar": null,
			"experience": {"type": "PUSH_UP_ARENA", "challengeId": "push_up"},
			"api": {"baseUrl": "/api/game"}
		}
	}
	var validation_error := validate_bootstrap(fixture)
	if not validation_error.is_empty():
		return {"ok": false, "error_code": validation_error}
	var safe_state := _safe_state_from_bootstrap(fixture["data"])
	safe_state["status"] = "MOCK_VALIDATED"
	safe_state["error_code"] = ""
	safe_state["bootstrap_valid"] = true
	safe_state["parent_handshake"] = false
	_publish_state(safe_state)
	return {"ok": true, "mock": true, "state": connection_state.duplicate(true)}

func _on_browser_bootstrap_result(args: Array) -> void:
	_request_in_flight = false
	if args.is_empty() or not args[0] is String:
		report_error(ERROR_BOOTSTRAP_REQUEST_FAILED)
		return
	var envelope = JSON.parse_string(args[0])
	if not envelope is Dictionary:
		report_error(ERROR_BOOTSTRAP_REQUEST_FAILED)
		return
	if bool(envelope.get("networkError", false)):
		report_error(ERROR_BOOTSTRAP_REQUEST_FAILED)
		return
	if not bool(envelope.get("ok", false)):
		report_error(ERROR_BOOTSTRAP_HTTP_FAILED)
		return
	var parsed = JSON.parse_string(str(envelope.get("body", "")))
	if not parsed is Dictionary:
		report_error(ERROR_BOOTSTRAP_INVALID_JSON)
		return
	var validation_error := validate_bootstrap(parsed)
	if not validation_error.is_empty():
		report_error(validation_error)
		return
	bootstrap = parsed["data"]
	var safe_state := _safe_state_from_bootstrap(bootstrap)
	safe_state["status"] = "CONNECTED"
	safe_state["bootstrap_valid"] = true
	_publish_state(safe_state)
	bootstrap_accepted.emit(bootstrap.duplicate(true))
	report_ready()

func _on_parent_handshake_result(args: Array) -> void:
	if not args.is_empty() and str(args[0]) == "SENT":
		_publish_state({"status": "READY", "parent_handshake": true, "error_code": ""})
		return
	report_error(ERROR_PARENT_HANDSHAKE_FAILED)

func _safe_state_from_bootstrap(payload: Dictionary) -> Dictionary:
	var member: Dictionary = payload["member"]
	var experience: Dictionary = payload["experience"]
	var member_id := str(member.get("id", ""))
	return {
		"protocol_version": int(payload.get("protocolVersion", 0)),
		"display_name": str(member.get("displayName", "PocketPT Member")),
		"member_id_short": _short_member_id(member_id),
		"experience": str(experience.get("type", "")),
		"challenge_id": str(experience.get("challengeId", ""))
	}

func _short_member_id(value: String) -> String:
	if value.length() <= 10:
		return value
	return value.left(6) + "…" + value.right(4)

func _post_error_to_parent(error_code: String) -> void:
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		return
	var payload := {
		"type": "POCKETPT_GODOT_BRIDGE",
		"event": "ERROR",
		"errorCode": error_code
	}
	var serialized_literal := JSON.stringify(JSON.stringify(payload))
	var script := """
(() => {
	if (window.parent === window || !window.location.origin) {
		return false;
	}
	window.parent.postMessage(JSON.parse(%s), window.location.origin);
	return true;
})()
""" % serialized_literal
	JavaScriptBridge.eval(script)

func _publish_state(changes: Dictionary) -> void:
	for key in changes:
		connection_state[key] = changes[key]
	connection_state_changed.emit(connection_state.duplicate(true))
