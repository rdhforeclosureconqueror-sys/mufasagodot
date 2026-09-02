class_name PocketPTBridgeDebug
extends CanvasLayer

var client: PocketPTGameClient
var avatar_loader: Node
var value_labels: Dictionary = {}
var panel: PanelContainer

func _ready() -> void:
	layer = 100
	_build_ui()

func bind_client(value: PocketPTGameClient) -> void:
	client = value
	client.connection_state_changed.connect(_on_connection_state_changed)
	_on_connection_state_changed(client.connection_state)

func _build_ui() -> void:
	panel = PanelContainer.new()
	panel.name = "ConnectionDebugPanel"
	panel.position = Vector2(24, 180)
	panel.custom_minimum_size = Vector2(480, 590)
	add_child(panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.03, 0.04, 0.94)
	style.border_color = Color(0.18, 0.75, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 7)
	panel.add_child(stack)

	var title := Label.new()
	title.text = "UNLEASH THE BEAST"
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", Color(0.95, 0.12, 0.14))
	stack.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "POCKETPT WORLD BRIDGE • PHASE 2"
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.65, 0.72, 0.80))
	stack.add_child(subtitle)

	var separator := HSeparator.new()
	stack.add_child(separator)

	_add_row(stack, "connection", "PocketPT Connection:", "INITIALIZING")
	_add_row(stack, "member", "Member:", "—")
	_add_row(stack, "member_id", "Member ID:", "—")
	_add_row(stack, "protocol", "Protocol:", "—")
	_add_row(stack, "experience", "Experience:", "—")
	_add_row(stack, "challenge", "Challenge:", "—")
	_add_row(stack, "bootstrap", "Bootstrap:", "PENDING")
	_add_row(stack, "handshake", "Parent Handshake:", "PENDING")
	_add_row(stack, "error", "Safe Error Code:", "—")
	_add_row(stack, "avatar_descriptor", "Avatar Descriptor:", "PENDING")
	_add_row(stack, "avatar_download", "Avatar Download:", "PENDING")
	_add_row(stack, "avatar_import", "Avatar Import:", "PENDING")
	_add_row(stack, "avatar_mount", "Avatar Mount:", "PENDING")
	_add_row(stack, "avatar_reason", "Avatar Detail:", "—")

	var note := Label.new()
	note.name = "ModeNotice"
	note.text = "Production Web mode uses the scoped PocketPT browser session.\nDesktop runs do not authenticate and cannot report acceptance."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color(0.62, 0.67, 0.72))
	stack.add_child(note)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	stack.add_child(buttons)
	var retry := Button.new()
	retry.name = "RetryButton"
	retry.text = "Retry Bootstrap"
	retry.pressed.connect(_on_retry_pressed)
	buttons.add_child(retry)
	var exit := Button.new()
	exit.name = "ExitArenaButton"
	exit.text = "Exit Arena"
	exit.pressed.connect(_on_exit_pressed)
	buttons.add_child(exit)
	var retry_avatar := Button.new()
	retry_avatar.name = "RetryAvatarButton"
	retry_avatar.text = "Retry Avatar"
	retry_avatar.pressed.connect(_on_retry_avatar_pressed)
	buttons.add_child(retry_avatar)

func bind_avatar_loader(value: Node) -> void:
	avatar_loader = value
	avatar_loader.avatar_state_changed.connect(_on_avatar_state_changed)
	_on_avatar_state_changed(avatar_loader.avatar_state)

func _add_row(stack: VBoxContainer, key: String, caption: String, initial: String) -> void:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = caption
	name_label.custom_minimum_size.x = 170
	name_label.add_theme_color_override("font_color", Color(0.72, 0.77, 0.84))
	row.add_child(name_label)
	var value := Label.new()
	value.text = initial
	value.add_theme_color_override("font_color", Color.WHITE)
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value)
	value_labels[key] = value
	stack.add_child(row)

func _on_connection_state_changed(state: Dictionary) -> void:
	if value_labels.is_empty():
		return
	var status := str(state.get("status", "IDLE"))
	value_labels["connection"].text = status
	value_labels["member"].text = _display_or_dash(state.get("display_name", ""))
	value_labels["member_id"].text = _display_or_dash(state.get("member_id_short", ""))
	var protocol := int(state.get("protocol_version", 0))
	value_labels["protocol"].text = "v%d" % protocol if protocol > 0 else "—"
	value_labels["experience"].text = _display_or_dash(state.get("experience", ""))
	value_labels["challenge"].text = _display_or_dash(state.get("challenge_id", ""))
	value_labels["bootstrap"].text = "PASS" if bool(state.get("bootstrap_valid", false)) else "PENDING"
	value_labels["handshake"].text = "PASS" if bool(state.get("parent_handshake", false)) else "PENDING"
	value_labels["error"].text = _display_or_dash(state.get("error_code", ""))

	var success := status == "CONNECTED" and bool(state.get("parent_handshake", false))
	var color := Color(0.25, 1.0, 0.55) if success else Color(1.0, 0.80, 0.25)
	if status == "ERROR":
		color = Color(1.0, 0.28, 0.25)
	value_labels["connection"].add_theme_color_override("font_color", color)

func _display_or_dash(value: Variant) -> String:
	var text := str(value)
	return text if not text.is_empty() else "—"

func _on_retry_pressed() -> void:
	if client:
		client.fetch_bootstrap()

func _on_retry_avatar_pressed() -> void:
	if avatar_loader:
		avatar_loader.retry_avatar()

func _on_avatar_state_changed(state: Dictionary) -> void:
	if value_labels.is_empty():
		return
	value_labels["avatar_descriptor"].text = _display_or_dash(state.get("descriptor", ""))
	var download := str(state.get("download", ""))
	var bytes := int(state.get("byte_count", 0))
	if bytes > 0:
		download += " (%d bytes)" % bytes
	value_labels["avatar_download"].text = _display_or_dash(download)
	var import_text := str(state.get("import", ""))
	if import_text == "PASS":
		import_text += " (%d mesh, %d skeleton)" % [int(state.get("mesh_count", 0)), int(state.get("skeleton_count", 0))]
	value_labels["avatar_import"].text = _display_or_dash(import_text)
	value_labels["avatar_mount"].text = _display_or_dash(state.get("mount", ""))
	var detail := str(state.get("error_code", ""))
	if detail.is_empty():
		detail = str(state.get("fallback_reason", ""))
	if detail.is_empty():
		detail = str(state.get("profile_version_short", ""))
	value_labels["avatar_reason"].text = _display_or_dash(detail)

func _on_exit_pressed() -> void:
	if not client or not client.request_exit():
		if value_labels.has("error"):
			value_labels["error"].text = PocketPTGameClient.ERROR_PARENT_HANDSHAKE_FAILED
