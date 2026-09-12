extends SceneTree

const AVATAR_PATH := "res://assets/characters/pocketpt/source/rashad1.glb"
const MAP_PATH := "res://resources/pocketpt/personalized_avatar_humanizer_bone_map.tres"
const HUMANIZER_LIBRARY_PATH := "res://addons/humanizer/data/animations/animations.glb"
const WALK_LIBRARY_PATH := "res://assets/animations/pocketpt/source/Walking.fbx"
const OUTPUT_PATH := "res://game/animations/player/player_locomotion_library.tres"
const SAMPLE_RATE := 30.0

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var avatar_scene := load(AVATAR_PATH) as PackedScene
	var bone_map := load(MAP_PATH) as BoneMap
	var humanizer_library := load(HUMANIZER_LIBRARY_PATH) as AnimationLibrary
	var walk_library := load(WALK_LIBRARY_PATH) as AnimationLibrary
	var output := load(OUTPUT_PATH) as AnimationLibrary
	if avatar_scene == null or bone_map == null or humanizer_library == null or output == null: return _fail("INPUT_RESOURCES")
	if not humanizer_library.has_animation(&"Run"): return _fail("RUN_CLIP")
	if walk_library == null or not walk_library.has_animation(&"mixamo_com"): return _fail("WALK_CLIP")
	if not output.has_animation(&"Idle"): return _fail("WORKING_IDLE_MISSING")
	var avatar := avatar_scene.instantiate()
	var targets := avatar.find_children("*", "Skeleton3D", true, false)
	if targets.is_empty(): return _fail("PERSONAL_SKELETON")
	var target := targets[0] as Skeleton3D
	var run_animation: Animation = await _bake_clip(humanizer_library, &"Run", target, bone_map)
	var walk_animation: Animation = await _bake_clip(walk_library, &"mixamo_com", target, bone_map)
	if run_animation == null or walk_animation == null: return _fail("RETARGET_BAKE")
	for clip_name in output.get_animation_list():
		if clip_name != &"Idle": output.remove_animation(clip_name)
	run_animation.resource_name = "Run"
	walk_animation.resource_name = "Walk"
	if output.add_animation(&"Run", run_animation) != OK: return _fail("ADD_RUN")
	if output.add_animation(&"Walk", walk_animation) != OK: return _fail("ADD_WALK")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_PATH.get_base_dir()))
	var error := ResourceSaver.save(output, OUTPUT_PATH)
	if error != OK: return _fail("ANIMATION_SAVE:%s" % error_string(error))
	print("HUMANIZER_LOCOMOTION_BAKE: PASS idle_preserved=true run_tracks=%d walk_tracks=%d clips=%s output=%s" % [run_animation.get_track_count(), walk_animation.get_track_count(), output.get_animation_list(), OUTPUT_PATH])
	quit(0)

func _bake_clip(donor_library: AnimationLibrary, source_name: StringName, target: Skeleton3D, bone_map: BoneMap) -> Animation:
	var profile := bone_map.profile
	var host := Node3D.new(); root.add_child(host)
	var donor := _build_profile_skeleton(profile, null); donor.name = "GeneralSkeleton"; host.add_child(donor); donor.owner = host; donor.unique_name_in_owner = true
	var modifier := RetargetModifier3D.new(); modifier.name = "HumanizerRetarget"; donor.add_child(modifier); modifier.profile = profile; modifier.use_global_pose = true
	var proxy := _build_profile_skeleton(profile, {"target": target, "map": bone_map}); proxy.name = "RashadRetargetProxy"; modifier.add_child(proxy)
	var player := AnimationPlayer.new(); host.add_child(player); player.root_node = NodePath(".."); player.add_animation_library(&"donor", donor_library)
	var source := donor_library.get_animation(source_name)
	var baked := Animation.new(); baked.length = source.length; baked.loop_mode = Animation.LOOP_LINEAR
	var tracks := {}
	for profile_index in profile.get_bone_size():
		var profile_name := profile.get_bone_name(profile_index)
		var raw_name := bone_map.get_skeleton_bone_name(profile_name)
		var proxy_index := proxy.find_bone(profile_name)
		if raw_name.is_empty() or target.find_bone(raw_name) < 0 or proxy_index < 0: continue
		var base := "Avatar/Armature/Skeleton3D:%s" % raw_name
		var position_track := baked.add_track(Animation.TYPE_POSITION_3D); baked.track_set_path(position_track, NodePath(base))
		var rotation_track := baked.add_track(Animation.TYPE_ROTATION_3D); baked.track_set_path(rotation_track, NodePath(base))
		tracks[profile_name] = [proxy_index, position_track, rotation_track]
	player.play(&"donor/" + source_name)
	var frames := ceili(source.length * SAMPLE_RATE)
	var hips_origin := Vector2.ZERO
	for frame in range(frames + 1):
		var time := minf(frame / SAMPLE_RATE, source.length)
		player.seek(time, true); await process_frame
		for profile_name in tracks:
			var data: Array = tracks[profile_name]; var index: int = data[0]
			var position := proxy.get_bone_pose_position(index)
			if profile_name == &"Hips":
				if frame == 0: hips_origin = Vector2(position.x, position.z)
				position.x = hips_origin.x; position.z = hips_origin.y
			baked.position_track_insert_key(data[1], time, position)
			baked.rotation_track_insert_key(data[2], time, proxy.get_bone_pose_rotation(index))
	host.queue_free()
	return baked

func _build_profile_skeleton(profile: SkeletonProfile, target_data: Variant) -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	for index in profile.get_bone_size():
		var profile_name := profile.get_bone_name(index)
		if target_data != null and (target_data.map.get_skeleton_bone_name(profile_name).is_empty() or target_data.target.find_bone(target_data.map.get_skeleton_bone_name(profile_name)) < 0): continue
		skeleton.add_bone(profile_name)
	for index in skeleton.get_bone_count():
		var profile_name := skeleton.get_bone_name(index)
		var profile_index := profile.find_bone(profile_name)
		var parent_name := profile.get_bone_parent(profile_index)
		while not parent_name.is_empty() and skeleton.find_bone(parent_name) < 0: parent_name = profile.get_bone_parent(profile.find_bone(parent_name))
		if not parent_name.is_empty(): skeleton.set_bone_parent(index, skeleton.find_bone(parent_name))
		var rest := profile.get_reference_pose(profile_index)
		if target_data != null: rest = target_data.target.get_bone_rest(target_data.target.find_bone(target_data.map.get_skeleton_bone_name(profile_name)))
		skeleton.set_bone_rest(index, rest); skeleton.reset_bone_pose(index)
	return skeleton

func _fail(boundary: String) -> void:
	push_error("FIRST_FAILURE: " + boundary); quit(1)
