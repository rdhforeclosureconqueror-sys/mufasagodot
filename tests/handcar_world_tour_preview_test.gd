extends SceneTree

const PREVIEW_SCENE := "res://scenes/previews/handcar_world_tour_preview.tscn"
const PREVIEW_SCRIPT := "res://scripts/previews/handcar_world_tour_preview.gd"

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_expect(FileAccess.file_exists(PREVIEW_SCENE), "handcar preview scene must exist")
	_expect(FileAccess.file_exists(PREVIEW_SCRIPT), "handcar preview script must exist")

	var scene_source := FileAccess.get_file_as_string(PREVIEW_SCENE)
	var script_source := FileAccess.get_file_as_string(PREVIEW_SCRIPT)
	var main_scene := FileAccess.get_file_as_string("res://Main.tscn")

	_expect(scene_source.contains("handcar_world_tour_preview.gd"), "preview scene must bind the handcar preview script")
	_expect(script_source.contains("const MAX_REPS := 60"), "preview must preserve the 60-rep challenge ceiling")
	_expect(script_source.contains("SUBWAY GRIND"), "preview must contain the subway visual zone")
	_expect(script_source.contains("CITY BREAKOUT"), "preview must contain the city visual zone")
	_expect(script_source.contains("MOUNTAIN CLIMB"), "preview must contain the mountain visual zone")
	_expect(script_source.contains("simulate_rep()"), "preview must expose a simulated rep action")
	_expect(script_source.contains("KEY_SPACE"), "preview must allow SPACE to simulate a push-up rep")
	_expect(script_source.contains("KEY_A"), "preview must allow autoplay toggle")
	_expect(script_source.contains("20, 30, 40, 50, 60"), "preview must expose 20/30/40/50/60 milestone gates")
	_expect(not main_scene.contains("HandcarWorldTourPreview"), "standalone preview must not be wired into the live Main scene before owner approval")

	if failures.is_empty():
		print("HANDCAR_WORLD_TOUR_PREVIEW_TEST: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("HANDCAR_WORLD_TOUR_PREVIEW_TEST: FAIL (%d)" % failures.size())
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
