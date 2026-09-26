extends Node

# Declare the signal so UI scripts can listen for it
signal room_code_generated(code: String)

const IP_ADDRESS: String = "127.0.0.1"
const PORT: int = 42069

var peer: ENetMultiplayerPeer
var http_request: HTTPRequest

func _ready() -> void:
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_ip_fetched)

# --- SERVER / HOST ---

func start_server(port: int = PORT) -> void:
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port)
	if error != OK:
		push_error("Failed to start server: ", error)
		return
	multiplayer.multiplayer_peer = peer
	
	fetch_public_ip()

func fetch_public_ip() -> void:
	var error = http_request.request("https://api.ipify.org")
	if error != OK:
		push_error("Failed to initiate IP lookup request.")

func _on_ip_fetched(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var room_code: String = ""
	
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var public_ip = body.get_string_from_utf8().strip_edges()
		room_code = ip_to_code(public_ip)
	else:
		# Fallback to local network code if internet lookup fails
		room_code = ip_to_code(IP_ADDRESS)
	
	# Send the room code to any UI script listening!
	room_code_generated.emit(room_code)

# --- CLIENT ---

func start_client(ip: String = IP_ADDRESS, port: int = PORT) -> void:
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, port)
	if error != OK:
		push_error("Failed to connect to server: ", error)
		return
	multiplayer.multiplayer_peer = peer

func join_via_room_code(code: String, port: int = PORT) -> void:
	var clean_code = code.strip_edges()
	
	# LOCALHOST SHORTCUT FOR TESTING ON 1 PC
	if clean_code.to_lower() == "local" or clean_code == "127.0.0.1":
		print("Connecting via Localhost fallback...")
		start_client("127.0.0.1", port)
		return

	if clean_code.is_empty() or clean_code.length() != 8:
		push_warning("Join ignored: Code must be 8 hex characters or 'local'.")
		return

	var target_ip = code_to_ip(clean_code)
	if target_ip == "":
		push_warning("Join ignored: Invalid room code.")
		return
		
	start_client(target_ip, port)

# --- ENCODER / DECODER ---

func ip_to_code(ip: String) -> String:
	var parts = ip.split(".")
	if parts.size() != 4:
		return ""
	var hex_str = ""
	for part in parts:
		hex_str += "%02X" % part.to_int()
	return hex_str

func code_to_ip(code: String) -> String:
	var clean_code = code.strip_edges().to_upper()
	
	# Check length
	if clean_code.length() != 8:
		return ""
		
	# Verify that all characters are valid hex digits (0-9, A-F)
	if not clean_code.is_valid_hex_number():
		return ""

	var ip_parts: Array[String] = []
	for i in range(0, 8, 2):
		var hex_byte = clean_code.substr(i, 2)
		var val = hex_byte.hex_to_int()
		ip_parts.append(str(val))
		
	return ".".join(ip_parts)
