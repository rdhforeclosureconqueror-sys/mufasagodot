extends Node3D

func _ready():
	# The original prototype room remains available below, but the runtime gym
	# is now built by the isolated GymEnvironment helper.
	pass

func create_light():
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 45, 0)
	add_child(light)

func create_floor():
	var floor_body = StaticBody3D.new()

	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(10, 1, 10)
	mesh.mesh = box
	mesh.position.y = -0.5
	floor_body.add_child(mesh)

	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(10, 1, 10)
	collision.shape = shape
	collision.position.y = -0.5
	floor_body.add_child(collision)

	add_child(floor_body)

func create_wall(pos: Vector3, size: Vector3):
	var wall = StaticBody3D.new()

	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = size
	mesh.mesh = box
	wall.add_child(mesh)

	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	wall.add_child(collision)

	wall.position = pos
	add_child(wall)
