class_name EnemyBase
extends CharacterBody2D

# --- Constants & Enums ---
const UNIT_SCALE: float = 100.0
const EXPLOSION: PackedScene = preload("res://Scenes/Effects/explosion.tscn")

enum State { IDLE, PATROL, CHASE, ATTACK, STUNNED, DEAD }
enum MovementState { NORMAL, ON_LEDGE, PHYSICS_OBJECT }

@export_group("Spawn Settings")
@export_enum("Right:1", "Left:-1") var initial_facing_direction: int = 1

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
@export var max_health: float = 200.0
@export var min_health: float = 100.0
@export var attack_damage: float = 15.0
@export var attack_cooldown_time: float = 1.0
@export var punch_windup_time: float = 0.5
@export var bounciness: float = 0.35
@export var physics_friction: float = 10.0
@export var hit_camera_shake: float = 0.35

@export_group("Death Impulse")
@export var death_launch_force: Vector2 = Vector2(5.0, -8.0)
@export var death_spin_speed: float = 12.0
@export var death_despawn_time: float = 2.0

@export_group("State")
@export var current_state: State = State.IDLE
@export var current_movement_state: MovementState = MovementState.NORMAL

# --- AI Input Targets (Synced) ---
var move_direction: float = 0.0
var wants_to_run: bool = false

# --- Runtime Variables ---
var health: float = 100
var current_speed: float = 1.4
var override_animations: bool = false
var modulate_tween: Tween
var death_angular_velocity: float = 0.0
var is_landing_settled: bool = false
var is_jumping_detour: bool = false
var can_punch: bool = true
var is_punching: bool = false

# --- Aggro System ---
var last_attacker: CharacterBody2D = null
var targets_in_sight: Array[CharacterBody2D] = []
var targets_in_punch_range: Array[CharacterBody2D] = []

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

@onready var sight: Area2D = $Sight
@onready var ray_cast_2d: RayCast2D = $RayCast2D

@onready var punch_hitbox: Area2D = $PunchHitbox
@onready var punch_range_area: Area2D = $PunchHitbox

@onready var stun_time: Timer = $StunTime


func _enter_tree() -> void:
	set_multiplayer_authority(1)

func _ready() -> void:
	_apply_initial_facing_direction()
	health = randf_range(min_health, max_health)
	
	if sprite and not sprite.animation_finished.is_connected(_on_sprite_animation_finished):
		sprite.animation_finished.connect(_on_sprite_animation_finished)
		
	if sight:
		if not sight.body_entered.is_connected(_on_sight_body_entered):
			sight.body_entered.connect(_on_sight_body_entered)
		if not sight.body_exited.is_connected(_on_sight_body_exited):
			sight.body_exited.connect(_on_sight_body_exited)

	if punch_range_area:
		if not punch_range_area.body_entered.is_connected(_on_punch_range_body_entered):
			punch_range_area.body_entered.connect(_on_punch_range_body_entered)
		if not punch_range_area.body_exited.is_connected(_on_punch_range_body_exited):
			punch_range_area.body_exited.connect(_on_punch_range_body_exited)

	if stun_time:
		if not stun_time.timeout.is_connected(_on_stun_timeout):
			stun_time.timeout.connect(_on_stun_timeout)

	if ray_cast_2d:
		ray_cast_2d.add_exception(self)

	if multiplayer.is_server():
		current_state = State.IDLE
		current_speed = walk_speed

		if navigation_agent_2d:
			if not navigation_agent_2d.link_reached.is_connected(_on_navigation_agent_2d_link_reached):
				navigation_agent_2d.link_reached.connect(_on_navigation_agent_2d_link_reached)
			
		_try_find_target()
		if not is_instance_valid(Target):
			get_tree().node_added.connect(_on_node_added)
			
		call_deferred("actor_setup")

func _apply_initial_facing_direction() -> void:
	var is_left: bool = (initial_facing_direction == -1)
	if sprite:
		sprite.flip_h = is_left
		
	var dir_sign: float = float(initial_facing_direction)
	if wall_check:
		wall_check.scale.x = dir_sign
	if ledge_check:
		ledge_check.scale.x = dir_sign
	if sight:
		sight.scale.x = dir_sign

