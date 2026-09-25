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
			update_camera_extent(last_direction)
@export var WALK_SPEED : float = 140.0
@export var RUN_SPEED : float = 350.0
@export var JUMP_VELOCITY : float = -850.0
@export var GRAVITY_MULTIPLIER : float = 2
@export var SPEED_MULTIPLIER : float = 1.0
@export var ACCELERATION : float = 1750.0
@export var AIR_ACCELERATION : float = 1500.0
@export var DECCELERATION : float = 2600.0
@export var AIR_DECCELERATION : float = 500.0
@export var LEDGE_TIMEOUT : float = 0.3

var CURRENT_SPEED : float = 140.0
var OVERIDE_ANIMATIONS : bool = false
enum State {Normal, Cutscene}
enum MovementState {Normal, OnLedge}

@export_group("State")
@export var CURRENT_STATE = State.Normal
var CURRENT_MOVEMENT_STATE = MovementState.Normal

@export_group("Camera")
@export var SMOOTHNESS_SPEED : float = 6.0
@export var EXTEND_RANGE : float = 200.0
@export var SHORTENED_EXTEND_RANGE : float = 100.0

@onready var Camera : Camera2D = $CamPivot/Camera2D
@onready var CameraPivot : Node2D = $CamPivot

var extend_tween : Tween
var last_direction : float = 0.0

@onready var SPRITE: AnimatedSprite2D = $SpriteSheet
@onready var ledge_detecor_area: Area2D = $LedgeDetecorArea
@onready var ledge_timeout: Timer = $LedgeTimeout

@onready var fire_bar: Control = $UI/SafeScreen/FireBar

func _ready() -> void:
	Camera.position_smoothing_speed = SMOOTHNESS_SPEED
	ledge_timeout.wait_time = LEDGE_TIMEOUT
	
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		fire_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	else:
		fire_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	
	fire_bar.offset_left = 0
	fire_bar.offset_right = 0
	fire_bar.offset_top = 0
	fire_bar.offset_bottom = 0
	


		
func _physics_process(delta: float) -> void:
	# Gravity setup
	if CURRENT_MOVEMENT_STATE == MovementState.Normal:
		if not is_on_floor():
			velocity += (get_gravity() * GRAVITY_MULTIPLIER) * delta

		# Jump handling
		if Input.is_action_just_pressed("Jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY
		
		

		# Get movement direction (-1, 0, 1)
		var direction : float = Input.get_axis("Move_Left", "Move_Right")
		
		# Determine acceleration coefficients
		var accel : float = ACCELERATION if is_on_floor() else AIR_ACCELERATION
		var deccel : float = DECCELERATION if is_on_floor() else AIR_DECCELERATION

		# Velocity physics updates
		if direction != 0:
			velocity.x = move_toward(velocity.x, direction * CURRENT_SPEED * SPEED_MULTIPLIER, accel * delta)
			if direction > 0 :
				SPRITE.flip_h = false
			else:
				SPRITE.flip_h = true
		else:
			velocity.x = move_toward(velocity.x, 0.0, deccel * delta)

		move_and_slide()
		update_animation()
		
		update_camera_extent(direction)
		last_direction = direction
	elif CURRENT_MOVEMENT_STATE == MovementState.OnLedge:
		update_animation()
		update_camera_extent(0)
		last_direction = 0
		if Input.is_action_just_pressed("Jump"):
			exit_ledge()
			GRAVITY_MULTIPLIER = 2
		elif Input.is_action_just_released("Jump"):
			GRAVITY_MULTIPLIER = 4

func _input(event: InputEvent) -> void:
	# Toggle Sprint
	if event.is_action_pressed("Sprint"):
		SPRINTING = not SPRINTING

func update_camera_extent(dir: float) -> void:
	# Safely clear the previous tween
	if extend_tween and extend_tween.is_running():
		extend_tween.kill()
		
	# Target offset depends entirely on current movement vector direction
	var current_range: float = EXTEND_RANGE if SPRINTING else SHORTENED_EXTEND_RANGE
	var target_x : float = dir * current_range
	
	# var y_direction : float = sign(velocity.y)
	# var target_y : float = y_direction * current_range
	
	extend_tween = create_tween()
	extend_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	extend_tween.tween_property(CameraPivot, "position:x", target_x, 0.5)
	# extend_tween.parallel()
	# extend_tween.tween_property(CameraPivot, "position:y", target_y, 0.5).set_ease(Tween.EASE_OUT)

func update_animation() -> void:
	if not OVERIDE_ANIMATIONS:
		if CURRENT_MOVEMENT_STATE == MovementState.Normal:
			if is_on_floor():
				if velocity.x == 0:
					SPRITE.play("Idle")
				else:
					if abs(velocity.x) < 190:
						
						SPRITE.play("Walk")
					else:
						SPRITE.play("Run")
			else:
				if velocity.y < 0:  # Switch if flipped by accident
					SPRITE.play("Jump")
				elif velocity.y > 0:
					SPRITE.play("Fall")
		elif CURRENT_MOVEMENT_STATE == MovementState.OnLedge:
			SPRITE.play("LedgeGrab")

func grab_ledge() -> void:
	CURRENT_MOVEMENT_STATE = MovementState.OnLedge

func exit_ledge() -> void:
	ledge_timeout.start()
	CURRENT_MOVEMENT_STATE = MovementState.Normal
	velocity.y = JUMP_VELOCITY

func _on_ledge_detecor_area_area_entered(area: Area2D) -> void:
	if area.is_in_group("Ledge") and CURRENT_MOVEMENT_STATE != MovementState.OnLedge and ledge_timeout.is_stopped():
		if SPRITE.flip_h == false:
			if area.global_position.x > global_position.x:
				grab_ledge()
		else:
			if area.global_position.x < global_position.x:
				grab_ledge()
		
