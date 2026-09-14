class_name PocketPTRemoteAvatarLoader
extends Node

signal remote_avatar_mounted(presence_id: String, avatar_root: Node3D)
signal remote_avatar_failed(presence_id: String, error_code: String)
signal loader_state_changed(state: Dictionary)

const MAX_AVATAR_BYTES := 32 * 1024 * 1024
const TARGET_HEIGHT_METERS := 1.8
const LOBBY_AVATAR_PREFIX := "/api/game/lobby/players/"

var loader_state: Dictionary = {
	"status": "IDLE",
	"queueCount": 0,
	"loadedCount": 0,
	"lastPresenceId": "",
	"lastError": ""
}

var _queue: Array[Dictionary] = []
var _current: Dictionary = {}
var _request_id := ""
var _download_callback = null
var _download_bytes := PackedByteArray()
var _byte_cache: Dictionary = {}
var _generation := 0

func request_avatar(presence_id: String, member_id: String, descriptor: Dictionary, visual_mount: Node3D) -> bool:
	var validation_error := validate_remote_descriptor(descriptor)
	if presence_id.is_empty() or member_id.is_empty() or visual_mount == null or not is_instance_valid(visual_mount) or not validation_error.is_empty():
		var error_code := validation_error if not validation_error.is_empty() else "REMOTE_AVATAR_REQUEST_INVALID"
		remote_avatar_failed.emit(presence_id, error_code)
		_publish({"lastPresenceId": presence_id, "lastError": error_code})
		return false
	cancel_presence(presence_id)
	_queue.append({
		"presenceId": presence_id,
		"memberId": member_id,
		"descriptor": descriptor.duplicate(true),
		"mount": visual_mount
	})
	_publish({"queueCount": _queue.size(), "lastError": ""})
	_start_next()
	return true

func cancel_presence(presence_id: String) -> void:
	if presence_id.is_empty():
		return
	var retained: Array[Dictionary] = []
	for job in _queue:
		if str(job.get("presenceId", "")) != presence_id:
			retained.append(job)
	_queue = retained
	if not _current.is_empty() and str(_current.get("presenceId", "")) == presence_id:
		_generation += 1
		_current.clear()
		_request_id = ""
		_download_bytes.clear()
		_publish({"status": "IDLE", "queueCount": _queue.size()})
		_start_next()
	else:
		_publish({"queueCount": _queue.size()})

func validate_remote_descriptor(candidate: Variant) -> String:
	if not candidate is Dictionary:
		return "REMOTE_AVATAR_DESCRIPTOR_INVALID"
	var descriptor: Dictionary = candidate
	if str(descriptor.get("format", "")) != "glb":
		return "REMOTE_AVATAR_DESCRIPTOR_INVALID"
	if str(descriptor.get("avatarId", "")).strip_edges().is_empty():
		return "REMOTE_AVATAR_DESCRIPTOR_INVALID"
	var version := str(descriptor.get("profileVersion", ""))
	if not _is_profile_version(version):
		return "REMOTE_AVATAR_DESCRIPTOR_INVALID"
	var asset_url := str(descriptor.get("assetUrl", ""))
	var parts := asset_url.split("?", false, 1)
	if parts.size() != 2:
		return "REMOTE_AVATAR_URL_INVALID"
	var path := str(parts[0])
	var query := str(parts[1])
	if not path.begins_with(LOBBY_AVATAR_PREFIX) or not path.ends_with("/avatar"):
		return "REMOTE_AVATAR_URL_INVALID"
	var middle := path.trim_prefix(LOBBY_AVATAR_PREFIX).trim_suffix("/avatar")
	if middle.is_empty() or middle.contains("/"):
		return "REMOTE_AVATAR_URL_INVALID"
	if query != "version=" + version:
		return "REMOTE_AVATAR_URL_INVALID"
	return ""

func _start_next() -> void:
	if not _current.is_empty() or _queue.is_empty():
		return
	_current = _queue.pop_front()
	var presence_id := str(_current.get("presenceId", ""))
	var descriptor: Dictionary = _current.get("descriptor", {})
	var cache_key := _cache_key(str(_current.get("memberId", "")), descriptor)
	_publish({"status": "LOADING", "queueCount": _queue.size(), "lastPresenceId": presence_id, "lastError": ""})
	if _byte_cache.has(cache_key):
		_import_current(_byte_cache[cache_key])
		return
	_start_browser_download(cache_key)

