class_name PocketPTAvatarLoader
extends Node

signal avatar_state_changed(state: Dictionary)
signal avatar_mounted(visual_root: Node3D)
signal fallback_activated(reason: String)

const ASSET_PATH := "/api/game/avatar/asset"
const MAX_AVATAR_BYTES := 32 * 1024 * 1024
const TARGET_HEIGHT_METERS := 1.8
const ALLOWED_FALLBACK_REASONS := [
	"AVATAR_NOT_CONFIGURED",
	"AVATAR_ASSET_UNAVAILABLE",
	"AVATAR_SOURCE_UNSUPPORTED",
	"AVATAR_FEATURE_DISABLED",
	"AVATAR_BRIDGE_UNAVAILABLE"
]

const ERROR_DESCRIPTOR_INVALID := "AVATAR_DESCRIPTOR_INVALID"
const ERROR_BROWSER_BRIDGE_UNAVAILABLE := "AVATAR_BROWSER_BRIDGE_UNAVAILABLE"
const ERROR_ASSET_URL_INVALID := "AVATAR_ASSET_URL_INVALID"
const ERROR_DOWNLOAD_FAILED := "AVATAR_DOWNLOAD_FAILED"
const ERROR_DOWNLOAD_TOO_LARGE := "AVATAR_DOWNLOAD_TOO_LARGE"
const ERROR_DOWNLOAD_INVALID := "AVATAR_DOWNLOAD_INVALID"
const ERROR_IMPORT_FAILED := "AVATAR_IMPORT_FAILED"
const ERROR_MOUNT_FAILED := "AVATAR_MOUNT_FAILED"
const ERROR_SESSION_EXPIRED := "ARENA_SESSION_INVALID"
const ERROR_AVATAR_UNAVAILABLE := "ARENA_AVATAR_UNAVAILABLE"
const ERROR_VERSION_CHANGED := "ARENA_AVATAR_VERSION_CHANGED"

var avatar_state: Dictionary = {
	"status": "IDLE",
	"descriptor": "PENDING",
	"download": "PENDING",
	"import": "PENDING",
	"mount": "PENDING",
	"presentation": "UNVERIFIED",
	"fallback": false,
	"fallback_reason": "",
	"error_code": "",
	"http_status": 0,
	"byte_count": 0,
	"mesh_count": 0,
	"skeleton_count": 0,
	"material_count": 0,
	"source_height": 0.0,
	"applied_scale": 1.0,
	"floor_offset": 0.0,
	"facing": "UNVERIFIED",
	"profile_version_short": ""
}

var _client: PocketPTGameClient
var _visual_mount: Node3D
var _fallback_visual: Node3D
var _active_visual: Node3D
var _active_member_id := ""
var _active_cache_key := ""
var _latest_bootstrap: Dictionary = {}
var _generation := 0
var _download_callback = null
var _download_bytes := PackedByteArray()
var _download_request_id := ""
var _download_generation := 0
var _download_descriptor: Dictionary = {}
var _byte_cache: Dictionary = {}
var _rebootstrap_attempted := false
var _waiting_for_rebootstrap := false

func bind(client: PocketPTGameClient, visual_mount: Node3D, fallback_visual: Node3D = null) -> void:
	_client = client
	_visual_mount = visual_mount
	_fallback_visual = fallback_visual
	_client.bootstrap_accepted.connect(_on_bootstrap_accepted)
	_client.session_ending.connect(_on_session_ending)

func retry_avatar() -> void:
	if _latest_bootstrap.is_empty():
		return
	_rebootstrap_attempted = false
	_waiting_for_rebootstrap = false
	_on_bootstrap_accepted(_latest_bootstrap.duplicate(true))

