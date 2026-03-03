extends Node3D

@onready var raycast = $RayCast3D
@onready var info_panel: InfoPanel = $"../../CanvasLayer/InfoPanel"

var _hovered_ingredient = null

func _ready() -> void:
	info_panel.opened.connect(_on_info_panel_opened)
	info_panel.closed.connect(_on_info_panel_closed)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _process(_delta: float) -> void:
	if raycast.is_colliding():
		var collider = raycast.get_collider()
		var ingredient = _get_ingredient(collider)
		if ingredient != _hovered_ingredient:
			_clear_highlight()
			_hovered_ingredient = ingredient
			if _hovered_ingredient:
				_hovered_ingredient.is_highlighted = true
	else:
		_clear_highlight()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _hovered_ingredient:
			info_panel.slide_in()
			
			if _hovered_ingredient is BitzCompanion:
				info_panel.quest_id = _hovered_ingredient.quest_id
				info_panel.species_id = _hovered_ingredient.species_id

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
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_info_panel_closed() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
