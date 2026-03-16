@tool
extends Node3D

@export_group("Setup")
@export var companion_scene: PackedScene
@export var api_url: String = "https://bitz.tools/api/farm-images/venn"
@export var target: Node3D

@export_subgroup("Debug")
@export_tool_button("Fetch & Spawn") var _spawn_button: Callable = fetch_and_spawn
@export_tool_button("Clear") var _clear_button: Callable = _clear_spawned

var _http: HTTPRequest
var _spawned: Array[BitzCompanion] = []

func _ensure_http() -> void:
	if is_instance_valid(_http):
		return
	_http = HTTPRequest.new()
	_http.name = "Http"
	add_child(_http)
	_http.request_completed.connect(_on_response)

func fetch_and_spawn():
	if companion_scene == null:
		push_error("[BitzFarmSpawner] companion_scene is not set")
		return
	_ensure_http()
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_http.cancel_request()
	print("[BitzFarmSpawner] Fetching %s" % api_url)
	var err = _http.request(api_url)
	if err != OK:
		push_error("[BitzFarmSpawner] Failed to start request: %d" % err)

func _on_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("[BitzFarmSpawner] Network error: %d" % result)
		return
	if response_code != 200:
		push_error("[BitzFarmSpawner] HTTP %d" % response_code)
		return

	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		push_error("[BitzFarmSpawner] JSON parse error")
		return

	var data: Dictionary = json.get_data()
	_clear_spawned()

	var total := 0
	for farm_name in data.keys():
		var entries: Array = data[farm_name]
		print("[BitzFarmSpawner] Farm '%s' — %d entries" % [farm_name, entries.size()])
		for entry in entries:
			var companion := companion_scene.instantiate() as BitzCompanion
			if companion == null:
				push_error("[BitzFarmSpawner] companion_scene is not a BitzCompanion")
				return
			companion.quest_id   = str(entry.get("quest_id",   ""))
			companion.species_id = int(entry.get("species_id", 0))
			companion.target     = target
			add_child(companion)
			_spawned.append(companion)
			total += 1
			print("[BitzFarmSpawner]   + %s / species %d  (%s)" % [
				companion.quest_id,
				companion.species_id,
				entry.get("common_name", "?")
			])

	print("[BitzFarmSpawner] Done — %d companions spawned across %d farms" % [total, data.size()])

func _clear_spawned():
	for c in _spawned:
		if is_instance_valid(c):
			c.queue_free()
	_spawned.clear()
	print("[BitzFarmSpawner] Cleared")
