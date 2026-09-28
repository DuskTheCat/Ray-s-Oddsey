extends Area2D


func _on_area_entered(area: Area2D) -> void:
	var parent = area.get_parent()
	if parent.is_in_group("Entity") and not parent.is_in_group("Ray"):
		if parent.has_method("damage"):
			parent.damage(40, global_position, 3)
	await get_tree().create_timer(0.2).timeout
	queue_free()
