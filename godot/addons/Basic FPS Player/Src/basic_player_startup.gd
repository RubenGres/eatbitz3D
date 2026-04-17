@tool
extends CharacterBody3D

var BasicFPSPlayerScene : PackedScene = preload("basic_player_head.tscn")
var addedHead = false

func _enter_tree():
	
	if find_child("Head"):
		addedHead = true
	
	if Engine.is_editor_hint() && !addedHead:
		var s = BasicFPSPlayerScene.instantiate()
		add_child(s)
		s.owner = get_tree().edited_scene_root
		addedHead = true

## PLAYER MOVMENT SCRIPT ##
###########################

@export_category("Movement")
@export_subgroup("Settings")
@export var SPEED := 5.0
@export var ACCEL := 50.0
@export var IN_AIR_SPEED := 3.0
@export var IN_AIR_ACCEL := 5.0
@export var JUMP_VELOCITY := 4.5
@export_subgroup("Head Bob")
@export var HEAD_BOB := true
@export var HEAD_BOB_FREQUENCY := 0.3
@export var HEAD_BOB_AMPLITUDE := 0.01
@export_subgroup("Clamp Head Rotation")
@export var CLAMP_HEAD_ROTATION := true
@export var CLAMP_HEAD_ROTATION_MIN := -90.0
@export var CLAMP_HEAD_ROTATION_MAX := 90.0

@export_category("Key Binds")
@export_subgroup("Mouse")
@export var MOUSE_ACCEL := true
@export var KEY_BIND_MOUSE_SENS := 0.005
@export var KEY_BIND_MOUSE_ACCEL := 50
@export_subgroup("Movement")
@export var KEY_BIND_UP := "ui_up"
@export var KEY_BIND_LEFT := "ui_left"
@export var KEY_BIND_RIGHT := "ui_right"
@export var KEY_BIND_DOWN := "ui_down"
@export var KEY_BIND_JUMP := "ui_accept"

@export_category("Gyroscope (Mobile)")
@export var GYRO_ENABLED := true
@export var GYRO_SENSITIVITY := 1.0
## Minimum angular velocity (rad/s) to register as intentional movement
@export var GYRO_DEADZONE := 0.05

@export_category("Advanced")
@export var UPDATE_PLAYER_ON_PHYS_STEP := true	# When check player is moved and rotated in _physics_process (fixed fps)
												# Otherwise player is updated in _process (uncapped)

@export_category("Edge Rotation")
@export var EDGE_ZONE := 0.40
@export var EDGE_ROTATION_SPEED := 1.0

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
# To keep track of current speed and acceleration
var speed = SPEED
var accel = ACCEL

# Used when lerping rotation to reduce stuttering when moving the mouse
var rotation_target_player : float
var rotation_target_head : float

var drag_look_active := false
var _touch_device := false
var _gyro_active := false
var sensitivity_scale := 0.12

var edge_rotation_active := false
var edge_direction := Vector2.ZERO
var edge_intensity := 0.0
var _mouse_in_window := true

# Used when bobing head
var head_start_pos : Vector3

# Current player tick, used in head bob calculation
var tick = 0

func _ready():
	if Engine.is_editor_hint():
		return

	_touch_device = DisplayServer.is_touchscreen_available()

	head_start_pos = $Head.position

	get_viewport().mouse_entered.connect(func(): _mouse_in_window = true)
	get_viewport().mouse_exited.connect(func(): _mouse_in_window = false)

func _physics_process(delta):
	if Engine.is_editor_hint():
		return
	
	tick += 1
	
	if _gyro_active:
		_apply_gyroscope(delta)
	
	rotate_player(delta)

func _process(delta):
	if Engine.is_editor_hint():
		return
	if edge_rotation_active:
		_apply_edge_rotation(delta)

func _input(event):
	if Engine.is_editor_hint():
		return

	if event is InputEventScreenTouch:
		drag_look_active = event.pressed
		return

	if event is InputEventScreenDrag:
		set_rotation_target(-event.relative)
		return

	if edge_rotation_active:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		drag_look_active = event.pressed
		return

	if event is InputEventMouseMotion:
		set_rotation_target(event.relative)

