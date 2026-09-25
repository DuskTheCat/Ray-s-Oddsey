extends GPUParticles2D
@export var Override : bool = true

func _ready() -> void:
	one_shot = true       # Ensure it only fires once
	explosiveness = 1.0   # Burst all particles simultaneously
	restart()    
	await get_tree().create_timer(0.2).timeout
	restart()         # Clears old particles and forces a fresh burst!
	emitting = false
	one_shot = false 
	explosiveness = 0
	
	Override = false
