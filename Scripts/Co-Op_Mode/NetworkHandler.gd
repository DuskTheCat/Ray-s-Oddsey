extends Node

# Signal emitted when a valid room code is generated
signal room_code_generated(code: String)

const DEFAULT_PORT: int = 42069
const DEFAULT_IP: String = "127.0.0.1"

var peer: ENetMultiplayerPeer
var upnp: UPNP
var active_port: int = 0

# Clean up UPnP mappings when the node is destroyed or game exits
func _exit_tree() -> void:
	_cleanup_upnp()

# --- SERVER / HOST ---

func start_server(port: int = DEFAULT_PORT) -> void:
	# Reset existing connections if any
	exit_server()
	
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_server(port)
	if error != OK:
		push_error("Failed to start server: %s" % error)
		return
		
	multiplayer.multiplayer_peer = peer
	active_port = port
	
	# Setup UPnP Port Forwarding & obtain external IP
	_setup_upnp_and_emit_code(port)


func _setup_upnp_and_emit_code(port: int) -> void:
	upnp = UPNP.new()
	var discover_result := upnp.discover()
	
	var public_ip := DEFAULT_IP
	
	if discover_result == UPNP.UPNP_RESULT_SUCCESS and upnp.get_gateway() and upnp.get_gateway().is_valid_gateway():
		# Try mapping with description first, fallback to empty description if router rejects it
		var map_udp := upnp.add_port_mapping(port, port, "Godot Game", "UDP")
		if map_udp != UPNP.UPNP_RESULT_SUCCESS:
			map_udp = upnp.add_port_mapping(port, port, "", "UDP")
			
		if map_udp != UPNP.UPNP_RESULT_SUCCESS:
			push_warning("UPnP UDP Port Mapping failed with error code: %d" % map_udp)
			
		var external_ip := upnp.query_external_address()
		if not external_ip.is_empty():
			public_ip = external_ip
	else:
		push_warning("UPnP Discovery failed or gateway invalid (Error: %d). Localhost assigned." % discover_result)

	var room_code := ip_to_code(public_ip)
	room_code_generated.emit(room_code)


func exit_server() -> void:
	_cleanup_upnp()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	peer = null


func _cleanup_upnp() -> void:
	if upnp and active_port > 0:
		upnp.delete_port_mapping(active_port, "UDP")
		upnp = null
		active_port = 0

# --- CLIENT ---

func start_client(ip: String = DEFAULT_IP, port: int = DEFAULT_PORT) -> void:
	exit_server()
	
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_client(ip, port)
	if error != OK:
		push_error("Failed to connect to server: %s" % error)
		return
		
	multiplayer.multiplayer_peer = peer


func join_via_room_code(code: String, port: int = DEFAULT_PORT) -> void:
	var clean_code := code.strip_edges()

	# Localhost override for local testing
	if clean_code.to_lower() == "local" or clean_code == DEFAULT_IP:
		start_client(DEFAULT_IP, port)
		return

	if clean_code.is_empty() or clean_code.length() != 8:
		push_warning("Join failed: Code must be an 8-character hex string or 'local'.")
		return

	var target_ip := code_to_ip(clean_code)
	if target_ip.is_empty():
		push_warning("Join failed: Invalid hex room code format.")
		return

	start_client(target_ip, port)

# --- ENCODER / DECODER ---

func ip_to_code(ip: String) -> String:
	var parts := ip.split(".")
	if parts.size() != 4:
		return ""
		
	var hex_code := ""
	for part in parts:
		hex_code += "%02X" % part.to_int()
	return hex_code


func code_to_ip(code: String) -> String:
	var clean_code := code.strip_edges().to_upper()
	if clean_code.length() != 8 or not clean_code.is_valid_hex_number():
		return ""

	var ip_parts: Array[String] = []
	for i in range(0, 8, 2):
		var hex_byte := clean_code.substr(i, 2)
		ip_parts.append(str(hex_byte.hex_to_int()))

	return ".".join(ip_parts)
