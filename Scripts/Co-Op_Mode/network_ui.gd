extends Control

@onready var multiplayer_spawner: MultiplayerSpawner = $"../../MultiplayerSpawner"
@onready var server_code: Label = $ServerCode
@onready var input_code: LineEdit = $VBoxContainer2/InputCode

func _ready() -> void:
	# 1. Listen for room code generation (HOST ONLY event)
	NetworkHandler.room_code_generated.connect(_on_room_code_generated)
	
	# 2. Listen for multiplayer connection events (CLIENT events)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)

func _on_host_pressed() -> void:
	server_code.text = "Generating code..."
	NetworkHandler.start_server()
	
func _on_join_pressed() -> void:
	if not is_instance_valid(input_code):
		push_error("input_code node reference is missing or invalid!")
		return

	var code = input_code.text.strip_edges()
	print("Inputted Code Raw: '", input_code.text, "' | Cleaned: '", code, "'")
	
	if code.is_empty():
		push_warning("Join attempted with empty code.")
		return
		
	server_code.text = "Connecting to host..."
	NetworkHandler.join_via_room_code(code)

# --- HOST CALLBACK ---
func _on_room_code_generated(code: String) -> void:
	# ONLY the server should handle room code creation and initial host spawning
	if multiplayer.is_server():
		server_code.text = "ServerCode: " + code + " (local if same network)"
		multiplayer_spawner.spawn_host()
		

# --- CLIENT CALLBACKS ---
func _on_connected_to_server() -> void:
	print("Successfully connected to host!")

func _on_connection_failed() -> void:
	server_code.text = "Connection Failed! Check code/router."
	push_error("Could not connect to host server.")
	
func _on_input_code_focus_entered() -> void:
	# Pass the current text of the input line so the OS keyboard syncs correctly
	DisplayServer.virtual_keyboard_show(input_code.text)
				
