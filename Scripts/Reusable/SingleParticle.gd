# Duskie's awesome single particle thingy yayyyyy :3

class_name SingleParticle
extends Node2D

# -- Export Variables --
@export_group("Visuals")
@export var sprite : AnimatedSprite2D

@export_group("System")
@export var auto_play_sprite : bool = true
@export var auto_play_animation : String
@export var delete_on_finish : bool = true
@export var looping : bool = false
@export var delete_on_frame: int

func _ready() -> void:
	if auto_play_sprite:
		start()
	else:
		sprite.animation_finished.connect(sprite_play)
	
func start() -> void:
	if not sprite:
		assert(false, "SPRITE NOT ADDED! ADD ONE!!")
	else:
		if auto_play_animation:
			sprite.play(auto_play_animation)
		else:
			assert(false, "NO ANIMATION SPECIFIED/FOUND")
	if looping == false:
		sprite.animation
		if delete_on_finish:
			sprite.animation_finished.connect(on_sprite_end)
		elif delete_on_frame > 0:
			await  get_tree().create_timer(delete_on_finish)
			queue_free()
	

func on_sprite_end() -> void:
	queue_free()
	
func sprite_play() -> void:
	sprite.play(sprite.animation)
