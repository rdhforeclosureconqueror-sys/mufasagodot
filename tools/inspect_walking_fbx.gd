extends SceneTree

func _initialize() -> void:
	var resource := load("res://assets/animations/pocketpt/source/Walking.fbx")
	print("WALK_RESOURCE_TYPE=", resource.get_class() if resource != null else "null")
	if resource is AnimationLibrary:
		for clip_name in (resource as AnimationLibrary).get_animation_list():
			var clip: Animation = (resource as AnimationLibrary).get_animation(clip_name)
			print("WALK_CLIP=", clip_name, " length=", clip.length, " loop=", clip.loop_mode, " tracks=", clip.get_track_count())
			for track_index in mini(clip.get_track_count(), 12): print("WALK_TRACK=", clip.track_get_path(track_index))
	if resource is PackedScene:
		var root_node: Node = (resource as PackedScene).instantiate()
		for skeleton in root_node.find_children("*", "Skeleton3D", true, false):
			var names := PackedStringArray()
			for index in skeleton.get_bone_count(): names.append(skeleton.get_bone_name(index))
			print("WALK_SKELETON=", skeleton.get_path(), " bones=", skeleton.get_bone_count(), " names=", names)
		for player in root_node.find_children("*", "AnimationPlayer", true, false):
			for library_name in player.get_animation_library_list():
				var library: AnimationLibrary = player.get_animation_library(library_name)
				for clip_name in library.get_animation_list():
					var clip: Animation = library.get_animation(clip_name)
					print("WALK_CLIP=", library_name, "/", clip_name, " length=", clip.length, " loop=", clip.loop_mode, " tracks=", clip.get_track_count())
					for track_index in mini(clip.get_track_count(), 8): print("WALK_TRACK=", clip.track_get_path(track_index))
	quit()
