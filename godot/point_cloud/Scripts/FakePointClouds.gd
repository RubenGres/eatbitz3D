@tool
class_name PointCloudParticles
extends GPUParticles3D

@export var texture: Texture2D:
	set(value):
		texture = value
		_set_texture(value)
		
@export var scale_multiplier: float = 0.1:
	set(value):
		scale_multiplier = value
		_set_scale(value)

func _ready():
	self.process_material = process_material.duplicate()

func _set_scale(value: float):
	if texture:
		process_material.set_shader_parameter("emission_shape", texture.get_size() * value)

func _set_texture(value: Texture2D):
	if self.process_material and value:
		process_material.set_shader_parameter("emission_shape", value.get_size() * scale_multiplier)
		process_material.set_shader_parameter("input_texture", value)
		process_material.set_shader_parameter("height_texture", value)
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

func _process(delta: float) -> void:
	pass
