extends Node3D

func _ready() -> void:
	get_tree().root.size = Vector2(3840, 1920) # 360 video resolution

# for movie making, only record one loop
func _on_global_species_view_rotation_completed() -> void:
	get_tree().quit()
