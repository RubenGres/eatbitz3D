@tool
extends Sprite3D


@export var rotation_speed: float = 1.0

func _process(delta: float) -> void:
	self.rotation.z += rotation_speed
