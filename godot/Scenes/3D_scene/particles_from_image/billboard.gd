@tool
extends Node3D

@onready var particles = $GPUParticles3D
@onready var point_cloud = $PointCloudObject

@export var wiggle_position: bool = false
@export var timestep_ms: int = 10
@export_range(0, 5, 0.01) var wiggle_speed: float = 1.0
@export_range(0, 5, 0.01) var wiggle_range: float = 1.0


var rng = RandomNumberGenerator.new()
var target_pos: Vector3 = self.position

@export var texture: Texture2D:
	set(value):
		texture = value
		_update_material_texture()

@export var target_3D: Node3D:
	set(value):
		target_3D = value
		_update_target_3D()

func _ready() -> void:
	_update_material_texture()
	_update_target_3D()

func _process(delta: float) -> void:
	if not target_3D:
		return
	
	# Point Z+ towards target by looking away from it
	var direction = global_position - target_3D.global_position
	if direction.length() > 0.001:
		look_at(global_position + direction, Vector3.UP)
	
	if wiggle_position:
		if Time.get_ticks_msec() % timestep_ms == 0:
			target_pos = position + (Vector3(rng.randf(), rng.randf(), rng.randf()) * 2 - Vector3.ONE) * wiggle_range

		self.position = position.lerp(target_pos, wiggle_speed * delta)

func _update_material_texture():
	if particles and point_cloud:
		particles.texture = texture
		point_cloud.texture = texture

func _update_target_3D():
	if point_cloud:
		point_cloud.target_3D = target_3D
