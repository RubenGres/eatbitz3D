extends Node3D

@onready var info_panel: InfoPanel = $"../../CanvasLayer/InfoPanel"

# Max duration and drift for a touch release to count as a tap (open species).
# Anything longer or further is treated as a long-press / drag (camera look only).
const TAP_MAX_DURATION = 0.25
const TAP_MAX_DRIFT = 20.0

var _hovered_ingredient = null
var _panel_open = false
var _touch_device = false
var _touch_start_time = 0.0
var _touch_start_pos = Vector2.ZERO
var _touch_active = false
var _touch_is_tap = false

func _ready() -> void:
	_touch_device = DisplayServer.is_touchscreen_available()
	info_panel.opened.connect(_on_info_panel_opened)
	info_panel.closed.connect(_on_info_panel_closed)

func _process(_delta: float) -> void:
	if _panel_open:
		return

	var camera = get_viewport().get_camera_3d()
	if not camera:
		_clear_highlight()
		return

	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_end = ray_origin + camera.project_ray_normal(mouse_pos) * 100.0

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	var result = space_state.intersect_ray(query)

	if result:
		var ingredient = _get_ingredient(result["collider"])
		if ingredient != _hovered_ingredient:
			_clear_highlight()
			_hovered_ingredient = ingredient
			if _hovered_ingredient:
				_hovered_ingredient.is_highlighted = true
	else:
		_clear_highlight()

func _unhandled_input(event: InputEvent) -> void:
	if _panel_open:
		return

	if _touch_device:
		if event is InputEventScreenTouch:
			if event.pressed:
				_touch_start_time = Time.get_ticks_msec() / 1000.0
				_touch_start_pos = event.position
				_touch_active = true
				_touch_is_tap = true
			else:
				var elapsed = Time.get_ticks_msec() / 1000.0 - _touch_start_time
				if _touch_active and _touch_is_tap and elapsed <= TAP_MAX_DURATION:
					# Raycast at the release position — _hovered_ingredient from _process
					# isn't reliable on touch (get_mouse_position() isn't updated by touches).
					var ingredient = _pick_ingredient_at(event.position)
					if ingredient:
						info_panel.slide_in()
						info_panel.focus_on(ingredient)
				_touch_active = false
				_touch_is_tap = false
		elif event is InputEventScreenDrag:
			if _touch_is_tap and event.position.distance_to(_touch_start_pos) > TAP_MAX_DRIFT:
				_touch_is_tap = false
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _hovered_ingredient:
			var ingredient = _hovered_ingredient
			info_panel.slide_in()
			info_panel.focus_on(ingredient)

func _clear_highlight() -> void:
	if _hovered_ingredient:
		_hovered_ingredient.is_highlighted = false
		_hovered_ingredient = null

func _pick_ingredient_at(screen_pos: Vector2):
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return null
	var ray_origin = camera.project_ray_origin(screen_pos)
	var ray_end = ray_origin + camera.project_ray_normal(screen_pos) * 100.0
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	var result = get_world_3d().direct_space_state.intersect_ray(query)
	if result:
		return _get_ingredient(result["collider"])
	return null

func _get_ingredient(collider: Node):
	var node = collider
	while node:
		if node is Ingredient3D or node is BitzCompanion:
			return node
		node = node.get_parent()
	return null

func _on_info_panel_opened() -> void:
	_panel_open = true
	_touch_active = false
	_touch_is_tap = false
	_clear_highlight()

func _on_info_panel_closed() -> void:
	_panel_open = false
