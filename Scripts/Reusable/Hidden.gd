extends ColorRect

var tween : Tween
var is_entered: bool = false

func _on_area_2d_body_entered(body: Node2D) -> void: 
	# FIX: Use the 'is' keyword instead of is_class()
	if body.is_in_group("Player") and body is CharacterBody2D: 
		if tween and tween.is_running(): 
			tween.kill() 
		
		tween = create_tween() 
		# TIP: You can use self instead of $"."
		tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.5)\
			.set_ease(Tween.EASE_OUT)\
			.set_trans(Tween.TRANS_CUBIC) 
			
		is_entered = true



func _on_area_2d_body_exited(body: Node2D) -> void:
	# CLEANUP: 'is_entered' is a boolean, so you don't need '== true'
	if body.is_in_group("Player") and body is CharacterBody2D and is_entered:
		if tween and tween.is_running():
			tween.kill()
		
		tween = create_tween()
		# CLEANUP: Replaced $"." with self and removed the redundant tween.play()
		tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.4)\
			.set_ease(Tween.EASE_OUT)\
			.set_trans(Tween.TRANS_CUBIC)
		
		is_entered = false
