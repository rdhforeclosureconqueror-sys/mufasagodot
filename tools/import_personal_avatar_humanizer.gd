extends SceneTree

const MODEL_PATH := "res://assets/characters/pocketpt/derived/rashad1_humanizer.glb"
const BONE_MAP_PATH := "res://resources/pocketpt/personalized_avatar_humanizer_bone_map.tres"
const ImportConfiguratorScript = preload("res://addons/mixabridge/import_configurator.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not ResourceLoader.exists(MODEL_PATH):
		push_error("FIRST_FAILURE: DERIVED_AVATAR_IMPORT")
		quit(1)
		return
	var bone_map := load(BONE_MAP_PATH) as BoneMap
	if bone_map == null:
		push_error("FIRST_FAILURE: VALIDATED_BONEMAP")
		quit(1)
		return
	var configurator = ImportConfiguratorScript.new()
	var config_error := configurator.configure_model(MODEL_PATH, BONE_MAP_PATH)
	if config_error != OK:
		push_error("FIRST_FAILURE: RETARGET_CONFIGURATION (%s)" % error_string(config_error))
		quit(1)
		return
	print("PERSONALIZED_HUMANIZER_IMPORT: ACCEPTED model=%s bonemap=%s" % [MODEL_PATH, BONE_MAP_PATH])
	quit(0)