func _start_browser_download(cache_key: String) -> void:
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		_fail_current("REMOTE_AVATAR_WEB_BRIDGE_UNAVAILABLE")
		return
	var window = JavaScriptBridge.get_interface("window")
	if window == null:
		_fail_current("REMOTE_AVATAR_WEB_BRIDGE_UNAVAILABLE")
		return
	_generation += 1
	var generation := _generation
	var descriptor: Dictionary = _current.get("descriptor", {})
	_request_id = "%s:%d" % [cache_key, generation]
	_download_bytes.clear()
	_download_callback = JavaScriptBridge.create_callback(_on_browser_asset_event)
	window.__pocketptGodotRemoteAvatarCallback = _download_callback
	var request_literal := JSON.stringify(_request_id)
	var url_literal := JSON.stringify(str(descriptor.get("assetUrl", "")))
	var version_literal := JSON.stringify(str(descriptor.get("profileVersion", "")))
	var script := """
(() => {
	const callback = window.__pocketptGodotRemoteAvatarCallback;
	const requestId = %s;
	const assetUrl = %s;
	const version = %s;
	const send = (value) => callback(JSON.stringify(Object.assign({requestId}, value)));
	if (typeof callback !== "function") return false;
	let resolved;
	try {
		resolved = new URL(assetUrl, window.location.origin);
		const keys = Array.from(resolved.searchParams.keys());
		const prefix = "/api/game/lobby/players/";
		const suffix = "/avatar";
		const middle = resolved.pathname.startsWith(prefix) && resolved.pathname.endsWith(suffix)
			? resolved.pathname.slice(prefix.length, resolved.pathname.length - suffix.length)
			: "";
		if (resolved.origin !== window.location.origin ||
			!middle || middle.includes("/") ||
			resolved.username || resolved.password || resolved.hash ||
			keys.length !== 1 || keys[0] !== "version" ||
			resolved.searchParams.get("version") !== version) {
			send({kind: "error", errorCode: "REMOTE_AVATAR_URL_INVALID", status: 0});
			return true;
		}
	} catch (_error) {
		send({kind: "error", errorCode: "REMOTE_AVATAR_URL_INVALID", status: 0});
		return true;
	}
	fetch(resolved.href, {
		method: "GET",
		credentials: "same-origin",
		cache: "no-store",
		headers: {"Accept": "model/gltf-binary, application/octet-stream"}
	})
	.then(async (response) => {
		if (!response.ok) {
			send({kind: "http", status: response.status});
			return;
		}
		const declared = Number(response.headers.get("Content-Length") || 0);
		if (declared > %d) {
			send({kind: "error", errorCode: "REMOTE_AVATAR_TOO_LARGE", status: 200});
			return;
		}
		const bytes = new Uint8Array(await response.arrayBuffer());
		if (bytes.byteLength === 0 || bytes.byteLength > %d) {
			send({kind: "error", errorCode: bytes.byteLength ? "REMOTE_AVATAR_TOO_LARGE" : "REMOTE_AVATAR_DOWNLOAD_INVALID", status: 200});
			return;
		}
		const chunkSize = 196608;
		for (let offset = 0; offset < bytes.byteLength; offset += chunkSize) {
			const chunk = bytes.subarray(offset, Math.min(offset + chunkSize, bytes.byteLength));
			let binary = "";
			for (let i = 0; i < chunk.length; i++) binary += String.fromCharCode(chunk[i]);
			send({kind: "chunk", data: btoa(binary)});
		}
		send({kind: "done", status: 200, byteCount: bytes.byteLength});
	})
	.catch(() => send({kind: "error", errorCode: "REMOTE_AVATAR_DOWNLOAD_FAILED", status: 0}));
	return true;
})()
""" % [request_literal, url_literal, version_literal, MAX_AVATAR_BYTES, MAX_AVATAR_BYTES]
	if JavaScriptBridge.eval(script) != true:
		_fail_current("REMOTE_AVATAR_DOWNLOAD_FAILED")

