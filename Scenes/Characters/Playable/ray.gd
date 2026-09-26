extends CharacterBody2D

# --- Constants & Enums ---
const UNIT_SCALE: float = 100.0
const EXPLOSION: PackedScene = preload("res://Scenes/Effects/explosion.tscn")

enum State { NORMAL, CUTSCENE }
enum MovementState { NORMAL, ON_LEDGE, PHYSICS_OBJECT }

# --- Export Variables ---
@export_group("Movement")
@export var walk_speed: float = 1.4
@export var run_speed: float = 3.5
@export var jump_velocity: float = -8.5
@export var gravity_multiplier: float = 2.0
@export var speed_multiplier: float = 1.0
@export var acceleration: float = 17.5
@export var air_acceleration: float = 15.0
@export var deceleration: float = 26.0
@export var air_deceleration: float = 5.0
@export var sprinting: bool = false:
	set(value):
		if sprinting != value:
			sprinting = value
			current_speed = run_speed if sprinting else walk_speed
			update_camera_extent(last_direction)

@export_group("Combat")
@export var max_fire: float = 100.0
@export var dash_velocity: float = 10.0
@export var dash_time: float = 0.2
@export var air_dash_ragdolls: bool = true
@export var bounciness: float = 0.35
@export var physics_friction: float = 10.0
@export var fire: float = 100.0:
	set(value):
		fire = value
		# Run UI update regardless of authority so client displays match
		if is_instance_valid(fire_bar):
			fire_bar.value = value
@export var punch_dash_speed: float = 5.0 # How fast the player lunges forward


@export_group("State")
@export var current_state: State = State.NORMAL
@export var current_movement_state: MovementState = MovementState.NORMAL

@export_group("Camera")
@export var smoothness_speed: float = 6.0
@export var extend_range: float = 2.0
@export var shortened_extend_range: float = 1.0

# --- Onready Nodes ---
@onready var fire_fill: Timer = $FireFill
@onready var dash_timeout: Timer = $DashTimeout
@onready var smoke: GPUParticles2D = $Smoke/Smoke
@onready var smoke_2: GPUParticles2D = $Smoke/Smoke2
@onready var camera: Camera2D = $CamPivot/Camera2D
@onready var camera_pivot: Node2D = $CamPivot
@onready var sprite: AnimatedSprite2D = $SpriteSheet
@onready var ledge_detector_area: Area2D = $LedgeDetecorArea
@onready var ledge_timeout: Timer = $LedgeTimeout
@onready var fire_bar_container: Control = $UI/SafeScreen/FireBar
@onready var fire_bar: TextureProgressBar = $UI/SafeScreen/FireBar/TextureProgressBar2
@onready var ui: CanvasLayer = $UI
@onready var health_bar_container: Control = $UI/SafeScreen/HealthBar
@onready var health_bar: TextureProgressBar = $UI/SafeScreen/HealthBar/TextureProgressBar2
@onready var punch_timeout: Timer = $PunchTimeout
@onready var punch_cooldown: Timer = $PunchCooldown

# --- Private / Runtime Variables ---
var current_speed: float = 1.4
var override_animations: bool = false
var is_dashing: bool = false
var can_dash: bool = true
var is_air_dash_ragdoll: bool = false
var is_ground_dashing: bool = false
var ground_dash_direction: float = 0.0
var extend_tween: Tween
var modulate_tween: Tween
var last_direction: float = 0.0
var combo_count: int = 0
var can_punch: bool = true

@export_group("Stats")
@export var Health : float = 100.0:
	set(value):
		Health = value
		health_bar.value = value
@export var Max_Health : float = 100.0

func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())

