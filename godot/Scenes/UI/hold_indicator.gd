extends Control
class_name HoldIndicator

const RADIUS := 26.0
const THICKNESS := 4.0
const BG_COLOR := Color(1, 1, 1, 0.18)
const FG_COLOR := Color(1, 1, 1, 0.95)
const SEGMENTS := 48

var progress: float = 0.0:
	set(value):
		progress = clamp(value, 0.0, 1.0)
		queue_redraw()

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	size = Vector2(RADIUS * 2.0 + THICKNESS, RADIUS * 2.0 + THICKNESS)
	pivot_offset = size / 2.0
	visible = false

func show_at(screen_pos: Vector2) -> void:
	position = screen_pos - size / 2.0
	progress = 0.0
	visible = true

func hide_indicator() -> void:
	visible = false
	progress = 0.0

func _draw() -> void:
	var center = size / 2.0
	draw_arc(center, RADIUS, 0.0, TAU, SEGMENTS, BG_COLOR, THICKNESS, true)
	if progress > 0.0:
		var start_angle := -PI / 2.0
		var end_angle := start_angle + TAU * progress
		var seg_count := max(2, int(SEGMENTS * progress))
		draw_arc(center, RADIUS, start_angle, end_angle, seg_count, FG_COLOR, THICKNESS, true)
