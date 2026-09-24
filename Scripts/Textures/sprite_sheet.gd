extends AnimatedSprite2D

@export_file("*.json") var json_path: String
@export var texture_atlas: Texture2D
@export var fps: int = 10

func _ready() -> void:
	if json_path.is_empty() or not texture_atlas:
		printerr("Please assign both the JSON path and Texture Atlas in the Inspector!")
		return
		
	# Call the static generator function
	var new_sprite_frames = parse_spritesheet_json(json_path, texture_atlas, fps)
	if not new_sprite_frames:
		return
		
	self.sprite_frames = new_sprite_frames
	
	var anim_names = new_sprite_frames.get_animation_names()
	if anim_names.size() > 0:
		var default_anim = "idle" if new_sprite_frames.has_animation("idle") else anim_names[0]
		self.play(default_anim)


# --- STATIC UTILITY FUNCTIONS ---

## Parses a Aseprite/TexturePacker JSON file and returns a ready-to-use SpriteFrames object.
static func parse_spritesheet_json(path: String, atlas: Texture2D, custom_fps: int = 10) -> SpriteFrames:
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
		var full_filename = frame_data["filename"]
		var anim_name = _extract_animation_name(full_filename)
		var frame_index = _extract_frame_index(full_filename)
		
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
			
		new_sprite_frames.set_animation_loop(anim_name, true)
		if custom_fps > 0:
			new_sprite_frames.set_animation_speed(anim_name, custom_fps)
			
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
