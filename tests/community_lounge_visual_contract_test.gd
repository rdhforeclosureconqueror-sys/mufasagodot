extends SceneTree
# Run with: godot --headless --path . --script res://tests/community_lounge_visual_contract_test.gd
# The scene should retain the established movement and game contracts.
func _initialize() -> void:
	var scene := FileAccess.get_file_as_string("res://gym_environment.gd")
	var main := FileAccess.get_file_as_string("res://Main.tscn")
	var required := [
		"func _build_community_lounge()",
		"_build_community_lounge()",
		"CommunitySocialSeating",
		"CommunityWellnessNook",
		"CommunityTeaBar",
		"MILELE FIT",
		"COMMUNITY LOUNGE",
		"CONNECT  •  BREATHE  •  BELONG",
		"PocketPTMatArrival",
		"pocketpt_mat_target",
		"GymNavigationRegion",
		"pocketpt_navigation_region",
		"GymTestCamera",
		"_build_mat_area(Vector3(2.6, 0, 3.7))"
	]
	for item in required:
		if not scene.contains(item):
			push_error("FIRST FAILURE: missing lounge or preserved gameplay contract: " + item)
			quit(1)
			return
	for item in ["pocketpt_bootstrap.gd", "player.gd", "gym_environment.gd", "NavigationAgent3D"]:
		if not main.contains(item):
			push_error("FIRST FAILURE: Main scene lost critical system: " + item)
			quit(1)
			return
	print("COMMUNITY_LOUNGE_VISUAL_CONTRACT: PASS (source assertions; export/browser verification still required)")
	quit(0)
