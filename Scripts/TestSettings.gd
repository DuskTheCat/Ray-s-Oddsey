extends Control

const MAIN_MENU = "res://Scenes/Menus/menu.tscn"
const LANGUAGES: Array[String] = ["en", "ja"]

@onready var language_button: Button = $LanguageButton

func _ready() -> void:
	language_button.pressed.connect(_on_language_button_pressed)
	_update_button_text()

func _on_language_button_pressed() -> void:
	var current: int = LANGUAGES.find(TranslationServer.get_locale().substr(0, 2))
	var next: int = (current + 1) % LANGUAGES.size()
	TranslationServer.set_locale(LANGUAGES[next])
	Settings.save_locale()
	_update_button_text()

func _update_button_text() -> void:
	match TranslationServer.get_locale().substr(0, 2):
		"ja":
			language_button.text = "日本語"
		_:
			language_button.text = "English"

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Settings.save_locale()
		get_tree().change_scene_to_file(MAIN_MENU)
