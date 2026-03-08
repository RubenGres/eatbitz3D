@tool
extends Sprite3D

func _on_point_cloud_from_bitz_rembg_texture_loaded(texture) -> void:
	self.material_override.set_shader_parameter("sprite_texture", texture)
