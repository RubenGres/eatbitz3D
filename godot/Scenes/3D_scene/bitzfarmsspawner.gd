@tool
extends Node3D
class_name BitzFarmSpawner

@export_group("Setup")
@export var companion_scene: PackedScene
@export var api_url: String = "https://bitz.tools/api/farm-images/venn"
@export var target: Node3D
@export var spawn_interval: float = 0.1

@export_group("Spawn Layout")
@export var spawn_radius: float = 5.0

@export_subgroup("Debug")
@export_tool_button("Fetch & Spawn") var _spawn_button: Callable = fetch_and_spawn
@export_tool_button("Clear") var _clear_button: Callable = _clear_spawned

var _http: HTTPRequest
var _spawned: Array[BitzCompanion] = []
var _pending_free: Array[BitzCompanion] = []
var _spawn_queue: Array[Dictionary] = []
var _spawn_timer: float = 0.0
var _is_spawning: bool = false
var _free_timer: float = 0.0
var _total_expected: int = 0  # total companions queued for this batch
const FREE_DELAY: float = 0.5

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready():
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_response)

	if not Engine.is_editor_hint():
		fetch_and_spawn()

func _process(delta: float) -> void:
	if not _pending_free.is_empty():
		_free_timer -= delta
		if _free_timer <= 0.0:
			for c in _pending_free:
				if is_instance_valid(c):
					c.queue_free()
			_pending_free.clear()

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

	for c in _spawned:
		if is_instance_valid(c):
			_pending_free.append(c)
	_spawned.clear()
	_free_timer = FREE_DELAY
	_spawn_queue.clear()

	var seen: Dictionary = {}
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

	_total_expected = _spawn_queue.size()
	print("[BitzFarmSpawner] Queued %d companions across %d farms" % [
		_total_expected, data.keys().size()
	])
	_is_spawning = true
	_spawn_timer = 0.0

# ── Spawning ──────────────────────────────────────────────────────────────────

func _spawn_one(entry_data: Dictionary) -> void:
	var companion: BitzCompanion = companion_scene.instantiate()

	companion.quest_id   = entry_data["quest_id"]
	companion.species_id = entry_data["species_id"]

	if target:
		companion.target = target

	var index  := _spawned.size()
	var offset := _fibonacci_sphere_point(index, _total_expected) * spawn_radius

	add_child(companion)
	companion.global_position = global_position + offset
	_spawned.append(companion)

	print("[BitzFarmSpawner] + %s / species %d (%s)" % [
		companion.quest_id,
		companion.species_id,
		entry_data["common_name"],
	])

# ── Helpers ───────────────────────────────────────────────────────────────────

func _fibonacci_sphere_point(index: int, total: int) -> Vector3:
	var golden_ratio := (1.0 + sqrt(5.0)) / 2.0
	var theta        := acos(1.0 - 2.0 * (index + 0.5) / max(total, 1))
	var phi          := TAU * index / golden_ratio
	return Vector3(
		sin(theta) * cos(phi),
		cos(theta),
		sin(theta) * sin(phi)
	)

func _clear_spawned():
	_spawn_queue.clear()
	_pending_free.clear()
	_total_expected = 0
	for c in _spawned:
		if is_instance_valid(c):
			c.queue_free()
	_spawned.clear()
	print("[BitzFarmSpawner] Cleared")