func set_rotation_target(mouse_motion : Vector2):
	# Add player target to the mouse -x input
	rotation_target_player += -mouse_motion.x * KEY_BIND_MOUSE_SENS * sensitivity_scale
	# Add head target to the mouse -y input
	rotation_target_head += -mouse_motion.y * KEY_BIND_MOUSE_SENS * sensitivity_scale
	# Clamp rotation
	if CLAMP_HEAD_ROTATION:
		rotation_target_head = clamp(rotation_target_head, deg_to_rad(CLAMP_HEAD_ROTATION_MIN), deg_to_rad(CLAMP_HEAD_ROTATION_MAX))
	
func rotate_player(delta):
	if MOUSE_ACCEL:
		quaternion = quaternion.slerp(Quaternion(Vector3.UP, rotation_target_player), KEY_BIND_MOUSE_ACCEL * delta)
		$Head.quaternion = $Head.quaternion.slerp(Quaternion(Vector3.RIGHT, rotation_target_head), KEY_BIND_MOUSE_ACCEL * delta)
	else:
		quaternion = Quaternion(Vector3.UP, rotation_target_player)
		$Head.quaternion = Quaternion(Vector3.RIGHT, rotation_target_head)

func set_gyro_active(active: bool) -> void:
	_gyro_active = true
	#active and _touch_device and GYRO_ENABLED

func _apply_gyroscope(delta: float) -> void:
	var gyro := Input.get_gyroscope()
	if gyro.length_squared() < GYRO_DEADZONE * GYRO_DEADZONE:
		return

	# gyro.y = yaw rate (turn left/right), gyro.x = pitch rate (look up/down)
	rotation_target_player -= gyro.y * GYRO_SENSITIVITY * delta
	rotation_target_head += gyro.x * GYRO_SENSITIVITY * delta

	if CLAMP_HEAD_ROTATION:
		rotation_target_head = clamp(
			rotation_target_head,
			deg_to_rad(CLAMP_HEAD_ROTATION_MIN),
			deg_to_rad(CLAMP_HEAD_ROTATION_MAX)
		)

func set_edge_rotation_active(active: bool) -> void:
	edge_rotation_active = active
	if not active:
		edge_direction = Vector2.ZERO
		edge_intensity = 0.0
		drag_look_active = false

func _apply_edge_rotation(delta: float) -> void:
	if not _mouse_in_window:
		edge_direction = Vector2.ZERO
		edge_intensity = 0.0
		return

	var vp = get_viewport()
	var mouse_pos = vp.get_mouse_position()
	var vp_size = vp.get_visible_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		edge_direction = Vector2.ZERO
		edge_intensity = 0.0
		return

	var norm_x = mouse_pos.x / vp_size.x
	var norm_y = mouse_pos.y / vp_size.y
	var ex := 0.0
	var ey := 0.0

	if norm_x < EDGE_ZONE:
		ex = -smoothstep(EDGE_ZONE, 0.0, norm_x)
	elif norm_x > 1.0 - EDGE_ZONE:
		ex = smoothstep(1.0 - EDGE_ZONE, 1.0, norm_x)

	if norm_y < EDGE_ZONE:
		ey = -smoothstep(EDGE_ZONE, 0.0, norm_y)
	elif norm_y > 1.0 - EDGE_ZONE:
		ey = smoothstep(1.0 - EDGE_ZONE, 1.0, norm_y)

	edge_direction = Vector2(ex, ey)
	edge_intensity = clamp(edge_direction.length(), 0.0, 1.0)

	rotation_target_player += -ex * EDGE_ROTATION_SPEED * delta
	rotation_target_head += -ey * EDGE_ROTATION_SPEED * delta

	if CLAMP_HEAD_ROTATION:
		rotation_target_head = clamp(
			rotation_target_head,
			deg_to_rad(CLAMP_HEAD_ROTATION_MIN),
			deg_to_rad(CLAMP_HEAD_ROTATION_MAX)
		)