func validate_descriptor(candidate: Variant, state_candidate: Variant) -> String:
	if not candidate is Dictionary or not state_candidate is Dictionary:
		return ERROR_DESCRIPTOR_INVALID
	var descriptor: Dictionary = candidate
	var descriptor_state: Dictionary = state_candidate
	if str(descriptor_state.get("status", "")) != "AVAILABLE":
		return ERROR_DESCRIPTOR_INVALID
	if str(descriptor_state.get("fallback", "")) != "DEFAULT_AVATAR":
		return ERROR_DESCRIPTOR_INVALID
	if str(descriptor.get("format", "")) != "glb":
		return ERROR_DESCRIPTOR_INVALID
	if str(descriptor.get("avatarId", "")).strip_edges().is_empty():
		return ERROR_DESCRIPTOR_INVALID
	var profile_version := str(descriptor.get("profileVersion", ""))
	if not _is_profile_version(profile_version):
		return ERROR_DESCRIPTOR_INVALID
	var asset_url := str(descriptor.get("assetUrl", ""))
	var potentially_canonical := asset_url.begins_with(ASSET_PATH + "?") or asset_url.begins_with("https://") or asset_url.begins_with("http://")
	if asset_url.strip_edges().is_empty() or asset_url.contains("#") or not potentially_canonical:
		return ERROR_ASSET_URL_INVALID
	return ""

func accept_bootstrap_for_test(payload: Dictionary) -> void:
	_on_bootstrap_accepted(payload)

func import_buffer_for_test(bytes: PackedByteArray, member_id: String, descriptor: Dictionary) -> void:
	_generation += 1
	_active_member_id = member_id
	_download_descriptor = descriptor.duplicate(true)
	_import_and_mount(bytes, _generation, member_id, _cache_key(member_id, descriptor))

func _on_bootstrap_accepted(payload: Dictionary) -> void:
	_latest_bootstrap = payload.duplicate(true)
	var member_value = payload.get("member")
	if not member_value is Dictionary:
		_show_fallback(ERROR_DESCRIPTOR_INVALID, ERROR_DESCRIPTOR_INVALID)
		return
	var member_id := str(member_value.get("id", ""))
	if member_id.is_empty():
		_show_fallback(ERROR_DESCRIPTOR_INVALID, ERROR_DESCRIPTOR_INVALID)
		return

	if member_id != _active_member_id:
		_generation += 1
		_download_bytes.clear()
		_byte_cache.clear()
		_remove_active_visual()
		_active_member_id = member_id

	if _waiting_for_rebootstrap:
		_waiting_for_rebootstrap = false
	else:
		_rebootstrap_attempted = false

	var descriptor = payload.get("avatar")
	var descriptor_state = payload.get("avatarState")
	if descriptor == null:
		var fallback_error := _validate_fallback_state(descriptor_state)
		_remove_active_visual()
		if fallback_error.is_empty():
			_show_fallback(str(descriptor_state.get("reason", "AVATAR_NOT_CONFIGURED")), "")
		else:
			_show_fallback(fallback_error, fallback_error)
		return

	var validation_error := validate_descriptor(descriptor, descriptor_state)
	if not validation_error.is_empty():
		_remove_active_visual()
		_show_fallback(validation_error, validation_error)
		return

	var typed_descriptor: Dictionary = descriptor
	var cache_key := _cache_key(member_id, typed_descriptor)
	_publish({
		"status": "LOADING",
		"descriptor": "PASS",
		"download": "PENDING",
		"import": "PENDING",
		"mount": "PENDING",
		"presentation": "UNVERIFIED",
		"fallback": false,
		"fallback_reason": "",
		"error_code": "",
		"http_status": 0,
		"byte_count": 0,
		"mesh_count": 0,
		"skeleton_count": 0,
		"material_count": 0,
		"source_height": 0.0,
		"applied_scale": 1.0,
		"floor_offset": 0.0,
		"facing": "SOURCE_FORWARD_UNVERIFIED",
		"profile_version_short": _short_revision(str(typed_descriptor["profileVersion"]))
	})
	if _byte_cache.has(cache_key):
		_generation += 1
		_import_and_mount(_byte_cache[cache_key], _generation, member_id, cache_key)
		return
	_start_browser_download(typed_descriptor, member_id, cache_key)

