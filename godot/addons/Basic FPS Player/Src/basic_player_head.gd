extends Node3D

@onready var info_panel: InfoPanel = $"../../CanvasLayer/InfoPanel"

var _hovered_ingredient = null
var _panel_open := false

func _ready() -> void:
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
	_clear_highlight()

func _on_info_panel_closed() -> void:
	_panel_open = false
