extends CanvasLayer

@onready var info_panel: InfoPanel = $"InfoPanel"
@onready var particle_parent = $"SubViewport/InspectNodeParent/ParticleLocation"
@onready var object3D_parent = $"SubViewport/InspectNodeParent/Object3DLocation"
@onready var inspect_node_parent: Node3D = $"SubViewport/InspectNodeParent"
@onready var camera3D = $SubViewport/Camera3D
@onready var blur_background = $BlurBakground
@onready var closeup = $ObjectCloseup
@onready var start_capture_overlay = $StartCaptureOverlay
@onready var capture_button: Button = $StartCaptureOverlay/CaptureButton
@onready var reticle = $Reticle

const INSPECT_MAX_TILT_X_DEG := 15.0
const INSPECT_MAX_TILT_Y_DEG := 15.0
const INSPECT_TILT_SMOOTH_SPEED := 6.0

func _ready() -> void:
	info_panel.focused.connect(_on_node_focused)
	info_panel.closed.connect(_on_closed)
	capture_button.pressed.connect(_on_capture_button_pressed)
	blur_background.visible = false
	closeup.visible = false
	reticle.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	start_capture_overlay.visible = true

func _on_capture_button_pressed() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	reticle.visible = true
	start_capture_overlay.visible = false

func _process(delta: float) -> void:
	var closeup_rect = closeup.get_global_rect()
	var mouse_pos := get_viewport().get_mouse_position()
	var is_hovering_closeup = closeup.visible and closeup_rect.has_point(mouse_pos)

	var target_tilt_x_deg := 0.0
	var target_tilt_y_deg := 0.0

	if is_hovering_closeup:
		var normalized_x = (
			(mouse_pos.x - closeup_rect.position.x) / closeup_rect.size.x
		) * 2.0 - 1.0
		var normalized_y = (
			(mouse_pos.y - closeup_rect.position.y) / closeup_rect.size.y
		) * 2.0 - 1.0
		target_tilt_y_deg = clamp(normalized_x, -1.0, 1.0) * INSPECT_MAX_TILT_Y_DEG
		target_tilt_x_deg = clamp(normalized_y, -1.0, 1.0) * INSPECT_MAX_TILT_X_DEG

	var target_basis = camera3D.global_transform.basis
	target_basis = target_basis * Basis(Vector3.RIGHT, deg_to_rad(target_tilt_x_deg))
	target_basis = target_basis * Basis(Vector3.UP, deg_to_rad(target_tilt_y_deg))

	var current_quat = inspect_node_parent.global_transform.basis.get_rotation_quaternion()
	var target_quat = target_basis.orthonormalized().get_rotation_quaternion()
	var blend = clamp(delta * INSPECT_TILT_SMOOTH_SPEED, 0.0, 1.0)
	var next_quat := current_quat.slerp(target_quat, blend)
	inspect_node_parent.global_transform.basis = Basis(next_quat)
	
func _on_node_focused(object: Node3D):
	for child in object3D_parent.get_children():
		child.queue_free()
		
	for child in particle_parent.get_children():
		child.queue_free()
	
	var duplicate = object.duplicate()
	
	if duplicate is BitzCompanion:
		object3D_parent.add_child(duplicate)
		duplicate.billboard_camera = false
	else:
		particle_parent.add_child(duplicate)
		
	duplicate.position = Vector3.ZERO
	duplicate.scale = Vector3.ONE
	duplicate.rotation = Vector3.ZERO
	duplicate.target = null
	duplicate.is_highlighted = false

	blur_background.visible = true
	closeup.visible = true
	
func _on_closed():
	blur_background.visible = false
	closeup.visible = false
