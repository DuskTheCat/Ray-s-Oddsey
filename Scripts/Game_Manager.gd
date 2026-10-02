extends Node2D # Or Node3D depending on your game

@export var player_scene: PackedScene

func _ready() -> void:
	# Check if we are running in multiplayer mode
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		# Multiplayer: Server listens for connected peers and spawns them
		multiplayer.peer_connected.connect(spawn_player)
		multiplayer.peer_disconnected.connect(remove_player)
		
		# Spawn the host/server player
		spawn_player(multiplayer.get_unique_id())
	elif not multiplayer.has_multiplayer_peer():
		# Single-player fallback: Just spawn one local player
		spawn_player(1) 

func spawn_player(id: int) -> void:
	var player = player_scene.instantiate()
	player.name = str(id) # Name must match the peer ID for MultiplayerSpawner to work
	add_child(player)
	
	# Optional: Set spawn positions based on ID
	# player.global_position = get_node("SpawnPoint").global_position

func remove_player(id: int) -> void:
	if has_node(str(id)):
		get_node(str(id)).queue_free()