func _update_facing_orientation(dir_x: float) -> void:
	if dir_x == 0.0:
		return
	var is_left: bool = (dir_x < 0.0)
	if sprite:
		sprite.flip_h = is_left
		
	var dir_sign: float = -1.0 if is_left else 1.0
	if wall_check:
		wall_check.scale.x = dir_sign
	if ledge_check:
		ledge_check.scale.x = dir_sign
	if sight:
		sight.scale.x = dir_sign

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
	if not multiplayer.is_server():
		update_animation()
		if move_direction != 0.0:
			_update_facing_orientation(move_direction)
		return

	if current_state == State.DEAD:
		_process_death_movement(delta)
		return

	_check_line_of_sight()
	_check_punch_range()

	match current_movement_state:
		MovementState.NORMAL:
			_process_normal_movement(delta)
		MovementState.ON_LEDGE:
			_process_ledge_movement()
		MovementState.PHYSICS_OBJECT:
			_process_physics_object_movement(delta)

# --- Perception & Vision System ---
func _on_sight_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D and body.is_in_group("Player"):
		if not targets_in_sight.has(body):
			targets_in_sight.append(body as CharacterBody2D)

func _on_sight_body_exited(body: Node2D) -> void:
	if body is CharacterBody2D and targets_in_sight.has(body):
		targets_in_sight.erase(body)

func _check_line_of_sight() -> void:
	if targets_in_sight.is_empty() or not ray_cast_2d:
		return

	targets_in_sight = targets_in_sight.filter(func(b): return is_instance_valid(b))

	for potential_target in targets_in_sight:
		ray_cast_2d.global_position = global_position
		ray_cast_2d.target_position = ray_cast_2d.to_local(potential_target.global_position)
		ray_cast_2d.force_raycast_update()

		if ray_cast_2d.is_colliding():
			var collider := ray_cast_2d.get_collider()
			if collider == potential_target:
				Target = potential_target
				if current_state != State.ATTACK and current_state != State.STUNNED:
					current_state = State.CHASE
				break

# --- Punch Detection & Attack Logic ---
func _on_punch_range_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D and body.is_in_group("Player"):
		if not targets_in_punch_range.has(body):
			targets_in_punch_range.append(body as CharacterBody2D)

func _on_punch_range_body_exited(body: Node2D) -> void:
	if body is CharacterBody2D and targets_in_punch_range.has(body):
		targets_in_punch_range.erase(body)

func _check_punch_range() -> void:
	if current_state == State.STUNNED or current_state == State.DEAD:
		return

	targets_in_punch_range = targets_in_punch_range.filter(func(b): return is_instance_valid(b))
	
	if not targets_in_punch_range.is_empty():
		Target = targets_in_punch_range[0]
		if can_punch and not is_punching:
			punch()
	elif current_state == State.ATTACK and not is_punching:
		current_state = State.CHASE if is_instance_valid(Target) else State.IDLE

func punch() -> void:
	if not can_punch or is_punching or current_state == State.STUNNED or current_state == State.DEAD:
		return

	can_punch = false
	is_punching = true
	current_state = State.ATTACK
	move_direction = 0.0

	# Turn to face target during wind-up
	if is_instance_valid(Target):
		var face_dir: float = Target.global_position.x - global_position.x
		_update_facing_orientation(face_dir)

	# --- 1. WIND-UP PHASE ---
	override_animations = true
	play_animation_once("Idle")
	await get_tree().create_timer(punch_windup_time).timeout

	if current_state == State.STUNNED or current_state == State.DEAD:
		_reset_attack_state()
		return

	# Re-face target before delivering punch
	if is_instance_valid(Target):
		var face_dir: float = Target.global_position.x - global_position.x
		_update_facing_orientation(face_dir)

	# --- 2. EXECUTE PUNCH ---
	play_animation_once("Punch1")
	punch_hitbox_activate(0.2)

	# --- 3. COOLDOWN PHASE ---
	await get_tree().create_timer(attack_cooldown_time).timeout
	_reset_attack_state()

