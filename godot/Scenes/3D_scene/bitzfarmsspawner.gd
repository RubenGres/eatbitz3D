@tool
extends Node3D
class_name BitzFarmSpawner

@export_group("Setup")
@export var companion_scene: PackedScene
@export var target: Node3D
@export var spawn_interval: float = 0.1

@export_group("Spawn Layout")
@export var ring_radii: Array[float] = [2.5, 5.0, 8.0, 12.0]
@export var ring_capacities: Array[int] = [6, 12, 20, 30]

@export_group("Loading")
## Max companions fetching their texture over HTTP at the same time.
@export var max_concurrent_fetches: int = 4

@export_subgroup("Debug")
@export_tool_button("Spawn") var _spawn_button: Callable = spawn_companions
@export_tool_button("Clear") var _clear_button: Callable = _clear_spawned

var _http: HTTPRequest
var _spawned: Array[BitzCompanion] = []
var _pending_free: Array[BitzCompanion] = []
var _spawn_queue: Array[Dictionary] = []
var _spawn_timer: float = 0.0
var _is_spawning: bool = false
var _free_timer: float = 0.0
var _total_expected: int = 0
const FREE_DELAY: float = 0.5

# ── Fetch queue ───────────────────────────────────────────────────────────
var _fetch_queue: Array[BitzCompanion] = []
var _currently_fetching: int = 0

# ── Lifecycle ─────────────────────────────────────────────────────────────

func _ready():
	if not Engine.is_editor_hint():
		spawn_companions()

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
	else:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			_spawn_timer = spawn_interval
			var entry_data: Dictionary = _spawn_queue.pop_front()
			_spawn_one(entry_data)

	# Drain the fetch queue up to the concurrency cap
	_pump_fetch_queue()

# ── API ───────────────────────────────────────────────────────────────────

func spawn_companions():
	
	for c in _spawned:
		if is_instance_valid(c):
			_pending_free.append(c)
	
	_spawned.clear()
	_fetch_queue.clear()
	_currently_fetching = 0
	_free_timer = FREE_DELAY
	_spawn_queue.clear()

	var data = CompanionList.get_companions()
	print(data)
	
	for quest_id in data.keys():
		var image_numbers: Array = data[quest_id]
		for image_number in image_numbers:
			var qid = str(quest_id)
			var sid = int(image_number)

			_spawn_queue.append({
				"quest_id":    qid,
				"species_id":  sid
			})

	_total_expected = _spawn_queue.size()
	print("[BitzFarmSpawner] Queued %d companions across %d quests" % [
		_total_expected, data.keys().size()
	])
	_is_spawning = true
	_spawn_timer = 0.0

# ── Spawning ──────────────────────────────────────────────────────────────

func _spawn_one(entry_data: Dictionary) -> void:
	var companion: BitzCompanion = companion_scene.instantiate()

	# Tell companion NOT to auto-fetch; we control the fetch queue.
	companion.auto_fetch = false
	companion.quest_id   = entry_data["quest_id"]
	companion.species_id = entry_data["species_id"]

	if target:
		companion.target = target

	var index     = _spawned.size()
	var ring_slot = _ring_for_index(index)

	# Set orbit radius from ring before _ready() fires
	var radius = ring_radii[ring_slot.x] if ring_slot.x < ring_radii.size() else ring_radii[-1]
	companion.orbit_radius = radius

	add_child(companion)  # _ready() fires here, reads orbit_radius
	_spawned.append(companion)

	# Enqueue for managed fetching
	companion.rembg_texture_loaded.connect(_on_companion_loaded)
	_fetch_queue.append(companion)

# ── Fetch-queue management ────────────────────────────────────────────────

func _pump_fetch_queue() -> void:
	while _currently_fetching < max_concurrent_fetches and not _fetch_queue.is_empty():
		var companion: BitzCompanion = _fetch_queue.pop_front()
		if is_instance_valid(companion):
			_currently_fetching += 1
			companion.start_fetch()

func _on_companion_loaded(_texture) -> void:
	_currently_fetching = maxi(_currently_fetching - 1, 0)

# ── Layout ────────────────────────────────────────────────────────────────

func _ring_for_index(index: int) -> Vector2i:
	var remaining = index
	for ring in ring_capacities.size():
		var capacity = ring_capacities[ring]
		if remaining < capacity:
			return Vector2i(ring, remaining)
		remaining -= capacity
	# Overflow: pack into last ring
	var last = ring_capacities.size() - 1
	return Vector2i(last, remaining % max(ring_capacities[last], 1))

func _ring_point(ring: int, slot: int) -> Vector3:
	var radius   = ring_radii[ring] if ring < ring_radii.size() else ring_radii[-1]
	var capacity = ring_capacities[ring] if ring < ring_capacities.size() else ring_capacities[-1]
	var golden_ratio = (1.0 + sqrt(5.0)) / 2.0
	var theta        = acos(1.0 - 2.0 * (slot + 0.5) / max(capacity, 1))
	var phi          = TAU * slot / golden_ratio
	return Vector3(
		sin(theta) * cos(phi) * radius,
		cos(theta)            * radius,
		sin(theta) * sin(phi) * radius
	)

# ── Helpers ───────────────────────────────────────────────────────────────

func _clear_spawned():
	_spawn_queue.clear()
	_fetch_queue.clear()
	_currently_fetching = 0
	_pending_free.clear()
	_total_expected = 0
	for c in _spawned:
		if is_instance_valid(c):
			c.queue_free()
	_spawned.clear()
	print("[BitzFarmSpawner] Cleared")