func _start_browser_download(descriptor: Dictionary, member_id: String, cache_key: String) -> void:
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		_show_fallback(ERROR_BROWSER_BRIDGE_UNAVAILABLE, ERROR_BROWSER_BRIDGE_UNAVAILABLE, "download")
		return
	var window = JavaScriptBridge.get_interface("window")
	if window == null:
		_show_fallback(ERROR_BROWSER_BRIDGE_UNAVAILABLE, ERROR_BROWSER_BRIDGE_UNAVAILABLE, "download")
		return

	_generation += 1
	var generation := _generation
	_download_generation = generation
	_download_request_id = "%s:%d" % [cache_key, generation]
	_download_descriptor = descriptor.duplicate(true)
	_download_bytes.clear()
	_download_callback = JavaScriptBridge.create_callback(_on_browser_asset_event)
	window.__pocketptGodotAvatarCallback = _download_callback
	var request_literal := JSON.stringify(_download_request_id)
	var url_literal := JSON.stringify(str(descriptor["assetUrl"]))
	var revision_literal := JSON.stringify(str(descriptor["profileVersion"]))
	var script := """
(() => {
	const callback = window.__pocketptGodotAvatarCallback;
	const requestId = %s;
	const assetUrl = %s;
	const revision = %s;
	const send = (value) => callback(JSON.stringify(Object.assign({requestId}, value)));
	if (typeof callback !== "function") return false;
	let resolved;
	try {
		resolved = new URL(assetUrl, window.location.origin);
		const keys = Array.from(resolved.searchParams.keys());
		if (resolved.origin !== window.location.origin ||
			resolved.pathname !== "/api/game/avatar/asset" ||
			resolved.username || resolved.password || resolved.hash ||
			keys.length !== 1 || keys[0] !== "version" ||
			resolved.searchParams.get("version") !== revision) {
			send({kind: "error", errorCode: "AVATAR_ASSET_URL_INVALID", status: 0});
			return true;
		}
	} catch (_error) {
		send({kind: "error", errorCode: "AVATAR_ASSET_URL_INVALID", status: 0});
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
			send({kind: "error", errorCode: "AVATAR_DOWNLOAD_TOO_LARGE", status: 200});
			return;
		}
		const bytes = new Uint8Array(await response.arrayBuffer());
		if (bytes.byteLength === 0 || bytes.byteLength > %d) {
			send({kind: "error", errorCode: bytes.byteLength ? "AVATAR_DOWNLOAD_TOO_LARGE" : "AVATAR_DOWNLOAD_INVALID", status: 200});
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
	.catch(() => send({kind: "error", errorCode: "AVATAR_DOWNLOAD_FAILED", status: 0}));
	return true;
})()
""" % [request_literal, url_literal, revision_literal, MAX_AVATAR_BYTES, MAX_AVATAR_BYTES]
	if JavaScriptBridge.eval(script) != true:
		_show_fallback(ERROR_DOWNLOAD_FAILED, ERROR_DOWNLOAD_FAILED, "download")

func _on_browser_asset_event(args: Array) -> void:
	if args.is_empty() or not args[0] is String:
		return
	var event = JSON.parse_string(args[0])
	if not event is Dictionary or str(event.get("requestId", "")) != _download_request_id:
		return
	if _download_generation != _generation:
		return
	var kind := str(event.get("kind", ""))
	if kind == "chunk":
		var chunk := Marshalls.base64_to_raw(str(event.get("data", "")))
		if chunk.is_empty() or _download_bytes.size() + chunk.size() > MAX_AVATAR_BYTES:
			_generation += 1
			_show_fallback(ERROR_DOWNLOAD_TOO_LARGE, ERROR_DOWNLOAD_TOO_LARGE, "download")
			return
		_download_bytes.append_array(chunk)
		return
	if kind == "http":
		_handle_http_failure(int(event.get("status", 0)))
		return
	if kind == "error":
		_show_fallback(str(event.get("errorCode", ERROR_DOWNLOAD_FAILED)), str(event.get("errorCode", ERROR_DOWNLOAD_FAILED)), "download")
		return
	if kind != "done":
		return
	var declared_count := int(event.get("byteCount", -1))
	if declared_count <= 0 or declared_count != _download_bytes.size():
		_show_fallback(ERROR_DOWNLOAD_INVALID, ERROR_DOWNLOAD_INVALID, "download")
		return
	var member_id := _active_member_id
	var descriptor := _download_descriptor.duplicate(true)
	var cache_key := _cache_key(member_id, descriptor)
	_byte_cache[cache_key] = _download_bytes.duplicate()
	_publish({"download": "PASS", "http_status": 200, "byte_count": declared_count})
	_import_and_mount(_download_bytes, _generation, member_id, cache_key)

