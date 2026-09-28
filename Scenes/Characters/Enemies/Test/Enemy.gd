class_name EnemyBase
extends CharacterBody2D

# --- Constants & Enums ---
const UNIT_SCALE: float = 100.0
const EXPLOSION: PackedScene = preload("res://Scenes/Effects/explosion.tscn")

enum State { IDLE, PATROL, CHASE, ATTACK, STUNNED, DEAD }
enum MovementState { NORMAL, ON_LEDGE, PHYSICS_OBJECT }

@export_group("AI")
@export var Target: CharacterBody2D
@export var target_scene: PackedScene

# --- Export Variables ---
@export_group("Movement")
@export var walk_speed: float = 1.4
@export var run_speed: float = 3.0
@export var jump_velocity: float = -8.5
@export var gravity_multiplier: float = 2.0
@export var speed_multiplier: float = 1.0
@export var acceleration: float = 17.5
@export var air_acceleration: float = 15.0
@export var deceleration: float = 26.0
@export var air_deceleration: float = 5.0

@export_group("Combat & Physics")
@export var max_health: float = 100.0
@export var bounciness: float = 0.35
@export var physics_friction: float = 10.0

@export_group("Death Impulse")
@export var death_launch_force: Vector2 = Vector2(5.0, -8.0)
@export var death_spin_speed: float = 12.0
@export var death_despawn_time: float = 2.0

@export_group("State")
@export var current_state: State = State.IDLE
@export var current_movement_state: MovementState = MovementState.NORMAL

# --- AI Input Targets ---
var move_direction: float = 0.0
var wants_to_run: bool = false

# --- Runtime Variables ---
var health: float = 100.0
var current_speed: float = 1.4
var override_animations: bool = false
var modulate_tween: Tween
var death_angular_velocity: float = 0.0
var is_landing_settled: bool = false
var is_jumping_detour: bool = false

# --- Aggro System ---
var last_attacker: CharacterBody2D = null

# --- Advanced Link & Platform Traversal ---
var is_traversing_link: bool = false
var link_exit_position: Vector2 = Vector2.ZERO
var link_target_velocity_x: float = 0.0

# --- Onready Nodes ---
@onready var smoke: GPUParticles2D = get_node_or_null("Smoke/Smoke")
@onready var smoke_2: GPUParticles2D = get_node_or_null("Smoke/Smoke2")
@onready var sprite: AnimatedSprite2D = $SpriteSheet
@onready var ledge_timeout: Timer = get_node_or_null("LedgeTimeout")

@onready var WallRaycast: RayCast2D = $WallCheck/RayCast2D
@onready var wall_check: Node2D = $WallCheck
@onready var LedgeRayCast: RayCast2D = $LedgeCheck/RayCast2D
@onready var ledge_check: Node2D = $LedgeCheck
@onready var navigation_agent_2d: NavigationAgent2D = $NavigationAgent2D

func _enter_tree() -> void:
	# Server runs AI logic and authority calculations
	set_multiplayer_authority(1)

func _ready() -> void:
	health = max_health
	
	if sprite and not sprite.animation_finished.is_connected(_on_sprite_animation_finished):
		sprite.animation_finished.connect(_on_sprite_animation_finished)
		
	# Server handles AI state and navigation initialization
	if multiplayer.is_server():
		current_state = State.CHASE
		var items = [run_speed, walk_speed]
		current_speed = items.pick_random()

		if navigation_agent_2d:
			if not navigation_agent_2d.link_reached.is_connected(_on_navigation_agent_2d_link_reached):
				navigation_agent_2d.link_reached.connect(_on_navigation_agent_2d_link_reached)
			
		_try_find_target()
		if not is_instance_valid(Target):
			get_tree().node_added.connect(_on_node_added)
			
		call_deferred("actor_setup")

func actor_setup() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	if is_instance_valid(Target) and navigation_agent_2d:
		navigation_agent_2d.target_position = Target.global_position

func _try_find_target() -> void:
	if is_instance_valid(last_attacker):
		Target = last_attacker
		return

	var players := get_tree().get_nodes_in_group("Player")
	var nearest_player: CharacterBody2D = null
	var shortest_distance: float = INF

	for node in players:
		if node is CharacterBody2D and is_instance_valid(node):
			var dist := global_position.distance_squared_to(node.global_position)
			if dist < shortest_distance:
				shortest_distance = dist
				nearest_player = node as CharacterBody2D

	if nearest_player:
		Target = nearest_player
		return

	var current_scene := get_tree().current_scene
	if current_scene and target_scene:
		var dummy := target_scene.instantiate()
		var target_script: Script = dummy.get_script()
		dummy.free()

		if target_script:
			for child in current_scene.get_children():
				if child.get_script() == target_script and child is CharacterBody2D:
					Target = child as CharacterBody2D
					return

