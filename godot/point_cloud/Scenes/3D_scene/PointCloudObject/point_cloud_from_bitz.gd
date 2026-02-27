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
	print("[PointCloud] _ready - quest_id: %s, species_id: %d" % [quest_id, species_id])
	_api = BitzAPI.new()
	add_child(_api)
	_api.species_data_loaded.connect(_on_species_data)
	_api.image_loaded.connect(_on_image)
	_api.request_failed.connect(func(url, code): print("[PointCloud] BitzAPI request failed - url: %s, code: %d" % [url, code]))

	_http_modal = HTTPRequest.new()
	add_child(_http_modal)
	_http_modal.request_completed.connect(_on_modal_received)

func _fetch():
	print("[PointCloud] _fetch - quest_id: %s, species_id: %d" % [quest_id, species_id])
	_got_name = false
	_got_image = false
	_pending_species_name = ""
	_pending_image = null
	_api.fetch_history(quest_id, species_id)
	_api.fetch_species_image(quest_id, species_id)

func _on_species_data(qid: String, sid: int, species_info: Dictionary):
	print("[PointCloud] _on_species_data - qid: %s, sid: %d, info: %s" % [qid, sid, species_info])
	if qid != quest_id or sid != species_id:
		print("[PointCloud] Ignoring stale species data (expected %s/%d)" % [quest_id, species_id])
		return
	_pending_species_name = species_info.get("name", "Unknown")
	_got_name = true
	print("[PointCloud] Got species name: %s" % _pending_species_name)
	_try_remove_bg()

func _on_image(qid: String, sid: int, texture: ImageTexture):
	print("[PointCloud] _on_image - qid: %s, sid: %d, texture size: %dx%d" % [qid, sid, texture.get_width(), texture.get_height()])
	if qid != quest_id or sid != species_id:
		print("[PointCloud] Ignoring stale image (expected %s/%d)" % [quest_id, species_id])
		return
	_pending_image = texture.get_image()
	_got_image = true
	print("[PointCloud] Got image: %dx%d" % [_pending_image.get_width(), _pending_image.get_height()])
	_try_remove_bg()

func _try_remove_bg():
	print("[PointCloud] _try_remove_bg - got_name: %s, got_image: %s" % [_got_name, _got_image])
	if not _got_name or not _got_image:
		return
	print("[PointCloud] Both ready, sending to Modal...")
	_remove_bg(_pending_image, _pending_species_name)

func _remove_bg(image: Image, prompt: String):
	var buf = image.save_jpg_to_buffer(0.9)
	var base64_image = Marshalls.raw_to_base64(buf)
	print("[PointCloud] _remove_bg - prompt: '%s', image: %dx%d, base64 length: %d" % [prompt, image.get_width(), image.get_height(), base64_image.length()])
	var payload = JSON.stringify({
		"image_base64": base64_image,
		"prompt": prompt
	})
	print("[PointCloud] Sending POST to %s (payload size: %d bytes)" % [modal_url, payload.length()])
	_http_modal.request(modal_url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, payload)

func _on_modal_received(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	print("[PointCloud] _on_modal_received - result: %d, response_code: %d, body size: %d bytes" % [result, response_code, body.size()])
	if response_code != 200:
		push_error("[PointCloud] Modal request failed: %d" % response_code)
		print("[PointCloud] Response body: %s" % body.get_string_from_utf8().substr(0, 500))
		return
	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		push_error("[PointCloud] Failed to parse Modal response: %s" % json.get_error_message())
		return
	var data = json.data
	var num_objects: int = data.get("num_objects", 0)
	var scores: Array = data.get("scores", [])
	var labels: Array = data.get("labels", [])
	print("[PointCloud] Modal results - objects: %d, labels: %s, scores: %s" % [num_objects, labels, scores])

	var masked_b64: String = data.get("masked_image_base64", "")
	if masked_b64.is_empty():
		push_error("[PointCloud] No masked_image_base64 in Modal response")
		print("[PointCloud] Response keys: %s" % str(data.keys()))
		return

	print("[PointCloud] Decoding masked image (base64 length: %d)" % masked_b64.length())
	var masked_bytes = Marshalls.base64_to_raw(masked_b64)
	var image = Image.new()
	var err = image.load_png_from_buffer(masked_bytes)
	if err != OK:
		print("[PointCloud] PNG decode failed, trying JPG...")
		err = image.load_jpg_from_buffer(masked_bytes)
	if err != OK:
		push_error("[PointCloud] Failed to load masked image from buffer")
		return

	var texture = ImageTexture.create_from_image(image)
	point_cloud_object.texture = texture
	print("[PointCloud] Applied masked texture (%dx%d) to point_cloud_object" % [image.get_width(), image.get_height()])