func _handle_http_failure(status: int) -> void:
	_publish({"http_status": status})
	if status == 401:
		_remove_active_visual()
		_show_fallback(ERROR_SESSION_EXPIRED, ERROR_SESSION_EXPIRED, "download")
		return
	if status == 404:
		if _request_rebootstrap_once():
			return
		_remove_active_visual()
		_show_fallback(ERROR_AVATAR_UNAVAILABLE, ERROR_AVATAR_UNAVAILABLE, "download")
		return
	if status == 409:
		if _request_rebootstrap_once():
			return
		_remove_active_visual()
		_show_fallback(ERROR_VERSION_CHANGED, ERROR_VERSION_CHANGED, "download")
		return
	_show_fallback(ERROR_DOWNLOAD_FAILED, ERROR_DOWNLOAD_FAILED, "download")

func _request_rebootstrap_once() -> bool:
	if _rebootstrap_attempted or _client == null:
		return false
	_rebootstrap_attempted = true
	_waiting_for_rebootstrap = true
	_generation += 1
	_download_bytes.clear()
	_publish({"status": "REFRESHING_DESCRIPTOR", "download": "REBOOTSTRAP", "error_code": ""})
	_client.fetch_bootstrap()
	return true

func _import_and_mount(bytes: PackedByteArray, generation: int, member_id: String, cache_key: String) -> void:
	if generation != _generation or member_id != _active_member_id:
		return
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var import_error := document.append_from_buffer(bytes, "", state)
	if import_error != OK:
		_show_fallback(ERROR_IMPORT_FAILED, ERROR_IMPORT_FAILED, "import")
		return
	var imported := document.generate_scene(state)
	if imported == null:
		_show_fallback(ERROR_IMPORT_FAILED, ERROR_IMPORT_FAILED, "import")
		return
	var mesh_count := imported.find_children("*", "MeshInstance3D", true, false).size()
	var skeleton_count := imported.find_children("*", "Skeleton3D", true, false).size()
	var material_count := _count_materials(imported)
	if mesh_count == 0:
		imported.queue_free()
		_show_fallback(ERROR_IMPORT_FAILED, ERROR_IMPORT_FAILED, "import")
		return
	_publish({"import": "PASS", "mesh_count": mesh_count, "skeleton_count": skeleton_count, "material_count": material_count})
	_mount_imported(imported, generation, member_id, cache_key)

func _mount_imported(imported: Node, generation: int, member_id: String, cache_key: String) -> void:
	if generation != _generation or member_id != _active_member_id or _visual_mount == null or not is_instance_valid(_visual_mount):
		imported.queue_free()
		_show_fallback(ERROR_MOUNT_FAILED, ERROR_MOUNT_FAILED, "mount")
		return
	var wrapper := Node3D.new()
	wrapper.name = "PocketPTAvatarVisual"
	_visual_mount.add_child(wrapper)
	wrapper.add_child(imported)
	var bounds := _calculate_bounds(imported)
	var uniform_scale := 1.0
	var floor_offset := 0.0
	if bounds.size.y > 0.001:
		uniform_scale = clampf(TARGET_HEIGHT_METERS / bounds.size.y, 0.01, 100.0)
		wrapper.scale = Vector3.ONE * uniform_scale
		var center := bounds.position + bounds.size * 0.5
		floor_offset = -bounds.position.y * uniform_scale
		wrapper.position = Vector3(-center.x * uniform_scale, floor_offset, -center.z * uniform_scale)
	if generation != _generation or member_id != _active_member_id:
		wrapper.queue_free()
		return
	_remove_active_visual()
	_active_visual = wrapper
	_active_cache_key = cache_key
	_set_fallback_visible(false)
	_publish({
		"status": "MOUNTED",
		"mount": "PASS",
		"presentation": "AWAITING_VISUAL_REVIEW",
		"fallback": false,
		"fallback_reason": "",
		"error_code": "",
		"source_height": bounds.size.y,
		"applied_scale": uniform_scale,
		"floor_offset": floor_offset,
		"facing": "SOURCE_FORWARD_UNVERIFIED"
	})
	avatar_mounted.emit(wrapper)

