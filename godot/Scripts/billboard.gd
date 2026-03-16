@tool
extends Node3D

@onready var particles = $GPUParticles3D
@onready var point_cloud = $PointCloudObject
@onready var highlighting = $HighlightSprite

@export_range(0.0, 20, 0.001) var sphere_radius: float = 1.0
@export_range(0.0, 1.0, 0.001) var orbit_multiplier: float = 1.0

@export var max_side: float = 1.0:
	set(value):
		max_side = value
		if(is_node_ready()):
			_set_max_side()

@export var billboard_camera: bool = true:
	set(value):
		self.rotation = Vector3.ZERO

var accumulated_time: float = 0.0
var rotation_seed: float = RandomNumberGenerator.new().randf()
var orbital_inclination: float = 0.0  # Angle in radians to tilt the orbit
var orbital_shift_rate : float = PI / 100
var initial_offset: Vector3
var initial_scale: Vector3
var time_offset: float

@export var texture: Texture2D:
	set(value):
		texture = value
		_update_material_texture()

@export var target: Node3D:
	set(value):
		target = value
		_update_target()

func _ready() -> void:
	
	particles.hide()
	highlighting.hide()
	
	# Store initial offset from parent
	initial_offset = position
	initial_scale = self.scale
	
	# Set orbit distance from initial distance if not manually set
	if sphere_radius == 0.0:
		sphere_radius = initial_offset.length()
	
	# Use seed to create time offset for orbit variation
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(rotation_seed)
	time_offset = rng.randf_range(0.0, TAU)
	
	_update_material_texture()
	_update_target()
	_set_max_side()
	
	self.orbital_inclination = rotation_seed * 2 * PI
	

func _set_max_side():
	particles.max_side = self.max_side
	point_cloud.max_side = self.max_side
	highlighting.max_side = self.max_side

func _point_towards_target():
	if not target:
		return
	
	var direction = global_position - target.global_position
	if direction.length() > 0.001:
		look_at(global_position + direction, Vector3.UP)

func _process(_delta: float) -> void:
	if billboard_camera:
		_point_towards_target()
		
func _update_material_texture():
	if particles and point_cloud and highlighting:
		particles.texture = texture
		point_cloud.texture = texture
		highlighting.texture = texture
		await get_tree().create_timer(0.5).timeout
		particles.show()
			
		if texture == null:
			particles.hide()
			point_cloud.hide()
			highlighting.hide()
		else:
			particles.show()
			point_cloud.show()
		
func _update_target():
	if point_cloud:
		point_cloud.target = target