func _on_node_added(node: Node) -> void:
	if is_instance_valid(Target):
		return

	if node is CharacterBody2D and node.is_in_group("Player"):
		_try_find_target()
		if is_instance_valid(Target) and get_tree().node_added.is_connected(_on_node_added):
			get_tree().node_added.disconnect(_on_node_added)

func _physics_process(delta: float) -> void:
	# CLIENT: Sync animations/sprite flipping locally based on server state
	if not multiplayer.is_server():
		update_animation()
		if sprite and move_direction != 0.0:
			sprite.flip_h = move_direction < 0.0
		return

	# SERVER: Full AI, State, and Physics processing
	if current_state == State.DEAD:
		_process_death_movement(delta)
		return

	match current_movement_state:
		MovementState.NORMAL:
			_process_normal_movement(delta)
		MovementState.ON_LEDGE:
			_process_ledge_movement()
		MovementState.PHYSICS_OBJECT:
			_process_physics_object_movement(delta)

# --- Movement Processing ---
func _process_normal_movement(delta: float) -> void:
	set_smoke_emitting(false)
	
	_process_ai_navigation()
	
	if velocity.x != 0.0:
		var dir_sign: float = sign(velocity.x)
		wall_check.scale.x = -dir_sign
		ledge_check.scale.x = -dir_sign
	
	if not is_on_floor():
		velocity += (get_gravity() * gravity_multiplier) * delta
		
	current_speed = run_speed if wants_to_run else walk_speed
	var accel := (acceleration if is_on_floor() else air_acceleration) * UNIT_SCALE
	var deccel := (deceleration if is_on_floor() else air_deceleration) * UNIT_SCALE
	var target_speed := current_speed * speed_multiplier * UNIT_SCALE
	
	if is_traversing_link and not is_on_floor():
		velocity.x = move_toward(velocity.x, link_target_velocity_x, accel * delta)
	elif move_direction != 0.0:
		velocity.x = move_toward(velocity.x, move_direction * target_speed, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, deccel * delta)
		
	if sprite and move_direction != 0.0:
		sprite.flip_h = move_direction < 0.0

	move_and_slide()
	update_animation()

# --- AI Navigation Processing ---
func _process_ai_navigation() -> void:
	if not is_instance_valid(navigation_agent_2d):
		return

	if not is_instance_valid(Target):
		_try_find_target()
		if not is_instance_valid(Target):
			move_direction = 0.0
			return
	elif not is_instance_valid(last_attacker):
		_try_find_target()

	if is_jumping_detour:
		if is_on_floor() and velocity.y >= 0:
			is_jumping_detour = false
		else:
			return

	if current_state == State.CHASE or current_state == State.IDLE:
		if is_on_floor() and not is_traversing_link:
			navigation_agent_2d.target_position = Target.global_position

	if is_traversing_link:
		var dist_to_exit := global_position.distance_to(link_exit_position)
		var x_diff := link_exit_position.x - global_position.x
		
		if abs(x_diff) > 4.0:
			move_direction = sign(x_diff)
			
		if dist_to_exit < 20.0 or (is_on_floor() and velocity.y >= 0.0 and global_position.y >= link_exit_position.y - 10.0):
			is_traversing_link = false
		return

	if navigation_agent_2d.is_navigation_finished():
		move_direction = 0.0
		return

	var next_path_pos: Vector2 = navigation_agent_2d.get_next_path_position()
	var dir_to_next: Vector2 = global_position.direction_to(next_path_pos)
	
	move_direction = sign(dir_to_next.x) if abs(dir_to_next.x) > 0.05 else 0.0
	wants_to_run = (current_state == State.CHASE)

	if is_on_floor():
		var y_diff: float = next_path_pos.y - global_position.y
		var x_diff: float = next_path_pos.x - global_position.x
		
		if WallRaycast and WallRaycast.is_colliding() and move_direction != 0.0:
			if not _is_ceiling_above():
				jump()
		elif y_diff < -24.0 and abs(x_diff) < 64.0:
			if not _is_ceiling_above():
				jump()
		elif LedgeRayCast and not LedgeRayCast.is_colliding() and move_direction != 0.0:
			if y_diff < 32.0 and not _is_ceiling_above():
				jump()

