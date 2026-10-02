class_name PlayerController
extends CharacterBody2D

# --- Constants & Enums ---
const UNIT_SCALE: float = 100.0
const EXPLOSION: PackedScene = preload("res://Scenes/Effects/explosion.tscn")

enum State { NORMAL, CUTSCENE, DEAD }
enum MovementState { NORMAL, ON_LEDGE, PHYSICS_OBJECT }

# --- Export Variables ---

@export var death_scene: String = "res://Scenes/Menus/menu.tscn"

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
@export var bounciness: float = 0.35
@export var physics_friction: float = 10.0
@export var fire: float = 100.0:
	set(value):
		fire = value
		if is_instance_valid(fire_bar):
			fire_bar.value = value
@export var punch_dash_speed: float = 7.5

@export_group("Upgrades")
@export var Can_Flame_Burst: bool = false
@export var Can_Air_Dash: bool = false
@export var Can_Up_Blast: bool = false

@export_group("Death Impulse")
@export var death_launch_force: Vector2 = Vector2(4.0, -7.0)
@export var death_despawn_time: float = 2.0

@export_group("State")
@export var current_state: State = State.NORMAL
@export var current_movement_state: MovementState = MovementState.NORMAL

@export_group("Camera & Shake")
@export var smoothness_speed: float = 6.0
@export var extend_range: float = 2.0
@export var shortened_extend_range: float = 1.0
@export var shake_decay: float = 5.0
@export var max_offset: Vector2 = Vector2(12.0, 8.0)
@export var max_roll: float = 0.05

# --- Onready Nodes ---
@onready var fire_fill: Timer = $FireFill
@onready var dash_timeout: Timer = $DashTimeout
@onready var smoke: GPUParticles2D = $Smoke/Smoke
@onready var smoke_2: GPUParticles2D = $Smoke/Smoke2
@onready var camera: Camera2D = $CamPivot/Camera2D
@onready var camera_pivot: Node2D = $CamPivot
@onready var sprite: AnimatedSprite2D = $SpriteTransformOffset/SpriteSheet
@onready var ledge_detector_area: Area2D = $LedgeDetecorArea
@onready var ledge_timeout: Timer = $LedgeTimeout
@onready var fire_bar_container: Control = $UI/SafeScreen/FireBar
@onready var fire_bar: TextureProgressBar = $UI/SafeScreen/FireBar/TextureProgressBar2
@onready var ui: CanvasLayer = $UI
@onready var health_bar_container: Control = $UI/SafeScreen/HealthBar
@onready var health_bar: TextureProgressBar = $UI/SafeScreen/HealthBar/TextureProgressBar2
@onready var punch_timeout: Timer = $PunchTimeout
@onready var punch_cooldown: Timer = $PunchCooldown
@onready var punch_hitbox: Area2D = $PunchHitbox
@onready var invincibility_timer: Timer = $InvincibilityTimer
@onready var coyote_time: Timer = $CoyoteTime
@onready var jump_buffer: Timer = $JumpBuffer


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
var old_speed: float = -1.0
var is_invincible: bool = false
var is_in_ledge: bool = false

# Shake variables
var shake_trauma: float = 0.0
var noise := FastNoiseLite.new()

@export_group("Stats")
@export var Health: float = 75.0:
	set(value):
		Health = value
		if is_instance_valid(health_bar):
			health_bar.value = value
