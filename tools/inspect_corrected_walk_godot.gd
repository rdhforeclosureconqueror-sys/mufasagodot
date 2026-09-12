extends SceneTree

func _initialize() -> void:
	var scene := load("res://assets/animations/player/rashad_walk_corrected.glb") as PackedScene
	if scene == null:
		push_error("CORRECTED_WALK_IMPORT_MISSING"); quit(1); return
	var root_node := scene.instantiate()
	root.add_child(root_node)
	for skeleton in root_node.find_children("*", "Skeleton3D", true, false):
		print("SKELETON=", skeleton.get_path(), " bones=", skeleton.get_bone_count())
	for value in root_node.find_children("*", "AnimationPlayer", true, false):
		var player := value as AnimationPlayer
		print("PLAYER=", player.get_path(), " root_node=", player.root_node)
		for library_name in player.get_animation_library_list():
			var library := player.get_animation_library(library_name)
			for clip_name in library.get_animation_list():
				var clip := library.get_animation(clip_name)
				print("CLIP=", library_name, "/", clip_name, " length=", clip.length, " tracks=", clip.get_track_count(), " loop=", clip.loop_mode)
				for index in mini(clip.get_track_count(), 12): print("TRACK=", clip.track_get_path(index), " type=", clip.track_get_type(index))
	quit()
