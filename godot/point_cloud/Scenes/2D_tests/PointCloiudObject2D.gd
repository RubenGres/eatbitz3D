@tool
extends Sprite2D

@export var point_size: int = 1
@export var my_texture: Texture2D:
	set(value):
		my_texture = value
		_update_material_texture()


func _ready() -> void:
	_update_material_texture()
	modulate = Color(1.5, 1.5, 1.5)
	material = material.duplicate()

func _process(delta: float) -> void:
	var point_density = (%Camera2D.zoom.x * 30) * point_size
	
	if material:
		material.set_shader_parameter("point_density", point_density)
	
func _update_material_texture() -> void:
	self.texture = my_texture
	if material and my_texture:
		material.set_shader_parameter("input_texture", my_texture)
