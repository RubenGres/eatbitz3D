@tool
extends Control

@export var api_url = "https://api.bitz.tools"
		
@export var quest_id = "":
	set(value):
		quest_id = value
		_on_field_updated()
		
@export var species_id: int = 0:
	set(value):
		species_id = value
		_on_field_updated()

var http_image: HTTPRequest
var http_json: HTTPRequest
var history_data: Array = []

func _ready():
	http_image = HTTPRequest.new()
	http_json = HTTPRequest.new()
	add_child(http_image)
	add_child(http_json)
	http_image.request_completed.connect(_on_image_received)
	http_json.request_completed.connect(_on_json_received)

func _on_field_updated():
	var image_url = api_url + "/explore/images/" + quest_id + "/" + str(species_id) + "_image.jpg?res=medium"
	var json_url = api_url + "/explore/data/" + quest_id + "/history.json"
	
	print(image_url)
	print(json_url)
	
	http_json.request(json_url)
	http_image.request(image_url)

func _fixup_string(assistant_data: String) -> Variant:
	var fixed = ""
	for i in assistant_data.length():
		var c = assistant_data[i]
		if c == "'":
			var prev_is_letter = i > 0 and assistant_data[i - 1].to_lower() != assistant_data[i - 1].to_upper()
			var next_is_letter = i < assistant_data.length() - 1 and assistant_data[i + 1].to_lower() != assistant_data[i + 1].to_upper()
			if prev_is_letter and next_is_letter:
				fixed += "'"
			else:
				fixed += "\""
		else:
			fixed += c
	var inner = JSON.new()
	var parse_err = inner.parse(fixed)
	if parse_err != OK:
		push_error("Failed to parse: %s" % inner.get_error_message())
		return null
	return inner.data

func _on_json_received(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	if response_code != 200:
		push_error("Failed to fetch JSON: %d" % response_code)
		return
	
	var json = JSON.new()
	var err = json.parse(body.get_string_from_utf8())
	if err != OK:
		push_error("Failed to parse JSON: %s" % json.get_error_message())
		return
	
	var data = json.data
	history_data = data.get("history", [])
	
	if species_id >= history_data.size():
		push_error("species_id %d out of range (history has %d entries)" % [species_id, history_data.size()])
		return
	
	var entry = history_data[species_id]
	var assistant_data = entry.get("assistant", {})
	
	assistant_data = _fixup_string(assistant_data)
	
	var species_info = assistant_data.get("species_identification", {})
	
	var species_name = species_info.get("name", "Unknown")
	var description = species_info.get("what_is_it", "")
	var additional_info = species_info.get("information", "")
	
	%SpeciesName.text = species_name
	%Description.text = description
	%AdditionalInfo.text = additional_info

func _on_image_received(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	if response_code != 200:
		push_error("Failed to fetch image: %d" % response_code)
		return
	
	var image = Image.new()
	var err = image.load_jpg_from_buffer(body)
	if err != OK:
		err = image.load_png_from_buffer(body)
	if err != OK:
		push_error("Failed to load image from buffer")
		return
	
	var texture = ImageTexture.create_from_image(image)
	%TextureRect.texture = texture
