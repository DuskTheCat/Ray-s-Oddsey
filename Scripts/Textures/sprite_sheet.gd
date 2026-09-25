@tool
class_name JSONSpriteSheetAnimator
extends AnimatedSprite2D

@export_file("*.json") var json_path: String:
	set(value):
		if json_path != value:
			json_path = value
			_reload_animations_from_json()

@export var texture_atlas: Texture2D:
	set(value):
		if texture_atlas != value:
			texture_atlas = value
			if Engine.is_editor_hint() and not json_path.is_empty():
				_reload_animations_from_json()

@export var default_fps: int = 10:
	set(value):
		default_fps = value
		if Engine.is_editor_hint() and not json_path.is_empty():
			_reload_animations_from_json()

# Stores dynamically populated property values: { "idle_loop": true, "idle_fps": 8.0 }
var _dynamic_properties: Dictionary = {}
var _detected_animations: Array[String] = []


func _ready() -> void:
	if json_path.is_empty() or not texture_atlas:
		if not Engine.is_editor_hint():
			printerr("Please assign both the JSON path and Texture Atlas in the Inspector!")
		return
		
	var new_sprite_frames = parse_spritesheet_json(json_path, texture_atlas, default_fps, _dynamic_properties)
	if not new_sprite_frames:
		return
		
	self.sprite_frames = new_sprite_frames
	
	if not Engine.is_editor_hint():
		var anim_names = new_sprite_frames.get_animation_names()
		if anim_names.size() > 0:
			var default_anim = anim_names[0]
			for anim in anim_names:
				if anim.to_lower() == "idle":
					default_anim = anim
					break
			self.play(default_anim)


# --- DYNAMIC PROPERTY INJECTION ---

func _reload_animations_from_json() -> void:
	_detected_animations.clear()
	if json_path.is_empty() or not FileAccess.file_exists(json_path):
		notify_property_list_changed()
		return

	var file = FileAccess.open(json_path, FileAccess.READ)
	if not file:
		notify_property_list_changed()
		return

	var json = JSON.new()
	if json.parse(file.get_as_text()) == OK:
		var data = json.get_data()
		if data is Dictionary and data.has("frames"):
			for frame_data in data["frames"]:
				var clean_filename = frame_data["filename"].get_file()
				var anim_name = _extract_animation_name(clean_filename)
				if not _detected_animations.has(anim_name):
					_detected_animations.append(anim_name)
					
					# Set initial default values if they don't exist yet
					var loop_key = anim_name.to_lower() + "_loop"
					var fps_key = anim_name.to_lower() + "_fps"
					if not _dynamic_properties.has(loop_key):
						_dynamic_properties[loop_key] = true
					if not _dynamic_properties.has(fps_key):
						_dynamic_properties[fps_key] = float(default_fps)

	notify_property_list_changed()


func _get_property_list() -> Array[Dictionary]:
	var properties: Array[Dictionary] = []
	
	if _detected_animations.is_empty() and not json_path.is_empty():
		_reload_animations_from_json()

	for anim_name in _detected_animations:
		var prefix = anim_name.to_lower()
		
		# Add a category header in the Inspector for each detected animation
		properties.append({
			"name": anim_name + " Animation",
			"type": TYPE_NIL,
			"usage": PROPERTY_USAGE_GROUP
		})
		
		properties.append({
			"name": prefix + "_loop",
			"type": TYPE_BOOL,
			"usage": PROPERTY_USAGE_DEFAULT
		})
		
		properties.append({
			"name": prefix + "_fps",
			"type": TYPE_FLOAT,
			"usage": PROPERTY_USAGE_DEFAULT,
			"hint": PROPERTY_HINT_RANGE,
			"hint_string": "0,120,0.1"
		})

	return properties


func _get(property: StringName):
	if _dynamic_properties.has(property):
		return _dynamic_properties[property]
	return null


func _set(property: StringName, value) -> bool:
	if property.ends_with("_loop") or property.ends_with("_fps"):
		_dynamic_properties[property] = value
		if Engine.is_editor_hint() and texture_atlas and not json_path.is_empty():
			_ready()
		return true
	return false


# --- STATIC UTILITY FUNCTIONS ---

static func parse_spritesheet_json(path: String, atlas: Texture2D, custom_fps: int = 10, dynamic_props: Dictionary = {}) -> SpriteFrames:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		printerr("Failed to open JSON file: ", path)
		return null
		
	var json_text = file.get_as_text()
	var json = JSON.new()
	if json.parse(json_text) != OK:
		printerr("Failed to parse JSON text in file: ", path)
		return null
		
	var data = json.get_data()
	if not data.has("frames"):
		return null

	var new_sprite_frames = SpriteFrames.new()
	new_sprite_frames.remove_animation("default")
	
	var animation_groups = {}
	
	for frame_data in data["frames"]:
		var clean_filename = frame_data["filename"].get_file()
		var anim_name = _extract_animation_name(clean_filename)
		var frame_index = _extract_frame_index(clean_filename)
		
		var frame_rect = frame_data["frame"]
		var source_size = frame_data["sourceSize"]
		var sprite_source_size = frame_data["spriteSourceSize"]
		
		var atlas_tex = AtlasTexture.new()
		atlas_tex.atlas = atlas
		atlas_tex.region = Rect2(frame_rect["x"], frame_rect["y"], frame_rect["w"], frame_rect["h"])
		atlas_tex.margin = Rect2(
			sprite_source_size["x"], 
			sprite_source_size["y"], 
			source_size["w"] - frame_rect["w"], 
			source_size["h"] - frame_rect["h"]
		)
		
		if not animation_groups.has(anim_name):
			animation_groups[anim_name] = []
			
		animation_groups[anim_name].append({
			"index": frame_index,
			"texture": atlas_tex
		})
	
	for anim_name in animation_groups.keys():
		new_sprite_frames.add_animation(anim_name)
		
		var frame_list = animation_groups[anim_name]
		frame_list.sort_custom(func(a, b): return a["index"] < b["index"])
		
		for frame_item in frame_list:
			new_sprite_frames.add_frame(anim_name, frame_item["texture"])
		
		# Look up dynamic property overrides (e.g., "idle_loop", "idle_fps")
		var prefix = anim_name.to_lower()
		var anim_loop = dynamic_props.get(prefix + "_loop", true)
		var anim_fps = dynamic_props.get(prefix + "_fps", float(custom_fps))
		
		new_sprite_frames.set_animation_loop(anim_name, anim_loop)
		if anim_fps > 0:
			new_sprite_frames.set_animation_speed(anim_name, anim_fps)
			
	return new_sprite_frames


static func _extract_animation_name(filename: String) -> String:
	var base_name = filename.get_basename()
	var last_underscore = base_name.rfind("_")
	if last_underscore != -1:
		return base_name.left(last_underscore)
	return base_name


static func _extract_frame_index(filename: String) -> int:
	var base_name = filename.get_basename()
	var last_underscore = base_name.rfind("_")
	if last_underscore != -1:
		var num_str = base_name.substr(last_underscore + 1)
		if num_str.is_valid_int():
			return num_str.to_int()
	return 0
