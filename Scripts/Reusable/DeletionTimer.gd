extends Timer
@onready var parent: = $".."




func _on_timeout() -> void:
	parent.queue_free()