# --- Navigation Link Traversal ---
func _on_navigation_agent_2d_link_reached(details: Dictionary) -> void:
	var entry_pos: Vector2 = details.get("link_entry_position", global_position)
	var exit_pos: Vector2 = details.get("link_exit_position", global_position)
	
	is_traversing_link = true
	link_exit_position = exit_pos

	var delta_pos := exit_pos - entry_pos
	var gravity_accel := get_gravity().y * gravity_multiplier
	var initial_jump_vy := jump_velocity * UNIT_SCALE

	if delta_pos.y < -10.0:
		if is_on_floor() and not _is_ceiling_above():
			jump()
			
		var time_to_peak: float = abs(initial_jump_vy) / gravity_accel
		var total_flight_time := time_to_peak * 2.0
		if total_flight_time > 0.0:
			link_target_velocity_x = delta_pos.x / total_flight_time
	else:
		link_target_velocity_x = sign(delta_pos.x) * (run_speed if wants_to_run else walk_speed) * UNIT_SCALE
		if delta_pos.y < 10.0 and is_on_floor() and not _is_ceiling_above():
			jump()

func _is_ceiling_above() -> bool:
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, global_position + Vector2.UP * 32.0)
	query.exclude = [self]
	var result := space_state.intersect_ray(query)
	return result.size() > 0

func _process_ledge_movement() -> void:
	velocity = Vector2.ZERO
	set_smoke_emitting(false)
	update_animation()

func _process_physics_object_movement(delta: float) -> void:
	override_animations = true
	
	if not is_on_floor():
		set_smoke_emitting(true)
		play_animation_once("Ragdoll")
		if sprite:
			sprite.rotate(deg_to_rad(20.0 if velocity.x > 0 else -20.0))
	else:
		play_animation_once("Dash")
		
	velocity += (get_gravity() * gravity_multiplier) * delta
	move_and_slide()
	
	if is_on_wall_only() or is_on_ceiling():
		var collision := get_last_slide_collision()
		if collision:
			velocity = velocity.bounce(collision.get_normal()) * bounciness
		if is_on_wall():
			_recover_from_physics_state()
			
	var friction_reduction := (deceleration if is_on_floor() else air_deceleration) * physics_friction
	velocity.x = move_toward(velocity.x, 0.0, friction_reduction * delta)
	
	update_animation()
	
	if is_on_floor() or abs(velocity.x) < (0.5 * UNIT_SCALE):
		_recover_from_physics_state()

