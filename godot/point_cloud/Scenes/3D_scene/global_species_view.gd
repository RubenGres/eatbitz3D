@tool
extends Node3D

@export var target: Node3D:
	set(value):
		target = value
		if is_node_ready():
			if is_inside_tree():
				set_target()

func _ready():
	set_target()

func set_target():
	for node in get_tree().get_nodes_in_group("ingredients"):
		if node is Ingredient3D:
			node.target = self.target

	for node: BitzCompanion in $Companions.get_children():
		node.target_3D = self.target
