class_name GymPlayerController
extends CharacterBody3D

signal mat_selected()
signal navigation_state_changed(moving: bool, source: String)
signal locomotion_speed_changed(horizontal_speed: float, source: String)
signal locomotion_sampled(sample: Dictionary)
signal route_finished(arrived: bool)

enum NavigationContext { GYM_NAVIGATION, CAMERA_SETUP, LOCKED }
enum LocomotionMode { WALK, RUN }

@export var speed := 5.0
@export var run_speed_multiplier := 1.6
@export var jump_velocity := 4.5
@export var gravity := 12.0
@export var mat_arrival_distance := 0.35
@export var visual_turn_speed := 12.0

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var avatar_anchor: Node3D = get_node_or_null("avataranchor") as Node3D

var navigation_context := NavigationContext.GYM_NAVIGATION
var movement_mode := LocomotionMode.WALK
var actual_horizontal_displacement := 0.0
var actual_horizontal_speed := 0.0
var _remote_direction := Vector2.ZERO
var _remote_lease_deadline_ms := 0
var _route_active := false
var _route_target := Vector3.ZERO
var _was_moving := false
var _last_source := "NONE"
var last_move_command := "NONE"

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		stop_navigation()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and navigation_context == NavigationContext.GYM_NAVIGATION:
		rotate_y(-event.relative.x * 0.003)
		spring_arm.rotate_x(-event.relative.y * 0.003)
		spring_arm.rotation.x = clampf(spring_arm.rotation.x, -1.2, 0.5)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_try_select_mat(event.position)
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	var movement := _resolve_movement()
	var direction: Vector3 = movement.get("direction", Vector3.ZERO)
	var source: String = movement.get("source", "NONE")
	var effective_mode := LocomotionMode.WALK if source == "AUTO" else movement_mode
	var target_speed := speed * run_speed_multiplier if effective_mode == LocomotionMode.RUN else speed
	if direction.length_squared() > 0.0001:
		_face_visual_direction(direction, delta)
		velocity.x = direction.x * target_speed
		velocity.z = direction.z * target_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)
	var position_before_move := global_position
	move_and_slide()
	actual_horizontal_displacement = Vector2(global_position.x - position_before_move.x, global_position.z - position_before_move.z).length()
	actual_horizontal_speed = actual_horizontal_displacement / maxf(delta, 0.000001)
	var moving := actual_horizontal_displacement > 0.0005
	locomotion_speed_changed.emit(actual_horizontal_speed, source)
	locomotion_sampled.emit({
		"controlAction": last_move_command,
		"requestedDirection": Vector2(direction.x, direction.z),
		"velocity": velocity,
		"actualHorizontalDisplacement": actual_horizontal_displacement,
		"actualHorizontalSpeed": actual_horizontal_speed,
		"movementMode": locomotion_mode_name(effective_mode),
		"physicalMovementObserved": moving,
		"visualFacingYaw": avatar_anchor.rotation.y if avatar_anchor != null else 0.0,
		"source": source,
	})
	if moving != _was_moving or source != _last_source:
		_was_moving = moving
		_last_source = source
		navigation_state_changed.emit(moving, source)

func _face_visual_direction(world_direction: Vector3, delta: float) -> void:
	if avatar_anchor == null:
		return
	var local_direction := global_transform.basis.inverse() * world_direction
	local_direction.y = 0.0
	if local_direction.length_squared() <= 0.0001:
		return
	local_direction = local_direction.normalized()
	var target_yaw := atan2(-local_direction.x, -local_direction.z)
	avatar_anchor.rotation.y = lerp_angle(avatar_anchor.rotation.y, target_yaw, clampf(visual_turn_speed * delta, 0.0, 1.0))

func set_navigation_context(value: String) -> bool:
	match value:
		"GYM_NAVIGATION": navigation_context = NavigationContext.GYM_NAVIGATION
		"CAMERA_SETUP": navigation_context = NavigationContext.CAMERA_SETUP
		"LOCKED": navigation_context = NavigationContext.LOCKED
		_: return false
	if navigation_context != NavigationContext.GYM_NAVIGATION:
		stop_navigation()
	return true

func set_remote_intent(direction: Vector2, valid_for_ms: int, control_action := "REMOTE") -> bool:
	if navigation_context != NavigationContext.GYM_NAVIGATION or valid_for_ms <= 0 or valid_for_ms > 300:
		return false
	_route_active = false
	_remote_direction = direction.limit_length(1.0)
	last_move_command = control_action
	_remote_lease_deadline_ms = Time.get_ticks_msec() + valid_for_ms
	return true

func set_locomotion_mode(value: String) -> bool:
	match value:
		"WALK": movement_mode = LocomotionMode.WALK
		"RUN": movement_mode = LocomotionMode.RUN
		_: return false
	return true

func locomotion_mode_name(value := movement_mode) -> String:
	return "RUN" if value == LocomotionMode.RUN else "WALK"

func start_route(target: Vector3) -> bool:
	if navigation_context != NavigationContext.GYM_NAVIGATION or not navigation_ready():
		return false
	_remote_direction = Vector2.ZERO
	_remote_lease_deadline_ms = 0
	var navigation_map := navigation_agent.get_navigation_map()
	var resolved_target := NavigationServer3D.map_get_closest_point(navigation_map, target)
	_route_target = resolved_target
	navigation_agent.target_position = resolved_target
	_route_active = true
	last_move_command = "GO_TO_MAT"
	return true

func stop_navigation() -> void:
	_remote_direction = Vector2.ZERO
	_remote_lease_deadline_ms = 0
	_route_active = false
	velocity.x = 0.0
	velocity.z = 0.0

func is_route_active() -> bool:
	return _route_active

func _resolve_movement() -> Dictionary:
	if navigation_context != NavigationContext.GYM_NAVIGATION:
		return {"direction": Vector3.ZERO, "source": "LOCKED"}
	if _route_active:
		var next_position := navigation_agent.get_next_path_position()
		var offset := next_position - global_position
		offset.y = 0.0
		var target_offset := _route_target - global_position
		target_offset.y = 0.0
		var within_arrival_distance := target_offset.length() <= mat_arrival_distance

		if within_arrival_distance:
			_route_active = false
			velocity.x = 0.0
			velocity.z = 0.0
			route_finished.emit(true)
			return {"direction": Vector3.ZERO, "source": "AUTO"}
		return {"direction": offset.normalized(), "source": "AUTO"}
	if _remote_lease_deadline_ms > 0:
		if Time.get_ticks_msec() <= _remote_lease_deadline_ms:
			var remote_world := transform.basis * Vector3(_remote_direction.x, 0.0, _remote_direction.y)
			return {"direction": remote_world.normalized(), "source": "TOUCH"}
		_remote_direction = Vector2.ZERO
		_remote_lease_deadline_ms = 0
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var keyboard_world := transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	return {"direction": keyboard_world.normalized(), "source": "KEYBOARD" if not input_dir.is_zero_approx() else "NONE"}

func navigation_ready() -> bool:
	return navigation_agent != null and navigation_agent.get_navigation_map().is_valid() and NavigationServer3D.map_get_iteration_id(navigation_agent.get_navigation_map()) > 0

func grounded_state() -> String:
	return "GROUNDED" if is_on_floor() else "AIRBORNE"

func _try_select_mat(screen_position: Vector2) -> void:
	if navigation_context != NavigationContext.GYM_NAVIGATION:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var origin := camera.project_ray_origin(screen_position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen_position) * 100.0)
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	var collider = result.get("collider")
	if collider is Node and collider.is_in_group("pocketpt_mat"):
		mat_selected.emit()
