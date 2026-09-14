extends SceneTree

const LIBRARY_PATH := "res://game/animations/player/player_locomotion_library.tres"
const SOURCE_PATH := "res://assets/animations/player/rashad_walk_corrected.glb"
const BONES := [&"Hips", &"LeftArm", &"RightArm", &"LeftUpLeg", &"RightUpLeg", &"LeftLeg", &"RightLeg"]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var library := load(LIBRARY_PATH) as AnimationLibrary
	if library == null or not library.has_animation(&"Walk"): return _fail("LIBRARY_WALK_MISSING")
	var walk := library.get_animation(&"Walk")
	_print_clip("LIBRARY_WALK", walk)
	var source_scene := load(SOURCE_PATH) as PackedScene
	if source_scene == null: return _fail("SOURCE_SCENE_MISSING")
	var root_node := source_scene.instantiate()
	var players := root_node.find_children("*", "AnimationPlayer", true, false)
	if players.size() != 1: return _fail("SOURCE_PLAYER_COUNT_%d" % players.size())
	var player := players[0] as AnimationPlayer
	for lib_name in player.get_animation_library_list():
		var lib := player.get_animation_library(lib_name)
		for clip_name in lib.get_animation_list():
			_print_clip("SOURCE_%s" % clip_name, lib.get_animation(clip_name))
	root_node.queue_free()
	print("WALK_QUALITY_INSPECT: PASS")
	quit(0)

func _print_clip(label: String, clip: Animation) -> void:
	print("%s tracks=%d length=%.6f loop=%s" % [label, clip.get_track_count(), clip.length, clip.loop_mode])
	for bone in BONES:
		var max_rot := 0.0
		var max_pos := 0.0
		var first_rot: Quaternion
		var first_pos := Vector3.ZERO
		var rot_seen := false
		var pos_seen := false
		for i in clip.get_track_count():
			var path := str(clip.track_get_path(i))
			if not path.ends_with(":" + String(bone)): continue
			if clip.track_get_type(i) == Animation.TYPE_ROTATION_3D and clip.track_get_key_count(i) > 0:
				first_rot = clip.track_get_key_value(i, 0); rot_seen = true
				for k in clip.track_get_key_count(i):
					var q: Quaternion = clip.track_get_key_value(i, k)
					max_rot = maxf(max_rot, first_rot.angle_to(q))
			if clip.track_get_type(i) == Animation.TYPE_POSITION_3D and clip.track_get_key_count(i) > 0:
				first_pos = clip.track_get_key_value(i, 0); pos_seen = true
				for k in clip.track_get_key_count(i):
					var p: Vector3 = clip.track_get_key_value(i, k)
					max_pos = maxf(max_pos, first_pos.distance_to(p))
		print("%s bone=%s rot_span_deg=%.3f pos_span=%.6f rot_seen=%s pos_seen=%s" % [label, bone, rad_to_deg(max_rot), max_pos, rot_seen, pos_seen])

func _fail(reason: String) -> void:
	push_error("WALK_QUALITY_INSPECT: FAIL " + reason)
	quit(1)
