extends Control
const TEST_LEVEL = "res://Scenes/Tests/TestLevel.tscn"
const TEST_LEVEL_COOP = "res://Scenes/Tests/TestLevelCoop.tscn"


func _on_button_pressed() -> void:
	get_tree().change_scene_to_file(TEST_LEVEL)
	


func _on_button_2_pressed() -> void:
	get_tree().change_scene_to_file(TEST_LEVEL_COOP)
