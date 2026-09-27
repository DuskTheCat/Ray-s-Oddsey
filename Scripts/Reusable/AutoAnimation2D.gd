extends AnimatedSprite2D
@export var animation_to_play : String

func _enter_tree() -> void:
	play(animation_to_play)

func _ready() -> void:
	play(animation_to_play)
