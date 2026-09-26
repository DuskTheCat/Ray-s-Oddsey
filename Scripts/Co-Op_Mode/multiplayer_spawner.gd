extends MultiplayerSpawner

@export var network_player: PackedScene
@export var Spawn_Node: Node2D

func _ready() -> void:
	# Set Godot's custom spawn function for this spawner
	spawn_function = _custom_spawn
	
	if not multiplayer.is_server(): 
		return
		
	multiplayer.peer_connected.connect(spawn_player)
	multiplayer.peer_disconnected.connect(remove_player)

# Custom spawn method used internally by Godot's MultiplayerSpawner
func _custom_spawn(data: Dictionary) -> Node:
	var player = network_player.instantiate()
	
	# Fallback to local position if Spawn_Node isn't set
	if Spawn_Node:
		player.global_position = Spawn_Node.global_position
		
	player.name = str(data["id"])
	return player
	
# Public function to trigger host spawn manually
func spawn_host() -> void:
	if multiplayer.is_server():
		spawn_player(1)

func spawn_player(id: int) -> void:
	if not multiplayer.is_server(): 
		return
	
	var parent_node = get_node_or_null(spawn_path)
	if not parent_node or parent_node.has_node(str(id)):
		return

	# Calling spawn() forces MultiplayerSpawner to instantiate AND replicate to clients
	spawn({"id": id})

func remove_player(id: int) -> void:
	if not multiplayer.is_server(): 
		return
		
	var parent_node = get_node_or_null(spawn_path)
	if parent_node and parent_node.has_node(str(id)):
		var player_node = parent_node.get_node(str(id))
		player_node.queue_free()

# Handle local quit gracefully for the host or local peer
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# If the local player closes the window while acting as server,
		# clean up all connected players before exiting
		if multiplayer.is_server():
			for peer_id in multiplayer.get_peers():
				remove_player(peer_id)
			remove_player(1) # Remove host