func _ready() -> void:
	if is_multiplayer_authority():
		camera.make_current()
	else:
		ui.visible = false
		camera.enabled = false
	fire = max_fire
	fire_bar.value = max_fire
	fire_bar.max_value = max_fire
	current_speed = walk_speed
	camera.position_smoothing_speed = smoothness_speed
	
	# Target the parent container node rather than the child progress bar
	var preset := Control.PRESET_TOP_LEFT if (OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")) else Control.PRESET_BOTTOM_LEFT
	
	fire_bar_container.set_anchors_preset(preset, false)

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority(): return
	if is_on_floor():
		can_dash = true
		
	# Separated execution chains back into their specific code domains to preserve exact physics timing
	if current_movement_state == MovementState.NORMAL:
		# FIX: Force smoke off during normal gameplay UNLESS we are currently in an upward dash window
		var is_upward_dashing : bool = not can_dash and not dash_timeout.is_stopped()
		set_smoke_emitting(is_upward_dashing)
		
		if not is_on_floor():
			velocity += (get_gravity() * gravity_multiplier) * delta
			
		if Input.is_action_just_pressed("Jump") and is_on_floor():
			velocity.y = jump_velocity * UNIT_SCALE
			
		var direction := Input.get_axis("Move_Left", "Move_Right")
		var accel := (acceleration if is_on_floor() else air_acceleration) * UNIT_SCALE
		var deccel := (deceleration if is_on_floor() else air_deceleration) * UNIT_SCALE
		var target_speed := current_speed * speed_multiplier * UNIT_SCALE
		
		if direction != 0:
			velocity.x = move_toward(velocity.x, direction * target_speed, accel * delta)
			sprite.flip_h = direction < 0
		else:
			velocity.x = move_toward(velocity.x, 0.0, deccel * delta)
			
		move_and_slide()
		update_animation()
		update_camera_extent(direction)
		last_direction = direction
		
	elif current_movement_state == MovementState.ON_LEDGE:
		velocity = Vector2.ZERO # Absolute state lock
		set_smoke_emitting(false) # Force smoke off on ledges
		update_animation()
		update_camera_extent(0)
		last_direction = 0
		if Input.is_action_just_pressed("Jump"):
			exit_ledge()
			
	elif current_movement_state == MovementState.PHYSICS_OBJECT:
		override_animations = true
		
		if not is_on_floor():
			# SMOKE RULE: Always emit in physics mode when airborne (ragdoll / air-dash)
			set_smoke_emitting(true)
			sprite.play("Ragdoll")
			sprite.rotate(deg_to_rad(20 if velocity.x > 0 else -20))
		else:
			# SMOKE RULE: On the floor, only emit if we transitioned here from an air version landing
			set_smoke_emitting(is_air_dash_ragdoll and not is_ground_dashing)
			sprite.play("Dash")
			
		if is_ground_dashing:
			velocity.x = ground_dash_direction * dash_velocity * UNIT_SCALE
		
		velocity += (get_gravity() * gravity_multiplier) * delta
		move_and_slide()
		
		# Isolated Wall/Ceiling/Floor bounce processing
		if is_on_wall_only() or is_on_ceiling() or (is_on_floor() and not is_ground_dashing):
			var collision := get_last_slide_collision()
			if collision:
				velocity = velocity.bounce(collision.get_normal()) * bounciness
			if is_on_wall():
				current_movement_state = MovementState.NORMAL
				sprite.rotation = 0.0
				override_animations = false
				
		if not is_ground_dashing:
			var friction_reduction := (deceleration if is_on_floor() else air_deceleration) * physics_friction
			velocity.x = move_toward(velocity.x, 0.0, friction_reduction * delta)
			
		update_animation()
		
		if is_on_floor() and not is_ground_dashing:
			override_animations = false
			sprite.rotation = 0.0
			if is_air_dash_ragdoll:
				is_air_dash_ragdoll = false
				current_movement_state = MovementState.NORMAL
		elif not is_ground_dashing and abs(velocity.x) < 0.5 * UNIT_SCALE:
			current_movement_state = MovementState.NORMAL
			set_smoke_emitting(false)

func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority(): return
	if current_movement_state == MovementState.PHYSICS_OBJECT and not is_ground_dashing:
		return
		
	if event.is_action_pressed("Sprint"):
		sprinting = not sprinting
		
	if event.is_action_pressed("Dash") and can_dash:
		if dash_timeout.is_stopped():
			dash()
			
	if event.is_action_pressed("Punch"):
		punch()

# --- Gameplay Actions ---
func dash() -> void:
	if not dash_timeout.is_stopped() or (current_movement_state == MovementState.PHYSICS_OBJECT and not is_ground_dashing):
		return
		
	# --- OVERRIDE PREVIOUS TWEEN ---
	if modulate_tween and modulate_tween.is_running():
		modulate_tween.kill()
		
	# Upward dash override
	if Input.is_action_pressed("Move_Up"):
		if fire < 20: return
		fire -= 20.0
		dash_timeout.start(0.3)
		current_movement_state = MovementState.NORMAL
		velocity.y = -dash_velocity * UNIT_SCALE
		can_dash = false
		rpc("spawn_explosion")
		sprite.play("Jump")
		set_smoke_emitting(true)
		
		# Darken instantly
		sprite.self_modulate = Color(0.3, 0.3, 0.3, 1.0)
		get_tree().create_timer(0.3).timeout.connect(func():
			if modulate_tween and modulate_tween.is_running(): modulate_tween.kill()
			modulate_tween = create_tween()
			modulate_tween.tween_property(sprite, "self_modulate", Color.WHITE, 0.15)
		)
		return
		
	# Standard horizontal dash
	dash_timeout.start()
	ground_dash_direction = -1.0 if sprite.flip_h else 1.0
	var launch_vector := Vector2(ground_dash_direction * dash_velocity, 0.0)
	
	if is_on_floor():
		is_ground_dashing = true
		apply_physics_impulse(launch_vector, false)
		override_animations = true
		sprite.play("Dash")
		
		# Darken instantly
		sprite.self_modulate = Color(0.3, 0.3, 0.3, 1.0)
		
		# 1. Wait for the active dash phase to finish
		await get_tree().create_timer(dash_time).timeout
		
		# 2. Check if we flew off a ledge during the dash!
		if is_on_floor():
			# --- GROUND HALT PATH ---
			is_ground_dashing = false
			velocity = Vector2.ZERO 
			set_smoke_emitting(false)
			
			# Hold the frozen dash frame for a moment
			await get_tree().create_timer(0.05).timeout
			
			# Cleanly return to normal state if we haven't walked off since
			if is_on_floor():
				override_animations = false
				sprite.rotation = 0.0
				current_movement_state = MovementState.NORMAL
				
			# Smoothly blend back to normal
			if modulate_tween and modulate_tween.is_running(): modulate_tween.kill()
			modulate_tween = create_tween()
			modulate_tween.tween_property(sprite, "self_modulate", Color.WHITE, 0.15)
		else:
			# --- LEDGE SLIDE-OFF PATH ---
			is_ground_dashing = false
			is_air_dash_ragdoll = true 
			
			# Smoothly blend back to normal during mid-air launch
			if modulate_tween and modulate_tween.is_running(): modulate_tween.kill()
			modulate_tween = create_tween()
			modulate_tween.tween_property(sprite, "self_modulate", Color.WHITE, 0.25)
	else:
		# --- AIR DASH VERSION ---
		is_ground_dashing = false
		if current_movement_state == MovementState.ON_LEDGE:
			exit_ledge()
			sprite.flip_h = not sprite.flip_h
		if fire < 20: return
		fire -= 20.0
		ground_dash_direction = -1.0 if sprite.flip_h else 1.0
		launch_vector = Vector2(ground_dash_direction * dash_velocity, 0.0)
		apply_physics_impulse(launch_vector, true)
		
		# Darken instantly
		sprite.self_modulate = Color(0.3, 0.3, 0.3, 1.0)
		
		if modulate_tween and modulate_tween.is_running(): modulate_tween.kill()
		modulate_tween = create_tween()
		modulate_tween.tween_property(sprite, "self_modulate", Color.WHITE, dash_time)

func apply_physics_impulse(impulse_velocity: Vector2, from_air_dash: bool = false) -> void:
	if not is_multiplayer_authority(): return
	current_movement_state = MovementState.PHYSICS_OBJECT
	is_air_dash_ragdoll = from_air_dash
	velocity = impulse_velocity * UNIT_SCALE
	if from_air_dash:
		rpc("spawn_explosion")

func grab_ledge() -> void:
	if not is_multiplayer_authority(): return
	current_movement_state = MovementState.ON_LEDGE
	velocity = Vector2.ZERO
	dash_timeout.stop()
	is_ground_dashing = false

func exit_ledge() -> void:
	if not is_multiplayer_authority(): return
	ledge_timeout.start()
	current_movement_state = MovementState.NORMAL
	velocity.y = jump_velocity * UNIT_SCALE

# --- Helper Methods ---
@rpc("any_peer", "call_local", "reliable")
func spawn_explosion() -> void:
	var explosion := EXPLOSION.instantiate() as Node2D
	explosion.global_position = global_position
	get_tree().root.add_child(explosion)

func set_smoke_emitting(emitting: bool) -> void:
	if is_instance_valid(smoke) and is_instance_valid(smoke_2):
		if smoke.Override == false:
			smoke.emitting = emitting
		if smoke_2.Override == false:
			smoke_2.emitting = emitting

func update_camera_extent(dir: float) -> void:
	if not is_multiplayer_authority(): return
	if extend_tween and extend_tween.is_running():
		extend_tween.kill()
		
	var current_range := (extend_range if sprinting else shortened_extend_range) * UNIT_SCALE
	var target_x := dir * current_range
	
	extend_tween = create_tween()
	extend_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	extend_tween.tween_property(camera_pivot, "position:x", target_x, 0.5)

func update_animation() -> void:
	if not is_multiplayer_authority(): return
	if override_animations:
		return
		
	if current_movement_state == MovementState.NORMAL:
		if is_on_floor():
			if velocity.x == 0:
				sprite.play("Idle")
			else:
				sprite.play("Walk" if abs(velocity.x) < (1.9 * UNIT_SCALE) else "Run")
		else:
			sprite.play("Jump" if velocity.y < 0 else "Fall")
	elif current_movement_state == MovementState.ON_LEDGE:
		sprite.play("LedgeGrab")
	elif current_movement_state == MovementState.PHYSICS_OBJECT:
		sprite.play("Hurt" if sprite.sprite_frames.has_animation("Hurt") else "Fall")

# --- Signal Connections ---
func _on_ledge_detecor_area_area_entered(area: Area2D) -> void:
	if not is_multiplayer_authority(): return
	if current_movement_state == MovementState.PHYSICS_OBJECT or current_movement_state == MovementState.ON_LEDGE or not ledge_timeout.is_stopped():
		return
		
	if area.is_in_group("Ledge"):
		var diff = area.global_position.x - global_position.x
		if (not sprite.flip_h and diff > 0) or (sprite.flip_h and diff < 0):
			grab_ledge()

func _on_fire_fill_timeout() -> void:
	if not is_multiplayer_authority(): return
	if fire < 100:
		fire += 0.5

func damage(value: float) -> void:
	Health = max(Health - value, 0.0)

func heal(value: float) -> void:
	Health = min(Health + value, Max_Health)

# --- Updated Punch Implementation ---

var old_speed: float = -1.0 # Initialize to sentinel value

func punch() -> void:
	if not can_punch:
		return
		
	# Instantly lock execution until cooldown completes
	can_punch = false
	punch_cooldown.start()
	
	# Only store speed_multiplier if we haven't already saved it
	if old_speed < 0.0:
		old_speed = speed_multiplier
	speed_multiplier = 0.0
	
	# Stop combo reset timer while attacking
	punch_timeout.start()
	
	# Advance combo step (1 through 4)
	combo_count = (combo_count % 4) + 1
	
	# Handle Fire requirement for Step 4
	if combo_count == 4:
		if fire > 20:
			fire -= 20
		else:
			# Reset to Step 1 if not enough fire
			combo_count = 1
	
	var current_step: int = combo_count
	
	# Force override animations to guarantee current punch plays
	override_animations = true
	
	# Apply forward lunge impulse
	var forward_direction: float = -1.0 if sprite.flip_h else 1.0
	velocity.x = forward_direction * (punch_dash_speed * UNIT_SCALE)
	
	# Play corresponding punch animation
	match current_step:
		1: sprite.play("Punch1")
		2: sprite.play("Punch2")
		3: sprite.play("Punch3")
		4:
			sprite.play("Punch4")
			_execute_finisher()
			

func _execute_finisher() -> void:
	# Use a timer or await safely
	var timer = get_tree().create_timer(0.1)
	await timer.timeout
	if not is_inside_tree(): 
		return # Ensure node wasn't freed during wait
		
	sprite.flip_h = not sprite.flip_h
	rpc("spawn_explosion")
	dash()

func _on_punch_cooldown_timeout() -> void:
	can_punch = true
	override_animations = false
	
	# Restore speed properly
	if old_speed >= 0.0:
		speed_multiplier = old_speed
		old_speed = -1.0 # Reset sentinel

func _on_punch_timeout_timeout() -> void:
	combo_count = 0
