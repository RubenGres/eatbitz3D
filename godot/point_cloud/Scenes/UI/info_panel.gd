@tool
extends Node3D

@onready var point_cloud_object = $PointCloudObject

@export var modal_url: String = "https://ruben-g-gres--grounded-sam2-api-segment.modal.run"

@export var quest_id: String = "":
	set(value):
		quest_id = value
		if quest_id != "" and species_id >= 0:
			_fetch()

@export var species_id: int = 0:
	set(value):
		species_id = value
		if quest_id != "" and species_id >= 0:
			_fetch()

var _api: BitzAPI
var _http_modal: HTTPRequest
var _pending_species_name: String = ""
var _pending_image: Image
var _got_name := false
var _got_image := false

func _ready():
	_api = BitzAPI.new()
	add_child(_api)
	_api.species_data_loaded.connect(_on_species_data)
	_api.image_loaded.connect(_on_image)

	_http_modal = HTTPRequest.new()
	add_child(_http_modal)
	_http_modal.request_completed.connect(_on_modal_received)

func _fetch():
	_got_name = false
	_got_image = false
	_pending_species_name = ""
	_pending_image = null
	_api.fetch_history(quest_id, species_id)
	_api.fetch_species_image(quest_id, species_id)

func _on_species_data(qid: String, sid: int, species_info: Dictionary):
	if qid != quest_id or sid != species_id:
		return
	_pending_species_name = species_info.get("name", "Unknown")
	_got_name = true
	_try_remove_bg()

func _on_image(qid: String, sid: int, texture: ImageTexture):
	if qid != quest_id or sid != species_id:
		return
	_pending_image = texture.get_image()
	_got_image = true
	_try_remove_bg()

func _try_remove_bg():
	if not _got_name or not _got_image:
		return
	_remove_bg(_pending_image, _pending_species_name)

func _remove_bg(image: Image, prompt: String):
	var buf = image.save_jpg_to_buffer(0.9)
	var base64_image = Marshalls.raw_to_base64(buf)
	var payload = JSON.stringify({
		"image_base64": base64_image,
		"prompt": prompt
	})
	print("Sending to Modal with prompt: ", prompt)
	_http_modal.request(modal_url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, payload)

func _on_modal_received(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	if response_code != 200:
		push_error("Modal request failed: %d" % response_code)
		return
	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		push_error("Failed to parse Modal response: %s" % json.get_error_message())
		return
	var data = json.data
	print("Modal found %d objects" % data.get("num_objects", 0))

	var masked_b64: String = data.get("masked_image_base64", "")
	if masked_b64.is_empty():
		push_error("No masked_image_base64 in Modal response")
		return

	var masked_bytes = Marshalls.base64_to_raw(masked_b64)
	var image = Image.new()
	var err = image.load_png_from_buffer(masked_bytes)
	if err != OK:
		err = image.load_jpg_from_buffer(masked_bytes)
	if err != OK:
		push_error("Failed to load masked image")
		return

	var texture = ImageTexture.create_from_image(image)
	point_cloud_object.texture = texture
	print("Applied masked texture (%dx%d)" % [image.get_width(), image.get_height()])
