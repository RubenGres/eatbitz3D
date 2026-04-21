extends Node3D

const HoldIndicatorScript = preload("res://Scenes/UI/hold_indicator.gd")

@onready var info_panel: InfoPanel = $"../../CanvasLayer/InfoPanel"
@onready var _canvas_layer: CanvasLayer = $"../../CanvasLayer"

const HOLD_DURATION = 0.2
const HOLD_MAX_DRIFT = 20.0

var _hovered_ingredient = null
var _panel_open = false
var _touch_device = false
var _touch_start_time = 0.0
var _touch_start_pos = Vector2.ZERO
var _touch_held = false
var _hold_indicator: Control = null

func _ready() -> void:
	_touch_device = DisplayServer.is_touchscreen_available()
	info_panel.opened.connect(_on_info_panel_opened)
	info_panel.closed.connect(_on_info_panel_closed)
	if _touch_device:
		_hold_indicator = HoldIndicatorScript.new()
		_canvas_layer.add_child(_hold_indicator)

func _process(_delta: float) -> void:
	if _panel_open:
		return

	if _touch_held:
		var elapsed = Time.get_ticks_msec() / 1000.0 - _touch_start_time
		if _hold_indicator:
			if _hovered_ingredient:
				if not _hold_indicator.visible:
					_hold_indicator.show_at(_touch_start_pos)
				_hold_indicator.progress = clamp(elapsed / HOLD_DURATION, 0.0, 1.0)
			else:
				_hold_indicator.hide_indicator()
		if elapsed >= HOLD_DURATION and _hovered_ingredient:
			_touch_held = false
			var ingredient = _hovered_ingredient
			if _hold_indicator:
				_hold_indicator.hide_indicator()
			info_panel.slide_in()
			info_panel.focus_on(ingredient)
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
				_touch_held = true
				if _hold_indicator and _hovered_ingredient:
					_hold_indicator.show_at(event.position)
			else:
				_touch_held = false
				if _hold_indicator:
					_hold_indicator.hide_indicator()
		elif event is InputEventScreenDrag:
			if _touch_held and event.position.distance_to(_touch_start_pos) > HOLD_MAX_DRIFT:
				_touch_held = false
				if _hold_indicator:
					_hold_indicator.hide_indicator()
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

func _get_ingredient(collider: Node):
	var node = collider
	while node:
		if node is Ingredient3D or node is BitzCompanion:
			return node
		node = node.get_parent()
	return null

func _on_info_panel_opened() -> void:
	_panel_open = true
	_touch_held = false
	if _hold_indicator:
		_hold_indicator.hide_indicator()
	_clear_highlight()

func _on_info_panel_closed() -> void:
	_panel_open = false
