@tool
extends Node3D
class_name BitzFarmSpawner

@export_group("Setup")
@export var companion_scene: PackedScene  # Assign your BitzCompanion.tscn here
@export var api_url: String = "https://bitz.tools/api/farm-images/venn"
@export var target: Node3D
@export var spawn_interval: float = 0.1  # seconds between each spawn (increased for runtime safety)

@export_subgroup("Debug")
@export_tool_button("Fetch & Spawn") var _spawn_button: Callable = fetch_and_spawn
@export_tool_button("Clear") var _clear_button: Callable = _clear_spawned

var _http: HTTPRequest
var _spawned: Array[BitzCompanion] = []
var _pending_free: Array[BitzCompanion] = []  # old companions waiting to be freed
var _spawn_queue: Array[Dictionary] = []
var _spawn_timer: float = 0.0
var _is_spawning: bool = false
var _free_timer: float = 0.0
const FREE_DELAY: float = 0.5  # seconds before freeing old companions

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready():
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_response)

	if not Engine.is_editor_hint():
		fetch_and_spawn()

func _process(delta: float) -> void:
	# Drain deferred-free queue after a short delay
	if not _pending_free.is_empty():
		_free_timer -= delta
		if _free_timer <= 0.0:
			for c in _pending_free:
				if is_instance_valid(c):
					c.queue_free()
			_pending_free.clear()

	# Drain spawn queue
	if _spawn_queue.is_empty():
		_is_spawning = false
		return

	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return

	_spawn_timer = spawn_interval
	var entry_data: Dictionary = _spawn_queue.pop_front()
	_spawn_one(entry_data)

# ── API ───────────────────────────────────────────────────────────────────────

func fetch_and_spawn():
	if companion_scene == null:
		push_error("[BitzFarmSpawner] companion_scene is not set — assign a PackedScene (.tscn)")
		return
	if _http == null:
		_http = HTTPRequest.new()
		add_child(_http)
		_http.request_completed.connect(_on_response)
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
	var parse_err = json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		push_error("[BitzFarmSpawner] JSON parse error")
		return

	var data: Dictionary = json.get_data()

	# Move current companions to pending-free list instead of freeing immediately.
	# They'll be freed after FREE_DELAY seconds, avoiding a spike on the same frame
	# that the first new companions start spawning.
	for c in _spawned:
		if is_instance_valid(c):
			_pending_free.append(c)
	_spawned.clear()
	_free_timer = FREE_DELAY

	_spawn_queue.clear()

	var seen: Dictionary = {}  # "quest_id:species_id" → true
	for farm_name in data.keys():
		var entries: Array = data[farm_name]
		for entry in entries:
			var qid := str(entry.get("quest_id", ""))
			var sid := int(entry.get("species_id", 0))
			var key := "%s:%d" % [qid, sid]
			if seen.has(key):
				print("[BitzFarmSpawner] Skipping duplicate %s" % key)
				continue
			seen[key] = true
			_spawn_queue.append({
				"quest_id":    qid,
				"species_id":  sid,
				"common_name": entry.get("common_name", "?"),
				"farm_name":   farm_name,
			})

	print("[BitzFarmSpawner] Queued %d companions (%d deduped) across %d farms" % [
		_spawn_queue.size(), data.size(), data.keys().size()
	])
	_is_spawning = true
	_spawn_timer = 0.0

# ── Spawning ──────────────────────────────────────────────────────────────────

func _spawn_one(entry_data: Dictionary) -> void:
	# instantiate() from a PackedScene is much faster than duplicate() on a live @tool node
	var companion: BitzCompanion = companion_scene.instantiate()

	# Assign identity BEFORE add_child so _ready() sees the correct values
	# and only fires one fetch (both setters call _request_fetch which dedupes via _fetch_dirty)
	companion.quest_id   = entry_data["quest_id"]
	companion.species_id = entry_data["species_id"]

	if target:
		companion.target = target

	add_child(companion)
	_spawned.append(companion)

	print("[BitzFarmSpawner] + %s / species %d (%s)" % [
		companion.quest_id,
		companion.species_id,
		entry_data["common_name"],
	])

# ── Helpers ───────────────────────────────────────────────────────────────────

func _clear_spawned():
	_spawn_queue.clear()
	_pending_free.clear()
	for c in _spawned:
		if is_instance_valid(c):
			c.queue_free()
	_spawned.clear()
	print("[BitzFarmSpawner] Cleared")