func _calculate_bounds(root: Node3D) -> AABB:
	var combined := AABB()
	var has_bounds := false
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	for value in meshes:
		var mesh_instance := value as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var relative := root.global_transform.affine_inverse() * mesh_instance.global_transform
		var transformed := relative * mesh_instance.get_aabb()
		combined = transformed if not has_bounds else combined.merge(transformed)
		has_bounds = true
	return combined

func _count_materials(root: Node) -> int:
	var count := 0
	for value in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := value as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		for surface_index in mesh_instance.mesh.get_surface_count():
			if mesh_instance.get_active_material(surface_index) != null:
				count += 1
	return count

func _show_fallback(reason: String, error_code: String, failure_stage := "descriptor") -> void:
	_generation += 1
	_download_bytes.clear()
	var retaining_previous := _active_visual != null and is_instance_valid(_active_visual)
	_set_fallback_visible(not retaining_previous)
	var descriptor_result := "FALLBACK" if error_code.is_empty() else "FAIL"
	var download_result := "NOT_RUN"
	var import_result := "NOT_RUN"
	if failure_stage != "descriptor":
		descriptor_result = "PASS"
	if failure_stage == "download":
		download_result = "FAIL"
	elif failure_stage == "import":
		download_result = "PASS"
		import_result = "FAIL"
	elif failure_stage == "mount":
		download_result = "PASS"
		import_result = "PASS"
	_publish({
		"status": "FALLBACK" if error_code.is_empty() else "ERROR",
		"descriptor": descriptor_result,
		"download": download_result,
		"import": import_result,
		"mount": "PREVIOUS_AVATAR_RETAINED" if retaining_previous else "DEFAULT_AVATAR",
		"presentation": "STALE_NOT_ACCEPTED" if retaining_previous else "FALLBACK_LABELLED",
		"fallback": not retaining_previous,
		"fallback_reason": reason,
		"error_code": error_code
	})
	fallback_activated.emit(reason)

func _validate_fallback_state(candidate: Variant) -> String:
	if not candidate is Dictionary:
		return ERROR_DESCRIPTOR_INVALID
	if str(candidate.get("status", "")) != "FALLBACK":
		return ERROR_DESCRIPTOR_INVALID
	if str(candidate.get("fallback", "")) != "DEFAULT_AVATAR":
		return ERROR_DESCRIPTOR_INVALID
	if str(candidate.get("reason", "")) not in ALLOWED_FALLBACK_REASONS:
		return ERROR_DESCRIPTOR_INVALID
	return ""

func _is_profile_version(value: String) -> bool:
	if value.length() != 32:
		return false
	for character in value.to_lower():
		if character not in "0123456789abcdef":
			return false
	return true

func _cache_key(member_id: String, descriptor: Dictionary) -> String:
	return "%s|%s|%s" % [member_id, str(descriptor.get("avatarId", "")), str(descriptor.get("profileVersion", ""))]

func _short_revision(value: String) -> String:
	return value.left(8) + "…" if value.length() > 8 else value

func _set_fallback_visible(value: bool) -> void:
	if _fallback_visual != null and is_instance_valid(_fallback_visual):
		_fallback_visual.visible = value

func _remove_active_visual() -> void:
	if _active_visual != null and is_instance_valid(_active_visual):
		_active_visual.queue_free()
	_active_visual = null
	_active_cache_key = ""

func _on_session_ending() -> void:
	_generation += 1
	_download_bytes.clear()
	_byte_cache.clear()
	_latest_bootstrap.clear()
	_active_member_id = ""
	_remove_active_visual()
	_set_fallback_visible(true)
	_publish({"status": "SESSION_ENDED", "mount": "DEFAULT_AVATAR", "fallback": true, "fallback_reason": "SESSION_ENDED"})

func _publish(changes: Dictionary) -> void:
	for key in changes:
		avatar_state[key] = changes[key]
	avatar_state_changed.emit(avatar_state.duplicate(true))
