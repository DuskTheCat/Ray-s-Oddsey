extends Node2D

@onready var bone_1: Bone2D = $Skeleton2D/Bone2D
@onready var bone_2: Bone2D = $Skeleton2D/Bone2D/Bone2D
@onready var bone_3: Bone2D = $Skeleton2D/Bone2D/Bone2D/Bone2D

@onready var rigid_body_1: RigidBody2D = $RigidBody2D1
@onready var rigid_body_2: RigidBody2D = $RigidBody2D2
@onready var rigid_body_3: RigidBody2D = $RigidBody2D3

func _ready() -> void:
	# Configure PinJoints dynamically to link adjacent RigidBody physics nodes
	$RigidBody2D1/PinJoint2D.node_a = rigid_body_1.get_path()
	$RigidBody2D1/PinJoint2D.node_b = rigid_body_2.get_path()
	
	$RigidBody2D2/PinJoint2D.node_a = rigid_body_2.get_path()
	$RigidBody2D2/PinJoint2D.node_b = rigid_body_3.get_path()

func _process(_delta: float) -> void:
	# Synchronize bone transforms to match the physical rigid bodies
	sync_bone(bone_1, rigid_body_1)
	sync_bone(bone_2, rigid_body_2)
	sync_bone(bone_3, rigid_body_3)

func sync_bone(bone: Bone2D, body: RigidBody2D) -> void:
	bone.global_position = body.global_position
	bone.global_rotation = body.global_rotation
