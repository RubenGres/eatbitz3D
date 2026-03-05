@tool
extends Node3D
class_name BitzCompanion

@onready var point_cloud_object = $ParticlesTest

@export var rembg_base_url: String = "/rembg"

@export var quest_id: String = "":
	set(value):
		quest_id = value
		if is_node_ready():
			if quest_id != "" and species_id >= 0:
				_fetch()

@export var species_id: int = 0:
	set(value):
		species_id = value
		if is_node_ready():
			if quest_id != "" and species_id >= 0:
				_fetch()

@export var target: Node3D:
	set(value):
		target = value
		if is_node_ready():
			point_cloud_object.target = self.target

@export var is_highlighted: bool = false:
	set(value):
		is_highlighted = value
		if is_node_ready():
			_set_highlighted()

var _http_rembg: HTTPRequest

func _ready():
	print("[PointCloud] _ready - quest_id: %s, species_id: %d" % [quest_id, species_id])
	_http_rembg = HTTPRequest.new()
	add_child(_http_rembg)
	_http_rembg.request_completed.connect(_on_rembg_received)
	
	point_cloud_object.target = self.target

	# hide while not loaded
	self.hide()

	_fetch()

func _fetch():
	print("[PointCloud] _fetch - quest_id: %s, species_id: %d" % [quest_id, species_id])
	if quest_id == "" or species_id < 0:
		return
	if _http_rembg.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_http_rembg.cancel_request()

	var url = "%s/%s/%d" % [_normalized_base_url(), quest_id, species_id]
	print("[PointCloud] Requesting rembg image from %s" % url)
	var err = _http_rembg.request(url)
	if err != OK:
		push_error("[PointCloud] Failed to start rembg request: %d" % err)

func _set_highlighted():
	$ParticlesTest/HighlightSprite.visible = is_highlighted

func _on_rembg_received(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
	print("[PointCloud] _on_rembg_received - result: %d, response_code: %d, body size: %d bytes" % [result, response_code, body.size()])
	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("[PointCloud] rembg network error: %d" % result)
		return
	if response_code != 200:
		push_error("[PointCloud] rembg request failed: %d" % response_code)
		print("[PointCloud] Response body: %s" % body.get_string_from_utf8().substr(0, 500))
		return

	var image = Image.new()
	var err = image.load_png_from_buffer(body)
	if err != OK:
		push_error("[PointCloud] Failed to load PNG image from rembg response")
		return

	var texture = ImageTexture.create_from_image(image)
	point_cloud_object.texture = texture
	print("[PointCloud] Applied masked texture (%dx%d) to point_cloud_object" % [image.get_width(), image.get_height()])
	
	# show node back
	self.show()

func _normalized_base_url() -> String:
	if rembg_base_url.ends_with("/"):
		return rembg_base_url.substr(0, rembg_base_url.length() - 1)
	return rembg_base_url
