@tool
extends Node3D

@onready var particles = $GPUParticles3D
@onready var point_cloud = $PointCloudObject

@export_range(0.0, 2, 0.001) var orbit_distance: float = 1.0
@export_range(0.0, 1.0, 0.001) var orbit_multiplier: float = 1.0
@export var rotation_speed: float = 1.0

var accumulated_time: float = 0.0
var rotation_seed: float = RandomNumberGenerator.new().randf()
var orbital_inclination: float = 0.0  # Angle in radians to tilt the orbit
var orbital_shift_rate : float = 0.01
var initial_offset: Vector3
var initial_scale: Vector3
var time_offset: float

@export var texture: Texture2D:
	set(value):
		texture = value
		_update_material_texture()

@export var target_3D: Node3D:
	set(value):
		target_3D = value
		_update_target_3D()

func _ready() -> void:
	# Store initial offset from parent
	initial_offset = position
	initial_scale = self.scale
	
	# Set orbit distance from initial distance if not manually set
	if orbit_distance == 0.0:
		orbit_distance = initial_offset.length()
	
	# Use seed to create time offset for orbit variation
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(rotation_seed)
	time_offset = rng.randf_range(0.0, TAU)
	
	_update_material_texture()
	_update_target_3D()
	
	self.orbital_inclination = rotation_seed * 2 * PI

func _point_towards_target():
	if not target_3D:
		return
	
	var direction = global_position - target_3D.global_position
	if direction.length() > 0.001:
		look_at(global_position + direction, Vector3.UP)

func _process(delta: float) -> void:
	_point_towards_target()
	
	if Engine.is_editor_hint():
		return
	
	# Accumulate time using delta (respects Engine.time_scale)
	accumulated_time += delta
	var angle = (accumulated_time + time_offset) * rotation_speed + rotation_seed
	
	self.orbital_inclination += orbital_shift_rate * delta
	self.orbital_inclination = fmod(orbital_inclination, 2.0 * PI)
	
	self.scale = initial_scale * orbit_multiplier
	
	if orbit_distance == 0.0:
		position = Vector3.ZERO
	else:
		# Start with flat orbit
		var orbit_pos = Vector3(
			cos(angle) * orbit_distance * orbit_multiplier,
			0.0,
			sin(angle) * orbit_distance * orbit_multiplier
		)
		
		# Apply orbital inclination (rotate around X axis)
		orbit_pos = orbit_pos.rotated(Vector3.RIGHT, orbital_inclination)
		
		position = orbit_pos
	
func _update_material_texture():
	if particles and point_cloud:
		particles.texture = texture
		point_cloud.texture = texture

func _update_target_3D():
	if point_cloud:
		point_cloud.target_3D = target_3D
