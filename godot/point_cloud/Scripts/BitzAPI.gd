extends Node
class_name BitzAPI

var api_url: String = "https://api.bitz.tools"

signal image_loaded(quest_id: String, species_id: int, texture: ImageTexture)
signal species_data_loaded(quest_id: String, species_id: int, data: Dictionary)
signal request_failed(url: String, response_code: int)

var _pending_requests: Dictionary = {}

func fetch_species_image(quest_id: String, species_id: int, quality: String = "thumb") -> void:
	var url = api_url + "/explore/images/" + quest_id + "/" + str(species_id) + "_image.jpg?res=medium"
	var http = HTTPRequest.new()
	add_child(http)
	var key = "img_%s_%d" % [quest_id, species_id]
	_pending_requests[key] = {"quest_id": quest_id, "species_id": species_id, "node": http}
	http.request_completed.connect(_on_image_received.bind(key))
	http.request(url)

func fetch_history(quest_id: String, species_id: int) -> void:
	var url = api_url + "/explore/data/" + quest_id + "/history.json"
	var http = HTTPRequest.new()
	add_child(http)
	var key = "json_%s_%d" % [quest_id, species_id]
	_pending_requests[key] = {"quest_id": quest_id, "species_id": species_id, "node": http}
	http.request_completed.connect(_on_json_received.bind(key))
	http.request(url)

func _on_image_received(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, key: String) -> void:
	var info = _pending_requests.get(key, {})
	_cleanup_request(key)
	if response_code != 200:
		request_failed.emit(api_url + ":" + info.get("quest_id", ""), response_code)
		return
	var image = Image.new()
	var err = image.load_jpg_from_buffer(body)
	if err != OK:
		err = image.load_png_from_buffer(body)
	if err != OK:
		push_error("BitzAPI: Failed to load image from buffer")
		return
	var texture = ImageTexture.create_from_image(image)
	image_loaded.emit(info.quest_id, info.species_id, texture)

func _on_json_received(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, key: String) -> void:
	var info = _pending_requests.get(key, {})
	_cleanup_request(key)
	if response_code != 200:
		request_failed.emit(info.get("quest_id", ""), response_code)
		return
	var json = JSON.new()
	var err = json.parse(body.get_string_from_utf8())
	if err != OK:
		push_error("BitzAPI: Failed to parse JSON: %s" % json.get_error_message())
		return
	var history: Array = json.data.get("history", [])
	var sid: int = info.species_id
	if sid >= history.size():
		push_error("BitzAPI: species_id %d out of range (%d entries)" % [sid, history.size()])
		return
	var entry = history[sid]
	var assistant_raw = entry.get("assistant", "{}")
	var parsed = _fixup_string(assistant_raw)
	if parsed == null:
		parsed = {}
	var species_info = parsed.get("species_identification", {})
	species_data_loaded.emit(info.quest_id, info.species_id, species_info)

func _cleanup_request(key: String) -> void:
	if _pending_requests.has(key):
		var node = _pending_requests[key].get("node")
		if node and is_instance_valid(node):
			node.queue_free()
		_pending_requests.erase(key)

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
		push_error("BitzAPI: Failed to parse fixup string: %s" % inner.get_error_message())
		return null
	return inner.data
