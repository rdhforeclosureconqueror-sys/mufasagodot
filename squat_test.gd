extends Node

const SKELETON_PATH := NodePath("../player/Sketchfab_Scene/Sketchfab_model/root/GLTF_SceneRootNode/imfernus_110/GLTF_created_0/Skeleton3D")
const CONTROLLED_NAMES := [
	"pelvis_108",
	"spine_0_82",
	"spine_1_81",
	"spine_2_80",
	"spine_3_78",
	"leg_upper_L_97",
	"leg_lower_L_94",
	"ankle_L_93",
	"leg_upper_R_91",
	"leg_lower_R_88",
	"ankle_R_87"
]

var skeleton: Skeleton3D
var gym_environment: Node
var bone_indices: Dictionary = {}
var original_rotations: Dictionary = {}
var original_positions: Dictionary = {}
var original_scales: Dictionary = {}
var target_rotations: Dictionary = {}
var target_positions: Dictionary = {}

var anatomical_left := Vector3.ZERO
var anatomical_up := Vector3.ZERO
var anatomical_forward := Vector3.ZERO
var left_hip_axis := Vector3.ZERO
var right_hip_axis := Vector3.ZERO
var torso_axis := Vector3.ZERO

var running := false
var elapsed := 0.0
var phase := "READY"
var last_phase := ""
var last_weight := 0.0

func _ready() -> void:
	skeleton = get_node(SKELETON_PATH)
	gym_environment = get_node_or_null("../GymEnvironment")
	for bone_name in CONTROLLED_NAMES:
		var index := skeleton.find_bone(bone_name)
		if index < 0:
			push_error("SquatTest missing bone: " + bone_name)
			return
		bone_indices[bone_name] = index
	_cache_original_pose()
	_derive_anatomical_frame()
	_build_squat_targets()
	_calibrate_pelvis_for_feet()
	print("[SquatTest] READY controlled_bones=", CONTROLLED_NAMES)
	print("[SquatTest] anatomical left=", anatomical_left, " up=", anatomical_up, " forward=", anatomical_forward)
	print("[SquatTest] hip axes L=", left_hip_axis, " R=", right_hip_axis, " torso=", torso_axis)
	_set_status("READY", "1: RUN SQUAT   R: RESTORE")

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_1:
		start_squat()
	elif event.keycode == KEY_R:
		restore_original_pose()

func start_squat() -> void:
	restore_original_pose(false)
	elapsed = 0.0
	running = true
	last_phase = ""
	_set_phase("STAND")
	print("[SquatTest] sequence_started")

func restore_original_pose(update_status := true) -> void:
	if not skeleton:
		return
	for bone_name in CONTROLLED_NAMES:
		var index: int = bone_indices[bone_name]
		skeleton.set_bone_pose_rotation(index, original_rotations[bone_name])
		skeleton.set_bone_pose_position(index, original_positions[bone_name])
		skeleton.set_bone_pose_scale(index, original_scales[bone_name])
	running = false
	last_weight = 0.0
	phase = "RESTORED"
	if update_status:
		_set_status("RESTORED", "Original pose restored exactly")
		print("[SquatTest] RESTORED max_error=", _max_restore_error())

func _exit_tree() -> void:
	restore_original_pose(false)

func _process(delta: float) -> void:
	if not running:
		return
	elapsed += delta
	var weight := 0.0
	if elapsed < 0.5:
		_set_phase("STAND")
		weight = 0.0
	elif elapsed < 2.0:
		_set_phase("DESCEND")
		weight = _smooth((elapsed - 0.5) / 1.5)
	elif elapsed < 2.5:
		_set_phase("BOTTOM")
		weight = 1.0
	elif elapsed < 4.0:
		_set_phase("ASCEND")
		weight = 1.0 - _smooth((elapsed - 2.5) / 1.5)
	else:
		restore_original_pose()
		return
	_apply_weight(weight)
	last_weight = weight
	_set_status("SQUAT TEST", "%s  •  HIP %d°  •  KNEE %d°" % [phase, roundi(68.0 * weight), roundi(82.0 * weight)])