func _process_death_movement(delta: float) -> void:
	if not is_on_floor():
		is_landing_settled = false
		velocity += (get_gravity() * gravity_multiplier) * delta
		rotate(death_angular_velocity * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, deceleration * UNIT_SCALE * delta)
		
		if not is_landing_settled:
			is_landing_settled = true
			death_angular_velocity = 0.0
			
			var current_rot: float = rotation
			var target_rot: float = round((current_rot - PI / 2.0) / PI) * PI + PI / 2.0
			
			var land_tween := create_tween()
			land_tween.tween_property(self, "rotation", target_rot, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	move_and_slide()
	
	if is_on_wall():
		var collision := get_last_slide_collision()
		if collision:
			velocity = velocity.bounce(collision.get_normal()) * bounciness
			death_angular_velocity *= -0.8

func _recover_from_physics_state() -> void:
	if current_state == State.DEAD:
		return
	override_animations = false
	rotation = 0.0
	if sprite:
		sprite.rotation = 0.0
	current_movement_state = MovementState.NORMAL
	set_smoke_emitting(false)

# --- AI Commands ---
func jump() -> void:
	if is_on_floor() and current_movement_state == MovementState.NORMAL and current_state != State.DEAD:
		velocity.y = jump_velocity * UNIT_SCALE
		is_jumping_detour = true

func apply_impulse(impulse_velocity: Vector2, linger: float) -> void:
	if current_state == State.DEAD:
		return
	current_movement_state = MovementState.PHYSICS_OBJECT
	velocity = impulse_velocity * UNIT_SCALE
	await get_tree().create_timer(linger).timeout
	if current_state != State.DEAD:
		current_movement_state = MovementState.NORMAL

# Remote call for clients/players to deal damage to the server-authoritative enemy
@rpc("any_peer", "call_local", "reliable")
func request_damage(amount: float, origin: Vector2, velocit_multiplier: float, attacker_path: NodePath = NodePath("")) -> void:
	if not multiplayer.is_server():
		return
		
	var attacker: CharacterBody2D = get_node_or_null(attacker_path) as CharacterBody2D
	damage(amount, origin, velocit_multiplier, attacker)

func damage(amount: float, origin: Vector2, velocit_multiplier: float, attacker: CharacterBody2D = null) -> void:
	if current_state == State.DEAD:
		return

	if is_instance_valid(attacker):
		last_attacker = attacker
		Target = attacker

	health = clamp(health - amount, 0.0, max_health)
	_play_hit_flash.rpc()
	
	if health <= 0.0:
		die(origin)
		set_collision_mask_value(2, false)
	elif origin != Vector2.ZERO:
		if origin.x < global_position.x:
			global_position.y += 10
			apply_impulse(Vector2(4 * velocit_multiplier, -2 * velocit_multiplier), 0.4)
		elif origin.x > global_position.x:
			global_position.y += 10
			apply_impulse(Vector2(-4 * velocit_multiplier, -2 * velocit_multiplier), 0.4)

@rpc("authority", "call_local", "reliable")
func _play_hit_flash() -> void:
	if sprite:
		if modulate_tween and modulate_tween.is_running(): 
			modulate_tween.kill()
		sprite.self_modulate = Color.RED
		modulate_tween = create_tween()
		modulate_tween.tween_property(sprite, "self_modulate", Color.WHITE, 0.2)

func die(origin: Vector2 = Vector2.ZERO) -> void:
	current_state = State.DEAD
	override_animations = true
	
	set_collision_mask_value(3, false)
	
	var dir_x: float = 0.0
	if origin != Vector2.ZERO:
		dir_x = 1.0 if origin.x < global_position.x else -1.0
	else:
		dir_x = -1.0 if sprite and sprite.flip_h else 1.0
		
	velocity = Vector2(death_launch_force.x * dir_x, death_launch_force.y) * UNIT_SCALE
	death_angular_velocity = dir_x * death_spin_speed
	
	if sprite:
		var death_anim := "Ragdoll" if sprite.sprite_frames.has_animation("Ragdoll") else "Hurt"
		sprite.play(death_anim)
	
	var fade_tween := create_tween()
	fade_tween.tween_property(self, "modulate:a", 0.0, death_despawn_time).set_delay(death_despawn_time * 0.5)
	fade_tween.tween_callback(queue_free)

# --- Visuals & Animations ---
func update_animation() -> void:
	if override_animations or not sprite or current_state == State.DEAD:
		return
		
	match current_movement_state:
		MovementState.NORMAL:
			if is_on_floor():
				if velocity.x == 0.0:
					sprite.play("Idle")
				else:
					sprite.play("Walk" if abs(velocity.x) < (1.9 * UNIT_SCALE) else "Run")
			else:
				sprite.play("Jump" if velocity.y < 0.0 else "Fall")
		MovementState.ON_LEDGE:
			play_animation_once("LedgeGrab")
		MovementState.PHYSICS_OBJECT:
			var hurt_anim := "Hurt" if sprite.sprite_frames.has_animation("Hurt") else "Fall"
			play_animation_once(hurt_anim)

func play_animation_once(anim_name: StringName) -> void:
	if sprite and sprite.animation != anim_name:
		sprite.play(anim_name)

func _on_sprite_animation_finished() -> void:
	if not sprite or current_state == State.DEAD:
		return
	match sprite.animation:
		"Hurt", "LedgeGrab", "Dash":
			if current_movement_state == MovementState.NORMAL:
				override_animations = false

func set_smoke_emitting(emitting: bool) -> void:
	if is_instance_valid(smoke) and not smoke.get("Override"):
		smoke.emitting = emitting
	if is_instance_valid(smoke_2) and not smoke_2.get("Override"):
		smoke_2.emitting = emitting

@rpc("any_peer", "call_local", "reliable")
func spawn_explosion() -> void:
	if EXPLOSION:
		var explosion := EXPLOSION.instantiate() as Node2D
		explosion.global_position = global_position
		get_tree().root.add_child(explosion)
