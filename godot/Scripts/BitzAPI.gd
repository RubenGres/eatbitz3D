extends Node
class_name BitzAPI

var api_url: String = "https://api.bitz.tools"

signal image_loaded(quest_id: String, species_id: int, texture: ImageTexture)
signal species_data_loaded(quest_id: String, species_id: int, data: Dictionary)
signal request_failed(url: String, response_code: int)

var _pending_requests: Dictionary = {}
var _local_data: Dictionary = {}
var _local_data_loaded: bool = false

func fetch_species_image(quest_id: String, species_id: int, quality: String = "medium") -> void:
	var url = api_url + "/explore/images/" + quest_id + "/" + str(species_id) + "_image.jpg?res=" + quality
	var http = HTTPRequest.new()
	add_child(http)
	var key = "img_%s_%d" % [quest_id, species_id]
	_pending_requests[key] = {"quest_id": quest_id, "species_id": species_id, "node": http}
	http.request_completed.connect(_on_image_received.bind(key))
	http.request(url)

func fetch_history(quest_id: String, species_id: int) -> void:
	var local = _get_local_species(quest_id, species_id)
	if not local.is_empty():
		species_data_loaded.emit(quest_id, species_id, local)
	else:
		request_failed.emit(quest_id, 0)

func _on_image_received(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, key: String) -> void:
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
	image_loaded.emit(info.get("quest_id", ""), info.get("species_id", ""), texture)


func _load_local_data() -> void:
	if _local_data_loaded:
		return
	_local_data_loaded = true
	var file = FileAccess.open("res://data/species_data.json", FileAccess.READ)
	if not file:
		push_error("BitzAPI: local species_data.json not found")
		return
	var json = JSON.new()
	if json.parse(file.get_as_text()) == OK:
		_local_data = json.data
	else:
		push_error("BitzAPI: failed to parse local species_data.json")

func _get_local_species(quest_id: String, species_id: int) -> Dictionary:
	_load_local_data()
	var quest_data = _local_data.get(quest_id, {})
	return quest_data.get(str(species_id), {})

func _cleanup_request(key: String) -> void:
	if _pending_requests.has(key):
		var node = _pending_requests[key].get("node")
		if node and is_instance_valid(node):
			node.queue_free()
		_pending_requests.erase(key)