func _reset_attack_state() -> void:
	can_punch = true
	is_punching = false
	if current_state == State.ATTACK:
		override_animations = false
		current_state = State.CHASE if is_instance_valid(Target) else State.IDLE

func punch_hitbox_activate(linger: float) -> void:
	if not is_instance_valid(punch_hitbox):
		return
		
	var hitbox: Area2D = punch_hitbox.duplicate()
	add_child(hitbox)
	
	var direction: float = -1.0 if (sprite and sprite.flip_h) else 1.0
	hitbox.scale.x = direction
	hitbox.area_entered.connect(_on_punch_hitbox_area_entered)
	hitbox.visible = true
	hitbox.monitorable = true
	hitbox.monitoring = true
	
	await get_tree().create_timer(linger).timeout
	if is_instance_valid(hitbox):
		hitbox.queue_free()

func _on_punch_hitbox_area_entered(area: Area2D) -> void:
	var parent_node := area.get_parent()
	if parent_node and parent_node.is_in_group("Player"):
		if parent_node.has_method("damage"):
			parent_node.damage(attack_damage, global_position, 1.0)
			_trigger_camera_shake(parent_node)

func _trigger_camera_shake(target_node: Node) -> void:
	if target_node and target_node.has_method("apply_shake"):
		target_node.apply_shake(hit_camera_shake)

# --- Movement Processing ---
func _process_normal_movement(delta: float) -> void:
	set_smoke_emitting(false)
	
	if current_state == State.ATTACK or current_state == State.STUNNED:
		move_direction = 0.0
	else:
		_process_ai_navigation()
	
	if current_state != State.ATTACK:
		if move_direction != 0.0:
			_update_facing_orientation(move_direction)
		elif is_instance_valid(Target) and current_state == State.CHASE:
			var target_dir: float = Target.global_position.x - global_position.x
			_update_facing_orientation(target_dir)

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

	move_and_slide()
	update_animation()

# --- AI Navigation Processing ---
func _process_ai_navigation() -> void:
	if not is_instance_valid(navigation_agent_2d):
		return

	if current_state != State.CHASE:
		move_direction = 0.0
		return

	if not is_instance_valid(Target):
		_try_find_target()
		if not is_instance_valid(Target):
			move_direction = 0.0
			return

	if is_jumping_detour:
		if is_on_floor() and velocity.y >= 0:
			is_jumping_detour = false
		else:
			return

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
	if is_on_floor() and current_movement_state == MovementState.NORMAL and current_state != State.DEAD and current_state != State.STUNNED:
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

# --- Stun Logic ---
func apply_stun() -> void:
	if current_state == State.DEAD:
		return

	is_punching = false
	can_punch = true

	current_state = State.STUNNED
	move_direction = 0.0
	override_animations = true
	
	var hurt_anim := "Hurt" if (sprite and sprite.sprite_frames.has_animation("Hurt")) else "Fall"
	play_animation_once(hurt_anim)

	if stun_time:
		stun_time.start()

func _on_stun_timeout() -> void:
	if current_state == State.STUNNED:
		override_animations = false
		is_punching = false
		can_punch = true
		current_state = State.CHASE if is_instance_valid(Target) else State.IDLE

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
		_sync_die.rpc(origin)
	else:
		apply_stun()
		if origin != Vector2.ZERO:
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

@rpc("authority", "call_local", "reliable")
func _sync_die(origin: Vector2 = Vector2.ZERO) -> void:
	die(origin)

func die(origin: Vector2 = Vector2.ZERO) -> void:
	current_state = State.DEAD
	override_animations = true
	
	set_collision_mask_value(2, false)
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
		"Hurt", "LedgeGrab", "Dash", "Punch1":
			if current_movement_state == MovementState.NORMAL and current_state != State.STUNNED:
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
