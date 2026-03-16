@tool
extends Node3D
class_name BitzCompanion

signal rembg_texture_loaded(texture)

@onready var point_cloud_object = $ParticlesTest

var rembg_base_url: String = "https://eat.bitz.tools/rembg"
#var rembg_base_url: String = "http://localhost:8888/rembg"

# ── Identity ──────────────────────────────────────────────────────────────────
@export_group("Identity")
@export var quest_id: String = "":
	set(value):
		quest_id = value
		_request_fetch()

@export var species_id: int = 0:
	set(value):
		species_id = value
		_request_fetch()

# ── Scene References ──────────────────────────────────────────────────────────
@export_group("Scene References")
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

@export var billboard_camera: bool = true:
	set(value):
		billboard_camera = value
		if is_node_ready():
			point_cloud_object.billboard_camera = value

# ── Firefly Movement ──────────────────────────────────────────────────────────
@export_group("Firefly Movement")

@export_subgroup("Orbit")
@export var orbit_radius: float = 1.0
@export var orbit_radius_variance: float = 0.3

@export_subgroup("Speed")
@export var drift_speed: float = 0.8:
	set(value):
		drift_speed = value
		if is_node_ready():
			_effective_speed = drift_speed + randf_range(-drift_speed_variance, drift_speed_variance)
@export var drift_speed_variance: float = 0.4

@export_subgroup("Wandering")
@export var wander_strength: float = 0.5
@export var wander_frequency: float = 0.6

@export_subgroup("Phase")
## Auto-randomized at _ready(). Override to manually sync companions.
@export var phase_offset: float = 0.0

@export_subgroup("Debug")
@export_tool_button("Reload") var _reload_button: Callable = _reload

# ── Proximity Scale ───────────────────────────────────────────────────────────
@export_group("Proximity Scale")

## Distance at which scale reaches 0 (fully invisible)
@export var scale_min_distance: float = 0.5

## Distance at which scale reaches 1 (fully visible)
@export var scale_max_distance: float = 3.0

## Optional curve to control the falloff shape (X: 0=min_dist, 1=max_dist → Y: scale)
## Leave empty for a simple linear ramp.
@export var scale_curve: Curve

# ── Lifetime & Sleep ──────────────────────────────────────────────────────────
@export_group("Lifetime & Sleep")

## How long the companion stays fully visible before sleeping. 0 = infinite.
@export var lifetime: float = 8.0

## How long the companion stays hidden before reappearing. 0 = never sleeps.
@export var sleep_time: float = 4.0

## Duration of the fade-in when appearing.
@export var fade_in_duration: float = 0.8

## Duration of the fade-out when disappearing.
@export var fade_out_duration: float = 1.2

# ── Private ───────────────────────────────────────────────────────────────────
var _http_rembg: HTTPRequest
var _decode_thread: Thread
var _pending_body: PackedByteArray
var _fetch_dirty: bool = false
var bitz_image_loaded: bool = false
var _effective_radius: float
var _effective_speed: float
var _time: float = 0.0

# Lifecycle state machine
enum LifecycleState { LOADING, FADE_IN, ALIVE, FADE_OUT, SLEEPING }
var _lifecycle_state: LifecycleState = LifecycleState.LOADING
var _lifecycle_timer: float = 0.0

# The proximity scale computed each frame — lifecycle multiplies on top of this
var _proximity_scale: float = 1.0

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready():
	print("[BitzCompanion] _ready - quest_id: %s, species_id: %d" % [quest_id, species_id])

	phase_offset      = randf() * TAU
	_effective_radius = orbit_radius + randf_range(-orbit_radius_variance, orbit_radius_variance)
	_effective_speed  = drift_speed  + randf_range(-drift_speed_variance,  drift_speed_variance)

	_http_rembg = HTTPRequest.new()
	add_child(_http_rembg)
	_http_rembg.request_completed.connect(_on_rembg_received)

	_decode_thread = Thread.new()

	point_cloud_object.target = self.target

	if not bitz_image_loaded:
		self.show()           # node visible but scale = 0 so nothing renders
		scale = _safe_scale(1)
		_lifecycle_state = LifecycleState.LOADING
		_fetch_dirty = false
		_fetch()

func _exit_tree() -> void:
	if _decode_thread and _decode_thread.is_started():
		_decode_thread.wait_to_finish()

# ── Process ───────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_update_position(delta)
	_update_proximity_scale()
	_update_lifecycle(delta)

func _update_position(delta: float) -> void:
	if target == null:
		return
	_time += delta * _effective_speed

	var t := _time + phase_offset

	var base_offset := Vector3(
		sin(t * 1.0 + phase_offset) * cos(t * 0.37),
		sin(t * 0.71 + phase_offset),
		cos(t * 1.0 + phase_offset) * sin(t * 0.53)
	) * _effective_radius

	var wander := Vector3(
		sin(t * wander_frequency * 0.91) * wander_strength,
		cos(t * wander_frequency * 0.67) * wander_strength,
		sin(t * wander_frequency * 1.13) * wander_strength
	)

	global_position = target.global_position + base_offset + wander

func _update_proximity_scale() -> void:
	if target == null or scale_max_distance <= scale_min_distance:
		_proximity_scale = 1.0
		return

	var dist    := global_position.distance_to(target.global_position)
	var t_scale := inverse_lerp(scale_min_distance, scale_max_distance, dist)
	t_scale = clamp(t_scale, 0.0, 1.0)

	_proximity_scale = scale_curve.sample_baked(t_scale) if scale_curve else t_scale
	_proximity_scale = maxf(_proximity_scale, 0.001)

