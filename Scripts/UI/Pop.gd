extends Node2D

@export var size_multiplier_pop: float = 0.8
@export var pressed_tint: Color = Color(0.482, 0.482, 0.482, 1.0)
@export var animation_duration: float = 0.1

@onready var button: TouchScreenButton = $TouchScreenButton

var old_scale: Vector2
var active_tween: Tween

func _ready() -> void:
	old_scale = scale
	button.pressed.connect(_on_pressed)
	button.released.connect(_on_released)

func _on_pressed() -> void:
	_animate(old_scale * size_multiplier_pop, pressed_tint)

func _on_released() -> void:
	_animate(old_scale, Color.WHITE) # Fixed the 255.0 blowout bug here

func _animate(target_scale: Vector2, target_color: Color) -> void:
	# Kill the previous tween if it's still running to avoid overlaps
	if active_tween and active_tween.is_running():
		active_tween.kill()
	
	active_tween = create_tween().set_parallel(true)
	active_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# Both animations will now play simultaneously over the duration
	active_tween.tween_property(self, "scale", target_scale, animation_duration)
	active_tween.tween_property(self, "modulate", target_color, animation_duration)
