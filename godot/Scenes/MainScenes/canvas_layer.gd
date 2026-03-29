extends CanvasLayer

@onready var info_panel: InfoPanel = $"InfoPanel"
@onready var particle_parent = $"SubViewport/InspectNodeParent/ParticleLocation"
@onready var object3D_parent = $"SubViewport/InspectNodeParent/Object3DLocation"
@onready var inspect_node_parent: Node3D = $"SubViewport/InspectNodeParent"
@onready var camera3D = $SubViewport/Camera3D
@onready var blur_background = $BlurBakground
@onready var closeup = $ObjectCloseup
@onready var welcome_overlay = $WelcomeOverlay
@onready var explore_button: Button = %ExploreButton
@onready var reticle = $Reticle
@onready var credits_button: Button = %CreditsButton
@onready var credits_overlay: Control = $WelcomeOverlay/CreditsOverlay
@onready var credits_backdrop: ColorRect = $WelcomeOverlay/CreditsOverlay/Backdrop
@onready var back_button: Button = %BackButton

var _prev_mouse_mode: Input.MouseMode
var _prev_reticle_visible: bool

const INSPECT_MAX_TILT_X_DEG := 15.0
const INSPECT_MAX_TILT_Y_DEG := 15.0
const INSPECT_TILT_SMOOTH_SPEED := 6.0

func _ready() -> void:
	info_panel.focused.connect(_on_node_focused)
	info_panel.closed.connect(_on_closed)
	explore_button.pressed.connect(_on_explore_button_pressed)
	credits_button.pressed.connect(_on_credits_button_pressed)
	back_button.pressed.connect(_on_back_button_pressed)
	credits_backdrop.gui_input.connect(_on_credits_backdrop_input)
	blur_background.visible = false
	closeup.visible = false
	reticle.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	welcome_overlay.visible = true

	TranslationServer.set_locale("en")
	
func _on_explore_button_pressed() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	reticle.visible = true
	welcome_overlay.visible = false
	#DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

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
		duplicate.lifetime = 99999
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

func _on_credits_button_pressed() -> void:
	_prev_mouse_mode = Input.get_mouse_mode()
	_prev_reticle_visible = reticle.visible
	credits_overlay.visible = true
	credits_button.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	reticle.visible = false

func _on_credits_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close_credits()

func _on_back_button_pressed() -> void:
	_close_credits()

func _close_credits() -> void:
	credits_overlay.visible = false
	credits_button.visible = true
	Input.set_mouse_mode(_prev_mouse_mode)
	reticle.visible = _prev_reticle_visible