func _on_browser_asset_event(args: Array) -> void:
	if args.is_empty() or not args[0] is String or _current.is_empty():
		return
	var event = JSON.parse_string(args[0])
	if not event is Dictionary or str(event.get("requestId", "")) != _request_id:
		return
	var kind := str(event.get("kind", ""))
	if kind == "chunk":
		var chunk := Marshalls.base64_to_raw(str(event.get("data", "")))
		if chunk.is_empty() or _download_bytes.size() + chunk.size() > MAX_AVATAR_BYTES:
			_fail_current("REMOTE_AVATAR_TOO_LARGE")
			return
		_download_bytes.append_array(chunk)
		return
	if kind == "http":
		var status := int(event.get("status", 0))
		var code := "ARENA_SESSION_INVALID" if status == 401 else "REMOTE_AVATAR_UNAVAILABLE" if status == 404 else "REMOTE_AVATAR_VERSION_CHANGED" if status == 409 else "REMOTE_AVATAR_DOWNLOAD_FAILED"
		_fail_current(code)
		return
	if kind == "error":
		_fail_current(str(event.get("errorCode", "REMOTE_AVATAR_DOWNLOAD_FAILED")))
		return
	if kind != "done":
		return
	var declared_count := int(event.get("byteCount", -1))
	if declared_count <= 0 or declared_count != _download_bytes.size():
		_fail_current("REMOTE_AVATAR_DOWNLOAD_INVALID")
		return
	var descriptor: Dictionary = _current.get("descriptor", {})
	var cache_key := _cache_key(str(_current.get("memberId", "")), descriptor)
	_byte_cache[cache_key] = _download_bytes.duplicate()
	_import_current(_download_bytes)

func _import_current(bytes: PackedByteArray) -> void:
	if _current.is_empty():
		return
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_buffer(bytes, "", state) != OK:
		_fail_current("REMOTE_AVATAR_IMPORT_FAILED")
		return
	var imported := document.generate_scene(state)
	if imported == null:
		_fail_current("REMOTE_AVATAR_IMPORT_FAILED")
		return
	if imported.find_children("*", "MeshInstance3D", true, false).is_empty():
		imported.queue_free()
		_fail_current("REMOTE_AVATAR_IMPORT_FAILED")
		return
	var mount := _current.get("mount") as Node3D
	if mount == null or not is_instance_valid(mount):
		imported.queue_free()
		_fail_current("REMOTE_AVATAR_MOUNT_MISSING")
		return
	for child in mount.get_children():
		if child.name == "PocketPTRemoteAvatarVisual":
			child.queue_free()
	var wrapper := Node3D.new()
	wrapper.name = "PocketPTRemoteAvatarVisual"
	mount.add_child(wrapper)
	wrapper.add_child(imported)
	var bounds := _calculate_bounds(imported)
	if bounds.size.y > 0.001:
		var uniform_scale := clampf(TARGET_HEIGHT_METERS / bounds.size.y, 0.01, 100.0)
		wrapper.scale = Vector3.ONE * uniform_scale
		var center := bounds.position + bounds.size * 0.5
		var floor_offset := -bounds.position.y * uniform_scale
		wrapper.position = Vector3(-center.x * uniform_scale, floor_offset, -center.z * uniform_scale)
	var presence_id := str(_current.get("presenceId", ""))
	loader_state["loadedCount"] = int(loader_state.get("loadedCount", 0)) + 1
	_publish({"status": "MOUNTED", "lastPresenceId": presence_id, "lastError": ""})
	remote_avatar_mounted.emit(presence_id, wrapper)
	_finish_current()

func _fail_current(error_code: String) -> void:
	var presence_id := str(_current.get("presenceId", "")) if not _current.is_empty() else ""
	_publish({"status": "ERROR", "lastPresenceId": presence_id, "lastError": error_code})
	remote_avatar_failed.emit(presence_id, error_code)
	_finish_current()

func _finish_current() -> void:
	_current.clear()
	_request_id = ""
	_download_bytes.clear()
	_publish({"queueCount": _queue.size()})
	_start_next()

func _calculate_bounds(root: Node3D) -> AABB:
	var combined := AABB()
	var has_bounds := false
	for value in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := value as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var relative := root.global_transform.affine_inverse() * mesh_instance.global_transform
		var transformed := relative * mesh_instance.get_aabb()
		combined = transformed if not has_bounds else combined.merge(transformed)
		has_bounds = true
	return combined

func _cache_key(member_id: String, descriptor: Dictionary) -> String:
	return "%s|%s|%s" % [member_id, str(descriptor.get("avatarId", "")), str(descriptor.get("profileVersion", ""))]

func _is_profile_version(value: String) -> bool:
	if value.length() != 32:
		return false
	for character in value.to_lower():
		if character not in "0123456789abcdef":
			return false
	return true

func _publish(changes: Dictionary) -> void:
	for key in changes:
		loader_state[key] = changes[key]
	loader_state_changed.emit(loader_state.duplicate(true))
