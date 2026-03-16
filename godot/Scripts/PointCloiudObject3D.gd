@tool
extends MeshInstance3D

@export var texture: Texture2D:
	set(value):
		texture = value
		_update_material_texture()

@export var point_size: float = 1
@export var density_curve: Curve ## Controls point density based on distance
@export var max_distance: float = 100.0 ## Maximum distance for curve normalization
@export var target: Node3D
@export var max_side: float = 0.1:
	set(value):
		max_side = value
		if(is_node_ready()):
			_update_material_texture()

var material: Material

func _ready() -> void:
	# Create default curve if none exists
	if not density_curve:
		density_curve = Curve.new()
		density_curve.add_point(Vector2(0, 1)) # Close = full density
		density_curve.add_point(Vector2(1, 0)) # Far = low density
	
	_update_material_texture()
	
	set_surface_override_material(0, get_surface_override_material(0).duplicate())
	mesh = mesh.duplicate()

	material = get_surface_override_material(0)

func _process(_delta: float) -> void:
	if not target:
		return
	
	var distance = target.global_position.distance_to(self.global_position)
	var normalized_distance = clamp(distance / max_distance, 0.0, 1.0)
	var curve_value = density_curve.sample(normalized_distance)
	var point_density = curve_value * point_size
	
	if material:
		material.set_shader_parameter("point_density", point_density)
		
func _update_material_texture() -> void:
	if material and texture:
		material.set_shader_parameter("input_texture", texture)
		var texture_size = texture.get_size()
		var longest_side = max(texture_size.x, texture_size.y)
		if longest_side > 0.0:
			mesh.size = texture_size * (max_side / longest_side)
