extends SceneTree

func _initialize() -> void:
	var library := load("res://assets/animations/humanizer/thriller_part1.res") as AnimationLibrary
	if library == null:
		push_error("THRILLER_LIBRARY_MISSING"); quit(1); return
	print("THRILLER_CLIPS=", library.get_animation_list())
	for name in library.get_animation_list():
		var clip := library.get_animation(name)
		print("CLIP=", name, " length=", clip.length, " loop=", clip.loop_mode, " tracks=", clip.get_track_count())
		for index in mini(clip.get_track_count(), 16): print("TRACK=", clip.track_get_path(index), " type=", clip.track_get_type(index))
	quit()
