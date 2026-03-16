extends Node3D

var _loop_count: int = 0
var _max_loops: int = 5
var _timer: Timer

func _ready() -> void:
	get_tree().root.size = Vector2(3840, 1920)
	
	_timer = Timer.new()
	_timer.wait_time = 300.0 # 5 minutes
	_timer.one_shot = true
	_timer.timeout.connect(_quit)
	add_child(_timer)
	_timer.start()

func _on_global_species_view_rotation_completed() -> void:
	_loop_count += 1
	if _loop_count >= _max_loops:
		_quit()

func _quit() -> void:
	get_tree().quit()
