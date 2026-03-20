@tool
class_name PointCloudParticles
extends GPUParticles3D

@export var texture: Texture2D:
	set(value):
		texture = value
		_set_texture(value)
		
@export var max_side: float = 0.1:
	set(value):
		max_side = value
		_set_max_side()

func _ready():
	self.process_material = process_material.duplicate()
	

func _set_max_side():
	if texture:
		var texture_size = texture.get_size()
		var longest_side = max(texture_size.x, texture_size.y)
		if longest_side > 0.0:
			var emission_shape = texture_size * (max_side / longest_side)
			process_material.set_shader_parameter("emission_shape", emission_shape)

func _set_texture(value: Texture2D):
	if self.process_material and value:
		var texture_size = value.get_size()
		var longest_side = max(texture_size.x, texture_size.y)
		var aspect = texture_size.x / texture_size.y
		if longest_side > 0.0:
			var emission_shape = texture_size * (max_side / longest_side)
			process_material.set_shader_parameter("emission_shape", emission_shape)
		process_material.set_shader_parameter("input_texture", value)
		process_material.set_shader_parameter("height_texture", value)
		process_material.set_shader_parameter("crop_aspect", aspect)
		_compute_height_range(value)

func _compute_height_range(tex: Texture2D):
	var image = tex.get_image()
	if not image:
		return
	
	if image.is_compressed():
		image.decompress()
	
	image.convert(Image.FORMAT_RGBA8)
	var data = image.get_data()
	
	var height_min = 1.0
	var height_max = 0.0
	
	for i in range(0, data.size(), 4):
		var a = data[i + 3]
		if a > 25:
			var g = data[i + 1] / 255.0
			
			if g < 0.001:
				continue
			
			height_min = min(height_min, g)
			height_max = max(height_max, g)
		
	process_material.set_shader_parameter("height_min", height_min)
	process_material.set_shader_parameter("height_max", height_max)

func _process(_delta: float) -> void:
	pass
