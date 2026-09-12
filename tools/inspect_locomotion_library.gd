extends SceneTree

func _initialize() -> void:
	for path in ["res://addons/humanizer/data/animations/animations.glb", "res://assets/animations/pocketpt/source/Walking.fbx", "res://game/animations/player/player_locomotion_library.tres"]:
		var library := load(path) as AnimationLibrary
		print("LIB=", path, " clips=", library.get_animation_list())
		for name in library.get_animation_list():
			if name not in [&"Idle", &"Run", &"Walk", &"mixamo_com"]: continue
			var animation := library.get_animation(name)
			var max_rotation := 0.0
			for track in animation.get_track_count():
				if animation.track_get_type(track) != Animation.TYPE_ROTATION_3D: continue
				for key in animation.track_get_key_count(track):
					var rotation: Quaternion = animation.track_get_key_value(track, key)
					max_rotation = maxf(max_rotation, rotation.angle_to(Quaternion.IDENTITY))
			print("CLIP=", name, " length=", animation.length, " tracks=", animation.get_track_count(), " max_rotation=", max_rotation, " first=", animation.track_get_path(0) if animation.get_track_count() else "")
	quit()
