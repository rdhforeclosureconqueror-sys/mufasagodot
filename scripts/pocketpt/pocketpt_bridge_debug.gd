class_name PocketPTBridgeDebug
extends CanvasLayer

var client: PocketPTGameClient
var avatar_loader: Node
var phone_flow: Node
var player: GymPlayerController
var output: TextEdit

func _ready() -> void:
	layer = 100
	var panel := PanelContainer.new()
	panel.name = "PocketPTConsolidatedDiagnostics"
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(470, 610)
	add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.018, 0.022, 0.03, 0.94)
	style.border_color = Color(0.92, 0.06, 0.08)
	style.set_border_width_all(2)
	style.set_corner_radius_all(9)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	var stack := VBoxContainer.new()
	panel.add_child(stack)
	var title := Label.new()
	title.text = "POCKETPT PUSH-UP ARENA DIAGNOSTICS"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.24, 0.18))
	stack.add_child(title)
	output = TextEdit.new()
	output.name = "CopyablePipelineDiagnostics"
	output.editable = false
	output.custom_minimum_size = Vector2(440, 535)
	output.add_theme_font_size_override("font_size", 13)
	output.add_theme_color_override("font_color", Color(0.82, 0.88, 0.95))
	stack.add_child(output)

func bind_client(value: PocketPTGameClient) -> void:
	client = value

func bind_avatar_loader(value: Node) -> void:
	avatar_loader = value

func bind_runtime(flow: Node, controller: GymPlayerController) -> void:
	phone_flow = flow
	player = controller

func _process(_delta: float) -> void:
	if output == null:
		return
	var web := OS.has_feature("web")
	var connection: Dictionary = client.connection_state if client != null else {}
	var flow_state: Dictionary = phone_flow.state if phone_flow != null else {}
	var avatar: Dictionary = avatar_loader.avatar_state if avatar_loader != null else {}
	var floor_found := not get_tree().get_nodes_in_group("pocketpt_floor_collision").is_empty()
	var nav_found := not get_tree().get_nodes_in_group("pocketpt_navigation_region").is_empty()
	var mat_found := not get_tree().get_nodes_in_group("pocketpt_mat_target").is_empty()
	var mufasa_found := not get_tree().get_nodes_in_group("pocketpt_mufasa").is_empty()
	var collision_found := player != null and player.get_node_or_null("CollisionShape3D") != null
	var grounded := player != null and player.is_on_floor()
	var nav_ready := player != null and player.navigation_ready()
	var first_failure := "NONE"
	if player == null: first_failure = "PLAYER CONTROLLER"
	elif not collision_found: first_failure = "PLAYER COLLISION"
	elif not floor_found: first_failure = "FLOOR COLLISION"
	elif not nav_found: first_failure = "NAVIGATION REGION"
	elif not mufasa_found: first_failure = "MUFASA ASSET"
	elif web and str(connection.get("status", "")) == "ERROR": first_failure = "POCKETPT PAGE / IFRAME HANDSHAKE"
	var animation_name := "NONE"
	if phone_flow != null and phone_flow._animation_player != null:
		animation_name = str(phone_flow._animation_player.current_animation)
	var visual_anchor := player.get_node_or_null("avataranchor") as Node3D if player != null else null
	var feet_offset := float(avatar.get("floor_offset", 0.0)) + visual_anchor.position.y if avatar_loader != null and visual_anchor != null else 0.0
	output.text = """POCKETPT PAGE: %s
→ IFRAME: %s
 → GODOT READY: %s
→ FLOW NEGOTIATION: %s
→ CONTROL RECEIVED: %s
→ PLAYER CONTROLLER: %s
→ COLLISION/GROUND: %s
→ VELOCITY: %s
→ LOCOMOTION ANIMATION: %s
→ NAVIGATION: %s
→ MAT ARRIVAL: %s
→ MUFASA ASSET: %s
→ RENDER: %d FPS

PLAYER_BODY_FOUND: %s
PLAYER_COLLISION_FOUND: %s
FLOOR_COLLISION_FOUND: %s
GROUND_CHECK: %s
PLAYER_GROUNDED: %s
PLAYER_ROOT_Y: %.3f
VISUAL_FEET_OFFSET: %.3f

MOVE_COMMAND_RECEIVED: %s
MOVE_VECTOR: %s
CHARACTER_VELOCITY: %s
ACTIVE_LOCOMOTION: %s
ANIMATION_PLAYING: %s
GROUND_STATE: %s

FIRST FAILURE: %s""" % [
		"CONNECTED" if bool(connection.get("bootstrap_valid", false)) else ("DESKTOP TEST" if not web else "PENDING"),
		"READY" if bool(connection.get("parent_handshake", false)) else ("DESKTOP TEST" if not web else "PENDING"),
		"YES" if bool(connection.get("parent_handshake", false)) else ("DESKTOP TEST" if not web else "NO"),
		"CONNECTED" if bool(flow_state.get("connected", false)) else "PENDING", str(flow_state.get("last_action", "NONE")),
		"FOUND" if player != null else "MISSING", ("GROUNDED" if grounded else "AIRBORNE") if collision_found and floor_found else "MISSING",
		str(player.velocity if player != null else Vector3.ZERO), animation_name, "READY" if nav_ready else "SYNCING" if nav_found else "MISSING",
		"ARRIVED" if mat_found and str(flow_state.get("pending_command", "")) == "" and str(flow_state.get("last_action", "")) == "GO_TO_MAT" else "READY" if mat_found else "MISSING",
		"VISIBLE" if mufasa_found else "MISSING", Engine.get_frames_per_second(), _yes(player != null), _yes(collision_found), _yes(floor_found),
		"PASS" if grounded else "PENDING", _yes(grounded), player.global_position.y if player != null else 0.0, feet_offset,
		str(flow_state.get("last_action", "NONE")), str(player._remote_direction if player != null else Vector2.ZERO),
		str(player.velocity if player != null else Vector3.ZERO), player._last_source if player != null else "NONE",
		animation_name, player.grounded_state() if player != null else "UNKNOWN", first_failure,
	]

func _yes(value: bool) -> String:
	return "YES" if value else "NO"
