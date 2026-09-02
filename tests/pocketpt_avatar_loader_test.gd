extends SceneTree

const LoaderScript = preload("res://scripts/pocketpt/pocketpt_avatar_loader.gd")

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var host := Node3D.new()
	host.name = "TestHost"
	root.add_child(host)
	var mount := Node3D.new()
	mount.name = "avataranchor"
	host.add_child(mount)
	var fallback := Node3D.new()
	fallback.name = "DefaultAvatar"
	host.add_child(fallback)
	var loader = LoaderScript.new()
	host.add_child(loader)
	loader._visual_mount = mount
	loader._fallback_visual = fallback
	var protocol_client := PocketPTGameClient.new()
	host.add_child(protocol_client)

	var descriptor_a := _descriptor("avatar-a", "0123456789abcdef0123456789abcdef")
	var descriptor_b := _descriptor("avatar-b", "fedcba9876543210fedcba9876543210")
	var canonical_envelope := {"ok": true, "data": _bootstrap("member-a", descriptor_a, _available_state())}
	_expect(protocol_client.validate_bootstrap(canonical_envelope).is_empty(), "Phase 1 canonical bootstrap remains valid")
	protocol_client.bootstrap = canonical_envelope["data"]
	_expect(protocol_client.get_avatar_descriptor()["avatarId"] == "avatar-a", "client exposes avatar descriptor")
	_expect(protocol_client.get_avatar_state()["status"] == "AVAILABLE", "client exposes avatar state")
	_expect(loader.validate_descriptor(descriptor_a, _available_state()).is_empty(), "valid descriptor accepted")
	var bad_format := descriptor_a.duplicate(true)
	bad_format["format"] = "gltf"
	_expect(loader.validate_descriptor(bad_format, _available_state()) == LoaderScript.ERROR_DESCRIPTOR_INVALID, "non-GLB rejected")
	var bad_url := descriptor_a.duplicate(true)
	bad_url["assetUrl"] = "https://evil.example/avatar.glb"
	_expect(loader.validate_descriptor(bad_url, _available_state()).is_empty(), "absolute URL defers exact origin validation to browser")
	var bad_revision := descriptor_a.duplicate(true)
	bad_revision["profileVersion"] = "1"
	_expect(loader.validate_descriptor(bad_revision, _available_state()) == LoaderScript.ERROR_DESCRIPTOR_INVALID, "malformed revision rejected")

	loader.accept_bootstrap_for_test(_bootstrap("member-a", null, _fallback_state("AVATAR_NOT_CONFIGURED")))
	_expect(loader.avatar_state["status"] == "FALLBACK", "null avatar is labelled fallback")
	_expect(bool(loader.avatar_state["fallback"]), "fallback flag is true")
	_expect(fallback.visible, "default visual remains visible")

	var glb := _make_test_glb()
	_expect(not glb.is_empty(), "synthetic GLB generated")
	loader.import_buffer_for_test(glb, "member-a", descriptor_a)
	await process_frame
	_expect(loader.avatar_state["import"] == "PASS", "GLB import passes")
	_expect(loader.avatar_state["mount"] == "PASS", "GLB mount passes")
	_expect(mount.get_child_count() == 1, "exactly one imported presentation mounted")
	_expect(not fallback.visible, "default hidden only after mount")

	loader.import_buffer_for_test(glb, "member-a", descriptor_b)
	await process_frame
	await process_frame
	_expect(loader.avatar_state["mount"] == "PASS", "replacement mounts")
	_expect(mount.get_child_count() == 1, "replacement leaves one presentation")

	loader.accept_bootstrap_for_test(_bootstrap("member-b", null, _fallback_state("AVATAR_NOT_CONFIGURED")))
	await process_frame
	_expect(mount.get_child_count() == 0, "account switch removes prior member visual")
	_expect(fallback.visible, "account switch without avatar restores labelled default")

	loader.accept_bootstrap_for_test(_bootstrap("member-b", null, _fallback_state("AVATAR_ASSET_UNAVAILABLE")))
	_expect(loader.avatar_state["fallback_reason"] == "AVATAR_ASSET_UNAVAILABLE", "documented fallback reason preserved")

	loader.import_buffer_for_test(glb, "member-b", descriptor_a)
	await process_frame
	loader._handle_http_failure(401)
	await process_frame
	_expect(loader.avatar_state["error_code"] == LoaderScript.ERROR_SESSION_EXPIRED, "401 enters session-expired state")
	_expect(mount.get_child_count() == 0, "session expiry removes personal visual")

	loader._client = protocol_client
	loader._rebootstrap_attempted = false
	loader._handle_http_failure(409)
	_expect(loader.avatar_state["status"] == "REFRESHING_DESCRIPTOR", "409 requests one descriptor refresh")
	loader._handle_http_failure(409)
	_expect(loader.avatar_state["error_code"] == LoaderScript.ERROR_VERSION_CHANGED, "second 409 fails without retry loop")

	loader._download_request_id = "current:50"
	loader._generation = 50
	loader._download_bytes.clear()
	loader._on_browser_asset_event([JSON.stringify({"requestId": "stale:49", "kind": "chunk", "data": Marshalls.raw_to_base64(PackedByteArray([1, 2, 3]))})])
	_expect(loader._download_bytes.is_empty(), "late response from stale request discarded")

	for failure in _failures:
		printerr("AVATAR_TEST FAIL: %s" % failure)
	if _failures.is_empty():
		print("AVATAR_TEST PASS: Phase 1 bootstrap, descriptor, fallback, GLB import/mount, replacement, account isolation, expiry, bounded retry, stale discard")
	quit(0 if _failures.is_empty() else 1)

func _descriptor(avatar_id: String, revision: String) -> Dictionary:
	return {
		"avatarId": avatar_id,
		"assetUrl": "/api/game/avatar/asset?version=%s" % revision,
		"profileVersion": revision,
		"format": "glb"
	}

func _available_state() -> Dictionary:
	return {"status": "AVAILABLE", "reason": null, "fallback": "DEFAULT_AVATAR"}

func _fallback_state(reason: String) -> Dictionary:
	return {"status": "FALLBACK", "reason": reason, "fallback": "DEFAULT_AVATAR"}

func _bootstrap(member_id: String, descriptor: Variant, state: Dictionary) -> Dictionary:
	return {
		"protocolVersion": 1,
		"session": {"id": "test", "expiresAt": "2099-01-01T00:00:00Z"},
		"member": {"id": member_id, "displayName": "Test Member"},
		"avatar": descriptor,
		"avatarState": state,
		"experience": {"type": "PUSH_UP_ARENA", "challengeId": "push_up"},
		"api": {"baseUrl": "/api/game"}
	}

func _make_test_glb() -> PackedByteArray:
	var source := Node3D.new()
	source.name = "AvatarFixture"
	var mesh := MeshInstance3D.new()
	mesh.name = "Body"
	mesh.mesh = BoxMesh.new()
	source.add_child(mesh)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_scene(source, state)
	source.free()
	if error != OK:
		return PackedByteArray()
	return document.generate_buffer(state)

func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