func _smooth(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _set_phase(value: String) -> void:
	phase = value
	if phase != last_phase:
		last_phase = phase
		print("[SquatTest] phase=", phase, " elapsed=", snappedf(elapsed, 0.001))

func _set_status(status: String, detail: String) -> void:
	if gym_environment and gym_environment.has_method("set_movement_status"):
		gym_environment.set_movement_status(status, detail)

func _cache_original_pose() -> void:
	for bone_name in CONTROLLED_NAMES:
		var index: int = bone_indices[bone_name]
		original_rotations[bone_name] = skeleton.get_bone_pose_rotation(index)
		original_positions[bone_name] = skeleton.get_bone_pose_position(index)
		original_scales[bone_name] = skeleton.get_bone_pose_scale(index)

func _derive_anatomical_frame() -> void:
	var hip_l: int = bone_indices["leg_upper_L_97"]
	var hip_r: int = bone_indices["leg_upper_R_91"]
	var knee_l: int = bone_indices["leg_lower_L_94"]
	var knee_r: int = bone_indices["leg_lower_R_88"]
	var pelvis: int = bone_indices["pelvis_108"]
	var chest: int = bone_indices["spine_3_78"]

	anatomical_left = (skeleton.get_bone_global_pose(hip_l).origin - skeleton.get_bone_global_pose(hip_r).origin).normalized()
	anatomical_up = (skeleton.get_bone_global_pose(chest).origin - skeleton.get_bone_global_pose(pelvis).origin).normalized()
	anatomical_forward = anatomical_left.cross(anatomical_up).normalized()

	var thigh_l := (skeleton.get_bone_global_pose(knee_l).origin - skeleton.get_bone_global_pose(hip_l).origin).normalized()
	var thigh_r := (skeleton.get_bone_global_pose(knee_r).origin - skeleton.get_bone_global_pose(hip_r).origin).normalized()
	left_hip_axis = thigh_l.cross(anatomical_forward).normalized()
	right_hip_axis = thigh_r.cross(anatomical_forward).normalized()
	torso_axis = anatomical_up.cross(anatomical_forward).normalized()

func _build_squat_targets() -> void:
	# Hips swing the thighs forward; knees counter-rotate the shins; ankles
	# dorsiflex to keep the imported feet close to their original orientation.
	target_rotations["leg_upper_L_97"] = _rotation_from_skeleton_delta(bone_indices["leg_upper_L_97"], left_hip_axis, 68.0)
	target_rotations["leg_upper_R_91"] = _rotation_from_skeleton_delta(bone_indices["leg_upper_R_91"], right_hip_axis, 68.0)
	target_rotations["leg_lower_L_94"] = _rotation_from_skeleton_delta(bone_indices["leg_lower_L_94"], -left_hip_axis, 82.0)
	target_rotations["leg_lower_R_88"] = _rotation_from_skeleton_delta(bone_indices["leg_lower_R_88"], -right_hip_axis, 82.0)
	target_rotations["ankle_L_93"] = _rotation_from_skeleton_delta(bone_indices["ankle_L_93"], left_hip_axis, 16.0)
	target_rotations["ankle_R_87"] = _rotation_from_skeleton_delta(bone_indices["ankle_R_87"], right_hip_axis, 16.0)

	# Small distributed forward torso inclination.
	target_rotations["spine_0_82"] = _rotation_from_skeleton_delta(bone_indices["spine_0_82"], torso_axis, 4.0)
	target_rotations["spine_1_81"] = _rotation_from_skeleton_delta(bone_indices["spine_1_81"], torso_axis, 3.0)
	target_rotations["spine_2_80"] = _rotation_from_skeleton_delta(bone_indices["spine_2_80"], torso_axis, 3.0)
	target_rotations["spine_3_78"] = _rotation_from_skeleton_delta(bone_indices["spine_3_78"], torso_axis, 2.0)
	target_rotations["pelvis_108"] = original_rotations["pelvis_108"]

	var pelvis_position: Vector3 = original_positions["pelvis_108"]
	target_positions["pelvis_108"] = pelvis_position - anatomical_up * 18.0 - anatomical_forward * 3.0

	for bone_name in CONTROLLED_NAMES:
		if not target_rotations.has(bone_name):
			target_rotations[bone_name] = original_rotations[bone_name]
		if not target_positions.has(bone_name):
			target_positions[bone_name] = original_positions[bone_name]

func _calibrate_pelvis_for_feet() -> void:
	var left_ball := skeleton.find_bone("ball_L_92")
	var right_ball := skeleton.find_bone("ball_R_86")
	if left_ball < 0 or right_ball < 0:
		push_warning("SquatTest foot calibration skipped: ball bones missing")
		return
	var standing_center := (skeleton.get_bone_global_pose(left_ball).origin + skeleton.get_bone_global_pose(right_ball).origin) * 0.5
	_apply_weight(1.0)
	var bottom_center := (skeleton.get_bone_global_pose(left_ball).origin + skeleton.get_bone_global_pose(right_ball).origin) * 0.5
	var foot_drift := bottom_center - standing_center
	var pelvis_target: Vector3 = target_positions["pelvis_108"]
	target_positions["pelvis_108"] = pelvis_target - foot_drift
	restore_original_pose(false)
	print("[SquatTest] pelvis foot-plant compensation=", -foot_drift)

func _rotation_from_skeleton_delta(index: int, axis: Vector3, degrees: float) -> Quaternion:
	var parent_index := skeleton.get_bone_parent(index)
	var current_global_basis := skeleton.get_bone_global_pose(index).basis.orthonormalized()
	var desired_global_basis := Basis(Quaternion(axis.normalized(), deg_to_rad(degrees))) * current_global_basis
	var parent_global_basis := Basis.IDENTITY
	if parent_index >= 0:
		parent_global_basis = skeleton.get_bone_global_pose(parent_index).basis.orthonormalized()
	var desired_local_basis := parent_global_basis.inverse() * desired_global_basis
	return desired_local_basis.get_rotation_quaternion().normalized()

func _apply_weight(weight: float) -> void:
	for bone_name in CONTROLLED_NAMES:
		var index: int = bone_indices[bone_name]
		var from_rotation: Quaternion = original_rotations[bone_name]
		var to_rotation: Quaternion = target_rotations[bone_name]
		var from_position: Vector3 = original_positions[bone_name]
		var to_position: Vector3 = target_positions[bone_name]
		skeleton.set_bone_pose_rotation(index, from_rotation.slerp(to_rotation, weight).normalized())
		skeleton.set_bone_pose_position(index, from_position.lerp(to_position, weight))
		skeleton.set_bone_pose_scale(index, original_scales[bone_name])

func _max_restore_error() -> float:
	var maximum := 0.0
	for bone_name in CONTROLLED_NAMES:
		var index: int = bone_indices[bone_name]
		var original_rotation: Quaternion = original_rotations[bone_name]
		var current_rotation := skeleton.get_bone_pose_rotation(index)
		var original_position: Vector3 = original_positions[bone_name]
		var current_position := skeleton.get_bone_pose_position(index)
		maximum = maxf(maximum, absf(original_rotation.dot(current_rotation) - 1.0))
		maximum = maxf(maximum, original_position.distance_to(current_position))
	return maximum
