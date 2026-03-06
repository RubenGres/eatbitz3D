@tool
extends MeshInstance3D

@export_range(0, 2) var rotation_speed: float = 0.1

signal rotation_completed

var _total_rotation: float = 0.0

func _ready() -> void:
	_total_rotation = 0.0

func _process(delta: float) -> void:
	var step = rotation_speed * delta * 10
	rotation.y += step
	_total_rotation += step

	if _total_rotation >= TAU:
		_total_rotation -= TAU
		rotation_completed.emit()
