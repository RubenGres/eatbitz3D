@tool
extends Control
class_name InfoPanel

@export var quest_id: String = "":
	set(value):
		quest_id = value
		if is_node_ready():
			_request_data()

@export var species_id: int = 0:
	set(value):
		species_id = value
		if is_node_ready():
			_request_data()
			
@export var slide_duration: float = 0.4

var _api: BitzAPI
var _tween: Tween

signal opened
signal closed
signal change_language(language: String)
signal focused(object: Node3D)

var current_language = "en"
var _current_ingredient: Ingredient3D = null

var portrait_mode: bool = false:
	set(value):
		if portrait_mode == value:
			return
		portrait_mode = value
		if is_node_ready():
			_apply_layout()

func _ready():
	_api = BitzAPI.new()
	add_child(_api)
	_apply_layout()
	_move_offscreen()
	_api.species_data_loaded.connect(_on_species_data)
	_api.image_loaded.connect(_on_image)

func _gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		slide_out()
		accept_event()

func _request_data():
	if quest_id.is_empty():
		return
	_api.fetch_history(quest_id, species_id)
	_api.fetch_species_image(quest_id, species_id, "medium")
	slide_in()

func _on_species_data(qid: String, sid: int, species_info: Dictionary):
	print("[InfoPanel] species info loaded: ", species_info)
	if qid != quest_id or sid != species_id:
		return
	%SpeciesName.text = species_info.get("name", "Unknown").split("(")[0].split("/")[0]
	%Description.text = species_info.get("what_is_it", "")
	%AdditionalInfo.text = species_info.get("information", "")

func _on_image(qid: String, sid: int, texture: ImageTexture):
	if qid != quest_id or sid != species_id:
		return
	%TextureRect.texture = texture

func _update_ingredient_text():
	if not _current_ingredient:
		return
	set_manual(
		tr(_current_ingredient.ingredient_name),
		tr(_current_ingredient.ingredient_description),
		"",
		_current_ingredient.associated_card_texture
	)

func set_manual(species_name: String, description: String, additional_info: String, texture: Texture2D = null):
	%SpeciesName.text = species_name.split("(")[0].split("/")[0]
	%Description.text = description
	%AdditionalInfo.text = additional_info
	if texture:
		%TextureRect.texture = texture

func focus_on(object: Node3D):
	if object is BitzCompanion:
		quest_id = object.quest_id
		species_id = object.species_id
	elif object is Ingredient3D:
		_current_ingredient = object
		_update_ingredient_text()
	
	focused.emit(object)

func _move_offscreen():
	if portrait_mode:
		position.y = get_viewport_rect().size.y
		position.x = 0
	else:
		position.x = get_viewport_rect().size.x
		position.y = 0

func _apply_layout():
	var side_panel = $SidePanel
	var separator = $SidePanel/VSeparator

	if portrait_mode:
		separator.visible = false
		side_panel.anchor_left = 0.0
		side_panel.anchor_top = 0.4
		side_panel.anchor_right = 1.0
		side_panel.anchor_bottom = 1.0
		side_panel.offset_left = 0
		side_panel.offset_top = 0
		side_panel.offset_right = 0
		side_panel.offset_bottom = 0
	else:
		separator.visible = true
		side_panel.anchor_left = 1.0
		side_panel.anchor_top = 0.0
		side_panel.anchor_right = 1.0
		side_panel.anchor_bottom = 1.0
		side_panel.offset_left = -336.0
		side_panel.offset_top = 0
		side_panel.offset_right = 0
		side_panel.offset_bottom = 0

	_move_offscreen()

func slide_in():
	_kill_tween()
	$SidePanel/VBoxContainer/ScrollContainer.scroll_vertical = 0
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	if portrait_mode:
		var vp_h = get_viewport_rect().size.y
		_tween.tween_property(self, "position:y", vp_h - size.y, slide_duration)
	else:
		_tween.tween_property(self, "position:x", get_viewport_rect().size.x - size.x, slide_duration)

	opened.emit()

func slide_out():
	_kill_tween()
	_tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)

	if portrait_mode:
		_tween.tween_property(self, "position:y", get_viewport_rect().size.y, slide_duration)
	else:
		_tween.tween_property(self, "position:x", get_viewport_rect().size.x, slide_duration)

	_tween.tween_callback(_reset)
	closed.emit()

func _reset():
	_current_ingredient = null
	quest_id = ""
	species_id = 0
	%SpeciesName.text = ""
	%Description.text = ""
	%AdditionalInfo.text = ""
	%TextureRect.texture = null
	$SidePanel/VBoxContainer/ScrollContainer.scroll_vertical = 0

func _kill_tween():
	if _tween and _tween.is_running():
		_tween.kill()


func _on_language_button_pressed() -> void:
	current_language = "en" if current_language == "pt" else "pt"
	%LanguageButton.text = "EN" if current_language == "pt" else "PT"
	change_language.emit(current_language)
	TranslationServer.set_locale(current_language)
	_update_ingredient_text()
