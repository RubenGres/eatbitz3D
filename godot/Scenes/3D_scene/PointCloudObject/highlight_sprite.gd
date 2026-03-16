@tool
extends MeshInstance3D

@export var max_side: float = 1.0:
	set(value):
		max_side = value
		if(is_node_ready()):
			_set_max_side()

@export var texture: Texture2D:
	set(value):
		texture = value
		_update_material_texture()

func _ready():
	self.material_override = self.material_override.duplicate()

func _set_max_side() -> void:
	if texture:
		var texture_size = texture.get_size()
		var longest_side = max(texture_size.x, texture_size.y)
		if longest_side > 0.0:
			mesh.size = texture_size * (max_side / longest_side)

func _update_material_texture() -> void:
	self.material_override.set_shader_parameter("sprite_texture", texture)
	_set_max_side()