@export var Max_Health: float = 75.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# Ensure multiplayer network loop is active and this node belongs to the local client
		if multiplayer and is_multiplayer_authority():
			# Additional safeguard: verify this authority matches the local machine's unique peer ID
			if multiplayer.get_unique_id() == get_multiplayer_authority():
				var tree := Engine.get_main_loop() as SceneTree
				if tree and not death_scene.is_empty():
					tree.change_scene_to_file.call_deferred(death_scene)

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
	
	Health = Max_Health
	if is_instance_valid(health_bar):
		health_bar.max_value = Max_Health
		health_bar.value = Max_Health
		
	current_speed = walk_speed
	camera.position_smoothing_speed = smoothness_speed
	
	# Noise generator setup for procedural screen shake
	noise.seed = randi()
	noise.frequency = 0.1
	
	if invincibility_timer and not invincibility_timer.timeout.is_connected(_on_invincibility_timer_timeout):
		invincibility_timer.timeout.connect(_on_invincibility_timer_timeout)
	
	if not sprite.animation_finished.is_connected(_on_sprite_animation_finished):
		sprite.animation_finished.connect(_on_sprite_animation_finished)
	
	var preset := Control.PRESET_TOP_LEFT if (OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")) else Control.PRESET_BOTTOM_LEFT
	if OS.has_feature("mobile"):
		Input.emulate_mouse_from_touch = false
	fire_bar_container.set_anchors_preset(preset, false)

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority(): return
	
	_process_camera_shake(delta)
	
	dash_timeout.wait_time = 0.7

	if current_state == State.DEAD:
		_process_death_movement(delta)
		return

	if is_on_floor():
		can_dash = true
		
	if current_movement_state == MovementState.NORMAL:
		var is_upward_dashing: bool = not can_dash and not dash_timeout.is_stopped()
		set_smoke_emitting(is_upward_dashing)
		
		var was_on_floor : bool = is_on_floor()
		
		if not is_on_floor():
			velocity += (get_gravity() * gravity_multiplier) * delta

		# --- Jump Buffer & Coyote Time Logic ---
		if Input.is_action_just_pressed("Jump"):
			jump_buffer.start()

		var can_jump: bool = is_on_floor() or not coyote_time.is_stopped()
		var has_buffered_jump: bool = not jump_buffer.is_stopped()

		if has_buffered_jump and can_jump:
			velocity.y = jump_velocity * UNIT_SCALE
			coyote_time.stop()
			jump_buffer.stop()
		# ---------------------------------------
			
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
		
		if was_on_floor and not is_on_floor() and velocity.y >= 0:
			coyote_time.start()
		
	elif current_movement_state == MovementState.ON_LEDGE:
		velocity = Vector2.ZERO
		set_smoke_emitting(false)
		update_animation()
		update_camera_extent(0)
		last_direction = 0
		if Input.is_action_just_pressed("Jump"):
			exit_ledge()
			
	elif current_movement_state == MovementState.PHYSICS_OBJECT:
		override_animations = true
		
		if not is_on_floor():
			set_smoke_emitting(true)
			play_animation_once("Ragdoll")
			sprite.rotate(deg_to_rad(20 if velocity.x > 0 else -20))
		else:
			set_smoke_emitting(is_air_dash_ragdoll and not is_ground_dashing)
			play_animation_once("Dash")
			
		if is_ground_dashing:
			velocity.x = ground_dash_direction * dash_velocity * UNIT_SCALE
		
		velocity += (get_gravity() * gravity_multiplier) * delta
		move_and_slide()
		
		# --- IMMEDIATE FLOOR RECOVERY & LANDING LOGIC ---
		if is_on_floor() and not is_ground_dashing:
			current_movement_state = MovementState.NORMAL
			override_animations = false
			is_air_dash_ragdoll = false
			sprite.rotation = 0.0
			set_smoke_emitting(false)
		else:
			if is_on_wall_only() or is_on_ceiling():
				var collision := get_last_slide_collision()
				if collision:
					velocity = velocity.bounce(collision.get_normal()) * bounciness
				if is_on_wall():
					current_movement_state = MovementState.NORMAL
					sprite.rotation = 0.0
					override_animations = false
					
			var friction_reduction := (deceleration if is_on_floor() else air_deceleration) * physics_friction
			velocity.x = move_toward(velocity.x, 0.0, friction_reduction * delta)
			
			if abs(velocity.x) < 0.5 * UNIT_SCALE:
				current_movement_state = MovementState.NORMAL
				override_animations = false
				sprite.rotation = 0.0
				set_smoke_emitting(false)
				
		update_animation()


func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or current_state == State.DEAD:
		return

	if current_movement_state == MovementState.PHYSICS_OBJECT and not is_ground_dashing:
		return
		
	if event.is_action_pressed("Sprint"):
		if event is InputEventAction and event.action == "Sprint":
			sprinting = event.pressed
		else:
			sprinting = not sprinting
		
	if event.is_action_pressed("Dash") and can_dash:
		if dash_timeout.is_stopped():
			dash()
			
	if event.is_action_pressed("Punch"):
		punch()
		
	# --- VARIABLE JUMP HEIGHT LOGIC ---
	if event.is_action_released("Jump"):
		# Only cut momentum if the player is actively rising (moving upward)
		if velocity.y < 0.0:
			# Mulitply or clamp the velocity to cut the upward rise cleanly.
			# Setting to a small downward value or near zero allows gravity 
			# in _physics_process() to naturally pull the player down.
			velocity.y = max(velocity.y, jump_velocity * UNIT_SCALE * 0.25)

# --- Animation Handling ---
func update_animation() -> void:
	if not is_multiplayer_authority() or current_state == State.DEAD: return
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
		play_animation_once("LedgeGrab")
	elif current_movement_state == MovementState.PHYSICS_OBJECT:
		var hurt_anim := "Hurt" if sprite.sprite_frames.has_animation("Hurt") else "Fall"
		play_animation_once(hurt_anim)

func play_animation_once(anim_name: StringName) -> void:
	if sprite.animation != anim_name:
		sprite.play(anim_name)

func _on_sprite_animation_finished() -> void:
	if current_state == State.DEAD:
		return
	match sprite.animation:
		"Hurt", "Punch1", "Punch2", "Punch3", "Punch4", "LedgeGrab", "Dash":
			if current_movement_state == MovementState.NORMAL:
				override_animations = false

# --- Gameplay Actions ---
func dash() -> void:
	if not dash_timeout.is_stopped() or (current_movement_state == MovementState.PHYSICS_OBJECT and not is_ground_dashing):
		return
		
	is_in_ledge = false
		
	if modulate_tween and modulate_tween.is_running():
		modulate_tween.kill()
		
	if Input.is_action_pressed("Move_Up") and Can_Up_Blast:
		if fire < 20: return
		fire -= 20.0
		dash_timeout.start(0.2)
		dash_timeout.wait_time = 0.7
		current_movement_state = MovementState.NORMAL
		velocity.y = -dash_velocity * UNIT_SCALE
		can_dash = false
		rpc("spawn_explosion")
		play_animation_once("Jump")
		set_smoke_emitting(true)
		
		grant_invincibility(0.3)
		
		sprite.self_modulate = Color(0.3, 0.3, 0.3, 1.0)
		get_tree().create_timer(0.3).timeout.connect(func():
			if modulate_tween and modulate_tween.is_running(): modulate_tween.kill()
			modulate_tween = create_tween()
			modulate_tween.tween_property(sprite, "self_modulate", Color.WHITE, 0.15)
		)
		return
		
	ground_dash_direction = -1.0 if sprite.flip_h else 1.0
	var launch_vector := Vector2(ground_dash_direction * dash_velocity, 0.0)
	
	if is_on_floor():
		dash_timeout.start()
		is_ground_dashing = true
		apply_physics_impulse(launch_vector, false)
		override_animations = true
		play_animation_once("Dash")
		
		grant_invincibility(0.3)
		
		sprite.self_modulate = Color(0.3, 0.3, 0.3, 1.0)
		
		await get_tree().create_timer(dash_time).timeout
		
		if is_on_floor():
			is_ground_dashing = false
			velocity = Vector2.ZERO 
			set_smoke_emitting(false)
			
			await get_tree().create_timer(0.05).timeout
			
			if is_on_floor():
				override_animations = false
				sprite.rotation = 0.0
				current_movement_state = MovementState.NORMAL
				
			if modulate_tween and modulate_tween.is_running(): modulate_tween.kill()
			modulate_tween = create_tween()
			modulate_tween.tween_property(sprite, "self_modulate", Color.WHITE, 0.15)
		else:
			dash_timeout.start(0.3)
			is_ground_dashing = false
			is_air_dash_ragdoll = true 
			
			if modulate_tween and modulate_tween.is_running(): modulate_tween.kill()
			modulate_tween = create_tween()
			modulate_tween.tween_property(sprite, "self_modulate", Color.WHITE, 0.25)
	elif Can_Air_Dash:
		is_ground_dashing = false
		if current_movement_state == MovementState.ON_LEDGE:
			exit_ledge()
			sprite.flip_h = not sprite.flip_h
		if fire < 20: return
		fire -= 20.0
		ground_dash_direction = -1.0 if sprite.flip_h else 1.0
		launch_vector = Vector2(ground_dash_direction * dash_velocity, 0.0)
		apply_physics_impulse(launch_vector, true)
		
		grant_invincibility(0.3)
		
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
	is_in_ledge = true
	current_movement_state = MovementState.ON_LEDGE
	velocity = Vector2.ZERO
	dash_timeout.stop()
	is_ground_dashing = false

func exit_ledge() -> void:
	if not is_multiplayer_authority(): return
	is_in_ledge = false
	ledge_timeout.start()
	current_movement_state = MovementState.NORMAL
	velocity.y = jump_velocity * UNIT_SCALE

# --- Camera Shake System ---
func apply_shake(amount: float) -> void:
	shake_trauma = clamp(shake_trauma + amount, 0.0, 1.0)

func _process_camera_shake(delta: float) -> void:
	if not is_instance_valid(camera) or shake_trauma <= 0.0:
		if is_instance_valid(camera):
			camera.offset = Vector2.ZERO
			camera.rotation = 0.0
		return

	shake_trauma = max(shake_trauma - shake_decay * delta, 0.0)
	var amount := shake_trauma * shake_trauma
	
	var time := Time.get_ticks_msec() * 0.05
	var offset_x := max_offset.x * amount  * noise.get_noise_2d(time, 0.0)
	var offset_y := max_offset.y * amount  * noise.get_noise_2d(0.0, time)
	
	camera.offset = Vector2(offset_x, offset_y)
	camera.rotation = max_roll * amount * noise.get_noise_2d(time, time)

# --- Damage, Invincibility & Death Implementation ---
@rpc("any_peer", "call_local", "reliable")
func request_damage(value: float, origin: Vector2 = Vector2.ZERO, velocity_multiplier: float = 1.0) -> void:
	if not is_multiplayer_authority() or current_state == State.DEAD:
		return
	damage(value, origin, velocity_multiplier)

func damage(value: float, origin: Vector2 = Vector2.ZERO, velocity_multiplier: float = 1.0) -> void:
	if current_state == State.DEAD or is_invincible and !invincibility_timer.is_stopped():
		return
	grant_invincibility(3.0)

	Health = max(Health - value, 0.0)
	_play_hit_flash.rpc()
	apply_shake(40000)
	
	set_physics_process(false)
	override_animations = true
	sprite.play("Ragdoll")
	await get_tree().create_timer(0.2).timeout
	set_physics_process(true)
	override_animations = false

	if Health <= 0.0:
		_sync_die.rpc(origin)
	elif origin != Vector2.ZERO:
		var dir_x := 1.0 if origin.x < global_position.x else -1.0
		apply_physics_impulse(Vector2(4.0 * dir_x * velocity_multiplier, -3.0 * velocity_multiplier))

func grant_invincibility(time: float = 1.0) -> void:
	is_invincible = true
	var duration: float = time
	
	if time > invincibility_timer.time_left:
		invincibility_timer.start(duration)
		
	if sprite:
		var flash_tween := create_tween().set_loops(max(1, int(duration / 0.1)))
		flash_tween.tween_property(sprite, "modulate:a", 0.3, 0.05)
		flash_tween.tween_property(sprite, "modulate:a", 1.0, 0.05)

func _on_invincibility_timer_timeout() -> void:
	is_invincible = false
	if sprite:
		sprite.modulate.a = 1.0

func heal(value: float) -> void:
	if current_state == State.DEAD:
		return
	Health = min(Health + value, Max_Health)

@rpc("authority", "call_local", "reliable")
func _play_hit_flash() -> void:
	if sprite:
		if modulate_tween and modulate_tween.is_running():
			modulate_tween.kill()
		sprite.self_modulate = Color.RED
		modulate_tween = create_tween()
		modulate_tween.tween_property(sprite, "self_modulate", Color.WHITE, 3)

@rpc("authority", "call_local", "reliable")
func _sync_die(origin: Vector2 = Vector2.ZERO) -> void:
	die(origin)

func die(origin: Vector2 = Vector2.ZERO) -> void:
	current_state = State.DEAD
	override_animations = true
	set_smoke_emitting(false)

	set_collision_layer_value(1, false)
	set_collision_mask_value(1, false)

	var dir_x: float = 0.0
	if origin != Vector2.ZERO:
		dir_x = 1.0 if origin.x < global_position.x else -1.0
	else:
		dir_x = -1.0 if sprite and sprite.flip_h else 1.0

	velocity = Vector2(death_launch_force.x * dir_x, death_launch_force.y) * UNIT_SCALE

	if sprite:
		var death_anim := "Ragdoll" if sprite.sprite_frames.has_animation("Ragdoll") else "Hurt"
		sprite.play(death_anim)

	var fade_tween := create_tween()
	fade_tween.tween_property(self, "modulate:a", 0.0, death_despawn_time).set_delay(death_despawn_time * 0.5)
	fade_tween.tween_callback(queue_free)

func _process_death_movement(delta: float) -> void:
	if not is_on_floor():
		velocity += (get_gravity() * gravity_multiplier) * delta
	else:
		velocity.x = move_toward(velocity.x, 0.0, deceleration * UNIT_SCALE * delta)
	move_and_slide()

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

# --- Signal Connections ---
func _on_ledge_detecor_area_area_entered(area: Area2D) -> void:
	if not is_multiplayer_authority() or current_state == State.DEAD: return
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

# --- Punch Implementation ---
func punch() -> void:
	if not can_punch or current_state != State.NORMAL or is_in_ledge:
		return
		
	can_punch = false
	punch_cooldown.start()
	
	punch_timeout.start()
	combo_count = (combo_count % 4) + 1
	
	if combo_count == 4 and Can_Flame_Burst == true:
		if fire > 10:
			fire -= 10
			_execute_finisher()
			play_animation_once("Punch4")
		else:
			combo_count = 1
	else:
		punch_hitbox_activate(0.15)
		var current_step: int = 1 if combo_count == 4 else combo_count
		override_animations = true
		
		if is_on_floor():
			if old_speed < 0.0:
				old_speed = speed_multiplier
				speed_multiplier = 0.0
			if current_step != 4:
				var forward_direction: float = -1.0 if sprite.flip_h else 1.0
				velocity.x = forward_direction * (punch_dash_speed * UNIT_SCALE)
		
		match current_step:
			1: play_animation_once("Punch1")
			2: play_animation_once("Punch2")
			3: play_animation_once("Punch3")

func punch_hitbox_activate(linger: float) -> void:
	var hitbox : Area2D = punch_hitbox.duplicate()
	add_child(hitbox)
	var direction = -1.0 if sprite.flip_h else 1.0
	if direction < 0:
		hitbox.scale.x = -1
	else:
		hitbox.scale.x = 1
	hitbox.area_entered.connect(_on_punch_hitbox_area_entered)
	hitbox.visible = true
	hitbox.monitorable = true
	hitbox.monitoring = true
	await get_tree().create_timer(linger).timeout
	hitbox.queue_free()

func _execute_finisher() -> void:
	var timer = get_tree().create_timer(0.2)
	await timer.timeout
	if not is_inside_tree(): 
		return
		
	sprite.flip_h = not sprite.flip_h
	rpc("spawn_explosion")
	dash()

func _on_punch_cooldown_timeout() -> void:
	can_punch = true
	override_animations = false
	
	if old_speed >= 0.0:
		speed_multiplier = old_speed
		old_speed = -1.0

func _on_punch_timeout_timeout() -> void:
	combo_count = 0

func _on_punch_hitbox_area_entered(area: Area2D) -> void:
	var parent_node = area.get_parent()
	if parent_node.is_in_group("Entity") and parent_node.is_in_group("Enemy"):
		if parent_node.has_method("damage"):
			parent_node.damage(20, global_position, 1, self)
			apply_shake(100)
			print("Hit!")
			var direction = -1.0 if sprite.flip_h else 1.0
			velocity.y = -1 * UNIT_SCALE
			velocity.x = (1 * UNIT_SCALE) * direction
