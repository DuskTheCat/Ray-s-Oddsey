# LoadManager.gd (Autoloaded)
extends Node

var progress: Array = []
var scene_path: String = "res://Scenes/Tests/TestLevel.tscn"
var status: ResourceLoader.ThreadLoadStatus

func load_scene(path: String) -> void:
	scene_path = path
	ResourceLoader.load_threaded_request(scene_path, "", true)
	get_tree().change_scene_to_file("res://Scenes/LoadingScreen.tscn")
