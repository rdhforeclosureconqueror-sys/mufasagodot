extends SceneTree

const AVATAR_PATH := "res://assets/characters/pocketpt/source/rashad1.glb"
const LIBRARY_PATH := "res://game/animations/player/player_locomotion_library.tres"

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	if _sha256(AVATAR_PATH) != "faaa22d93196a058dca10545c8300f42de6e0c681fe8d05865927cd6320581e3": return _fail("SOURCE_HASH_MATCHED")
	var packed := load(AVATAR_PATH) as PackedScene
	var library := load(LIBRARY_PATH) as AnimationLibrary
	if packed == null or library == null or not library.has_animation(&"Idle"): return _fail("BAKED_RESOURCES")
	var host := Node3D.new(); root.add_child(host)
	var avatar := packed.instantiate(); avatar.name = "Avatar"; host.add_child(avatar)
	var skeletons := avatar.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty(): return _fail("PERSONAL_SKELETON")
	var skeleton := skeletons[0] as Skeleton3D
	if skeleton.name != "Skeleton3D" or skeleton.find_bone(&"LeftArm") < 0 or skeleton.find_bone(&"LeftUpperArm") >= 0: return _fail("ORIGINAL_SKELETON_PRESERVED")
	var player := AnimationPlayer.new(); host.add_child(player); player.root_node = NodePath(".."); player.add_animation_library(&"player", library)
	var bone := skeleton.find_bone(&"LeftArm"); var before := skeleton.get_bone_pose_rotation(bone)
	player.play(&"player/Idle"); await process_frame; await create_timer(0.2).timeout
	var delta := before.angle_to(skeleton.get_bone_pose_rotation(bone))
	if not player.is_playing() or delta < 0.0001: return _fail("IDLE_PLAYING")
	print("HUMANIZER_IDLE_ORIGINAL_AVATAR_TEST: PASS skeleton=%s bones=%d clip=%s pose_delta=%.6f" % [skeleton.name, skeleton.get_bone_count(), player.current_animation, delta])
	quit(0)

func _sha256(path: String) -> String:
	var context := HashingContext.new(); context.start(HashingContext.HASH_SHA256); context.update(FileAccess.get_file_as_bytes(path)); return context.finish().hex_encode()

func _fail(boundary: String) -> void:
	push_error("FIRST_FAILURE: " + boundary); quit(1)
