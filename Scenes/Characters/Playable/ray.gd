extends CharacterBody2D

@export_group("Movement")

@export var SPRINTING : bool = false:
	set(value):
		if SPRINTING != value:
			SPRINTING = value
			if SPRINTING:
				CURRENT_SPEED = RUN_SPEED
			else:
				CURRENT_SPEED = WALK_SPEED

@export var WALK_SPEED : float = 140.0
@export var RUN_SPEED : float = 350.0
@export var JUMP_VELOCITY : float = -500.0
@export var SPEED_MULTIPLIER : float = 1.0
@export var ACCELERATION : float = 2000.0
@export var AIR_ACCELERATION : float = 1500.0 
@export var DECCELERATION : float = 2600.0
@export var AIR_DECCELERATION : float = 500.0

var CURRENT_SPEED : float = 140.0


func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("Jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Select acceleration/deceleration rate based on floor state
	var accel := ACCELERATION if is_on_floor() else AIR_ACCELERATION
	var deccel := DECCELERATION if is_on_floor() else AIR_DECCELERATION

	# Get the input direction and handle the movement/deceleration.
	var direction := Input.get_axis("Move_Left", "Move_Right")
	if direction != 0:
		velocity.x = move_toward(velocity.x, direction * CURRENT_SPEED * SPEED_MULTIPLIER, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, deccel * delta)

	move_and_slide()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("Sprint"):
		SPRINTING = not SPRINTING
