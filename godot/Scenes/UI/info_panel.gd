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

const _BASE_FONT_SPECIES_NAME := 20
const _BASE_FONT_SCIENTIFIC := 11
const _BASE_FONT_DESCRIPTION := 12
const _BASE_FONT_SECTION_TITLE := 17
const _BASE_FONT_CLOSE := 20
const _BASE_TEXTURE_MIN_WIDTH := 250

var _api: BitzAPI
var _tween: Tween
var _font_scale: float = 1.0

signal opened
signal closed
signal focused(object: Node3D)

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
	_apply_font_scale()
	_move_offscreen()
	_api.species_data_loaded.connect(_on_species_data)
	_api.image_loaded.connect(_on_image)

func set_font_scale(scale: float) -> void:
	if is_equal_approx(_font_scale, scale):
		return
	_font_scale = scale
	if is_node_ready():
		_apply_font_scale()

func _apply_font_scale() -> void:
	var name_label: Label = %SpeciesName
	var sci_label: Label = %ScientificName
	var desc_label: Label = %Description
	var extra_label: Label = %AdditionalInfo
	var desc_title: Label = $SidePanel/VBoxContainer/ScrollContainer/MarginContainer2/VBoxContainer/MarginContainer2/VBoxContainer/DescriptionTitle
	var extra_title: Label = $SidePanel/VBoxContainer/ScrollContainer/MarginContainer2/VBoxContainer/MarginContainer2/VBoxContainer/AdditonalInfoTitle
	var close_btn: Button = $SidePanel/VBoxContainer/HBoxContainer/Button

	name_label.add_theme_font_size_override("font_size", int(_BASE_FONT_SPECIES_NAME * _font_scale))
	sci_label.add_theme_font_size_override("font_size", int(_BASE_FONT_SCIENTIFIC * _font_scale))
	desc_label.add_theme_font_size_override("font_size", int(_BASE_FONT_DESCRIPTION * _font_scale))
	extra_label.add_theme_font_size_override("font_size", int(_BASE_FONT_DESCRIPTION * _font_scale))
	desc_title.add_theme_font_size_override("font_size", int(_BASE_FONT_SECTION_TITLE * _font_scale))
	extra_title.add_theme_font_size_override("font_size", int(_BASE_FONT_SECTION_TITLE * _font_scale))
	close_btn.add_theme_font_size_override("font_size", int(_BASE_FONT_CLOSE * _font_scale))

	var tex_rect: TextureRect = %TextureRect
	tex_rect.custom_minimum_size.x = int(_BASE_TEXTURE_MIN_WIDTH * _font_scale)

func _gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		slide_out()
		accept_event()

func _request_data():
	if quest_id.is_empty():
		return
	_api.fetch_history(quest_id, species_id)
	var is_mobile_web := OS.has_feature("web_android") or OS.has_feature("web_ios")
	_api.fetch_species_image(quest_id, species_id, "small" if is_mobile_web else "medium")
	slide_in()

func _on_species_data(qid: String, sid: int, species_info: Dictionary):
	print("[InfoPanel] species info loaded: ", species_info)
	if qid != quest_id or sid != species_id:
		return
	var common = species_info.get("common_name", "")
	if common.is_empty():
		common = species_info.get("name", "Unknown").split("(")[0].split("/")[0].strip_edges()
	%SpeciesName.text = common
	%ScientificName.text = species_info.get("scientific_name", "")
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
	%SpeciesName.text = species_name.split("(")[0].split("/")[0].strip_edges()
	%ScientificName.text = ""
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
	%ScientificName.text = ""
	%Description.text = ""
	%AdditionalInfo.text = ""
	%TextureRect.texture = null
	$SidePanel/VBoxContainer/ScrollContainer.scroll_vertical = 0

func _kill_tween():
	if _tween and _tween.is_running():
		_tween.kill()


func sync_language(locale: String) -> void:
	_api.set_locale(locale)
	if not quest_id.is_empty():
		_api.fetch_history(quest_id, species_id)
	_update_ingredient_text()
