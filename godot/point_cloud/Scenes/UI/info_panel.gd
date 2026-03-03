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
signal focused(object: Node3D)

func _ready():
	_api = BitzAPI.new()
	add_child(_api)
	position.x = get_viewport_rect().size.x
	_api.species_data_loaded.connect(_on_species_data)
	_api.image_loaded.connect(_on_image)
	
	_request_data()

func _request_data():
	if quest_id.is_empty():
		return
	_api.fetch_history(quest_id, species_id)
	_api.fetch_species_image(quest_id, species_id)
	slide_in()

func _on_species_data(qid: String, sid: int, species_info: Dictionary):
	if qid != quest_id or sid != species_id:
		return
	%SpeciesName.text = species_info.get("name", "Unknown")
	%Description.text = species_info.get("what_is_it", "")
	%AdditionalInfo.text = species_info.get("information", "")

func _on_image(qid: String, sid: int, texture: ImageTexture):
	if qid != quest_id or sid != species_id:
		return
	%TextureRect.texture = texture

func focus_on(object: Node3D):
	if object is BitzCompanion:
		quest_id = object.quest_id
		species_id = object.species_id
		
	focused.emit(object)

func slide_in():
	_kill_tween()
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "position:x", get_viewport_rect().size.x - size.x, slide_duration)
	opened.emit()

func slide_out():
	_kill_tween()
	_tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "position:x", get_viewport_rect().size.x, slide_duration)
	closed.emit()

func _kill_tween():
	if _tween and _tween.is_running():
		_tween.kill()
