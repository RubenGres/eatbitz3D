extends CanvasLayer

@onready var info_panel: InfoPanel = $"InfoPanel"
@onready var particle_parent = $"SubViewport/ParticleLocation"
@onready var object3D_parent = $"SubViewport/Object3DLocation"
@onready var camera3D = $SubViewport/Camera3D
@onready var blur_background = $BlurBakground
@onready var closeup = $ObjectCloseup

func _ready() -> void:
	info_panel.focused.connect(_on_node_focused)
	info_panel.closed.connect(_on_closed)
	blur_background.visible = false
	closeup.visible = false
	
func _on_node_focused(object: Node3D):
	var duplicate = object.duplicate()
	duplicate.position = Vector3.ZERO
	duplicate.scale = Vector3.ONE
	duplicate.rotation = Vector3.ZERO
	duplicate.target = camera3D
		
	for child in object3D_parent.get_children():
		child.queue_free()
		
	for child in particle_parent.get_children():
		child.queue_free()
	
	if duplicate is BitzCompanion:
		particle_parent.add_child(duplicate)
	else:
		duplicate.rotation_speed = 0.0
		object3D_parent.add_child(duplicate)
		
	blur_background.visible = true
	closeup.visible = true
	
func _on_closed():
	blur_background.visible = false
	closeup.visible = false
