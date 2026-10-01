extends Area2D


func _on_body_entered(body: Node2D) -> void:
	if body.is_class("CharacterBody2D") or body.is_class("RigidBody2D"):
		body.queue_free()
