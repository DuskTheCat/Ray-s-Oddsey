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
	
	var spawn_node = get_node(spawn_path)
	if spawn_node.has_node(str(id)):
		return

	# Calling spawn() forces MultiplayerSpawner to instantiate AND replicate to clients
	spawn({"id": id})

func remove_player(id: int) -> void:
	if not multiplayer.is_server(): 
		return
		
	var spawn_node = get_node(spawn_path)
	if spawn_node.has_node(str(id)):
		spawn_node.get_node(str(id)).queue_free()
