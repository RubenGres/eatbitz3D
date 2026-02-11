@tool

extends Node3D

@export var target: Node3D:
	set(value):
		target = value
		_set_target_3d()
		
@export var sphere_radius: float:
	set(value):
		sphere_radius = value
		_set_sphere_radius()
		
@export var mesh: ArrayMesh:
	set(value):
		mesh = value
		_set_mesh()

@onready var model_3d = $BeetRootDisplay/Model3d
@onready var species = $BeetRootDisplay/GravitatingSpecies
@onready var main_particles = $BeetRootDisplay/Model3d/Particles

func _ready() -> void:
	_set_target_3d()
	_set_mesh()
	
	model_3d.material_override = model_3d.material_override.duplicate()

func _set_target_3d():
	if species:
		for s in species.get_children():
			s.target_3D = target

func _set_sphere_radius():
	if species:
		for s in species.get_children():
			s.sphere_radius = sphere_radius
			
func _set_mesh():
	if model_3d:
		var albedo = mesh.surface_get_material(0).albedo_texture
		model_3d.material_override.set_shader_parameter("input_texture", albedo)
		model_3d.mesh = mesh
		main_particles.visible = mesh != null
