extends Control
@warning_ignore("inferred_declaration")
const TEST_LEVEL = "res://Scenes/Tests/TestLevel.tscn"
@warning_ignore("inferred_declaration")
const TEST_LEVEL_COOP = "res://Scenes/Tests/TestLevelCoop.tscn"
@warning_ignore("inferred_declaration")
const TEST_SETTINGS = "res://Scenes/Tests/TestSettings.tscn"

# Localization stuff.
@export_enum("en", "ja", "sv") var language: String = "en":
	set(value):
		language = value
		TranslationServer.set_locale(value)

func _ready() -> void:
	# Re-apply the locale after the scene is in the tree so labels refresh.
	await get_tree().process_frame
	TranslationServer.set_locale(TranslationServer.get_locale())

func _on_button_pressed() -> void:
	get_tree().change_scene_to_file(TEST_LEVEL)

func _on_button_2_pressed() -> void:
	get_tree().change_scene_to_file(TEST_LEVEL_COOP)

func _on_button_3_pressed() -> void:
	get_tree().change_scene_to_file(TEST_SETTINGS)
