extends Node

const SAVE_PATH = "user://settings.cfg"

func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		var saved: String = config.get_value("general", "locale", "en")
		TranslationServer.set_locale(saved)
		# Re-apply after the first scene has loaded so the UI refreshes.
		await get_tree().process_frame
		TranslationServer.set_locale(saved)
	print("Settings loaded, locale: ", TranslationServer.get_locale())

func save_locale() -> void:
	var config := ConfigFile.new()
	config.load(SAVE_PATH)
	config.set_value("general", "locale", TranslationServer.get_locale())
	config.save(SAVE_PATH)