const SCALE_EPSILON := 0.0001

func _update_lifecycle(delta: float) -> void:
	match _lifecycle_state:

		LifecycleState.LOADING:
			scale = _safe_scale(SCALE_EPSILON)

		LifecycleState.FADE_IN:
			_lifecycle_timer += delta
			var t = clamp(_lifecycle_timer / max(fade_in_duration, 0.001), 0.0, 1.0)
			var eased := 1.0 - pow(1.0 - t, 3.0)
			var s := maxf(_proximity_scale * eased, SCALE_EPSILON)
			scale = _safe_scale(s)
			if _lifecycle_timer >= fade_in_duration:
				_lifecycle_state = LifecycleState.ALIVE
				_lifecycle_timer = 0.0

		LifecycleState.ALIVE:
			scale = _safe_scale(maxf(_proximity_scale, SCALE_EPSILON))
			if lifetime > 0.0:
				_lifecycle_timer += delta
				if _lifecycle_timer >= lifetime:
					_begin_fade_out()

		LifecycleState.FADE_OUT:
			_lifecycle_timer += delta
			var t = clamp(_lifecycle_timer / max(fade_out_duration, 0.001), 0.0, 1.0)
			var eased := pow(t, 3.0)
			var s := maxf(_proximity_scale * (1.0 - eased), SCALE_EPSILON)
			scale = _safe_scale(s)
			if _lifecycle_timer >= fade_out_duration:
				_lifecycle_state = LifecycleState.SLEEPING
				_lifecycle_timer = 0.0

		LifecycleState.SLEEPING:
			scale = _safe_scale(SCALE_EPSILON)
			if sleep_time > 0.0:
				_lifecycle_timer += delta
				if _lifecycle_timer >= sleep_time:
					_begin_fade_in()

func _begin_fade_in() -> void:
	_lifecycle_state = LifecycleState.FADE_IN
	_lifecycle_timer = 0.0

func _begin_fade_out() -> void:
	_lifecycle_state = LifecycleState.FADE_OUT
	_lifecycle_timer = 0.0

# ── Fetch helpers ─────────────────────────────────────────────────────────────

func _request_fetch() -> void:
	if not is_node_ready():
		return
	if _fetch_dirty:
		return
	_fetch_dirty = true
	call_deferred("_deferred_fetch")

func _deferred_fetch() -> void:
	_fetch_dirty = false
	_fetch()

func _fetch() -> void:
	print("[BitzCompanion] _fetch - quest_id: %s, species_id: %d" % [quest_id, species_id])
	if quest_id == "" or species_id < 0:
		return
	if _http_rembg == null:
		return
	if _http_rembg.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_http_rembg.cancel_request()
	var url := "%s/%s/%d" % [_normalized_base_url(), quest_id, species_id]
	print("[BitzCompanion] Requesting %s" % url)
	var err := _http_rembg.request(url)
	if err != OK:
		push_error("[BitzCompanion] Failed to start rembg request: %d" % err)

# ── Response & decoding ───────────────────────────────────────────────────────

func _on_rembg_received(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	print("[BitzCompanion] response - result: %d, code: %d, size: %d bytes" % [result, response_code, body.size()])
	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("[BitzCompanion] Network error: %d" % result)
		return
	if response_code != 200:
		push_error("[BitzCompanion] HTTP %d" % response_code)
		print("[BitzCompanion] Body: %s" % body.get_string_from_utf8().substr(0, 500))
		return

	if _decode_thread.is_started():
		_decode_thread.wait_to_finish()

	_pending_body = body
	_decode_thread.start(_decode_image_thread)

func _decode_image_thread() -> void:
	var image := Image.new()
	var err := image.load_png_from_buffer(_pending_body)
	if err != OK:
		push_error("[BitzCompanion] PNG decode failed in thread")
		return
	call_deferred("_apply_texture", image)

func _apply_texture(image: Image) -> void:
	var texture := ImageTexture.create_from_image(image)
	point_cloud_object.texture = texture
	print("[BitzCompanion] Texture applied (%dx%d)" % [image.get_width(), image.get_height()])
	bitz_image_loaded = true
	rembg_texture_loaded.emit(texture)
	# Kick off the lifecycle — fade in from scale 0
	_begin_fade_in()

# ── Misc ──────────────────────────────────────────────────────────────────────

func _reload() -> void:
	phase_offset      = randf() * TAU
	_effective_radius = orbit_radius + randf_range(-orbit_radius_variance, orbit_radius_variance)
	_effective_speed  = drift_speed  + randf_range(-drift_speed_variance,  drift_speed_variance)
	print("[BitzCompanion] Reloaded — phase: %.2f, radius: %.2f, speed: %.2f" % [phase_offset, _effective_radius, _effective_speed])

func _set_highlighted() -> void:
	$ParticlesTest/HighlightSprite.visible = is_highlighted

func _normalized_base_url() -> String:
	if rembg_base_url.ends_with("/"):
		return rembg_base_url.substr(0, rembg_base_url.length() - 1)
	return rembg_base_url

func _safe_scale(s: float) -> Vector3:
	if not is_finite(s) or s < SCALE_EPSILON:
		push_warning("[BitzCompanion] clamped bad scale: %f (state: %d)" % [s, _lifecycle_state])
		return Vector3.ONE * SCALE_EPSILON
	return Vector3.ONE * s
