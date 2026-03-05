@tool
extends Node3D
class_name Ingredient3D

signal rotation_completed

@export var target: Node3D:
	set(value):
		target = value
		_set_target()

@export var sphere_radius: float:
	set(value):
		sphere_radius = value
		_set_sphere_radius()

@export var mesh: ArrayMesh:
	set(value):
		mesh = value
		_set_mesh()

@export var is_highlighted: bool = false:
	set(value):
		is_highlighted = value
		_set_highlighted()

@export var highlight_material: Material

@onready var model_3d = $ModelDisplay/Model3d
@onready var model_display = $ModelDisplay
@onready var species = $ModelDisplay/GravitatingSpecies
@onready var main_particles = $ModelDisplay/Model3d/Particles

func _ready() -> void:
	add_to_group("ingredients")
	_set_target()
	_set_mesh()

	model_3d.material_override = model_3d.material_override.duplicate()

func _set_target():
	if species:
		for s in species.get_children():
			s.target = target

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

		# Remove old collision from model_3d if it exists
		var old_body = model_3d.get_node_or_null("Model3d_col")
		if old_body:
			old_body.queue_free()

		await get_tree().process_frame

		# Create new convex collision (adds StaticBody3D as child of model_3d)
		model_3d.create_convex_collision()

		# Remove old outline mesh if it exists
		var old_outline = model_3d.get_node_or_null("OutlineMesh")
		
		if old_outline:
			old_outline.queue_free()

		await get_tree().process_frame

		# Create and add outline mesh
		var outline_mesh := MeshInstance3D.new()
		outline_mesh.name = "OutlineMesh"
		outline_mesh.mesh = model_3d.mesh.duplicate()
		outline_mesh.scale = Vector3.ONE * 1.05
		outline_mesh.material_override = highlight_material
		outline_mesh.visible = is_highlighted
		model_3d.add_child(outline_mesh)

func _set_highlighted():
	var outline = model_3d.get_node_or_null("OutlineMesh") if model_3d else null
	if outline:
		outline.visible = is_highlighted


func _on_model_3d_rotation_completed() -> void:
	rotation_completed.emit()
