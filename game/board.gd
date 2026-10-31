class_name HydrologicBoard
extends Node3D

var _white := _material(Color("fafcfa"), 0.82)
var _floor := _material(Color("d8e2e4"), 0.65)
var _red := _material(Color("ef493f"), 0.55)


static func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	return result


func build(level: LevelDefinition) -> void:
	var bounds := level.board_bounds
	var middle := bounds.get_center()
	_box(Vector3(bounds.size.x + 0.10, 0.14, bounds.size.y + 0.10), Vector3(middle.x, -0.46, middle.y), _material(Color("b3c4c7"), 0.9))
	_box(Vector3(bounds.size.x, 0.40, bounds.size.y), Vector3(middle.x, -0.25, middle.y), _white)
	_floor_polygon(level.outline, 0.005, _floor)
	for i: int in range(level.outline.size()):
		var a := level.outline[i]
		var b := level.outline[(i + 1) % level.outline.size()]
		var center := (a + b) * 0.5
		var wall := _box(Vector3(a.distance_to(b) + 0.10, 0.30, 0.10), Vector3(center.x, 0.15, center.y), _white)
		wall.rotation.y = -atan2(b.y - a.y, b.x - a.x)
	# The vessel is part of the board: red rails and an end cap, no HUD labels.
	var goal := level.goal
	_box(Vector3(goal.size.x + 0.16, 0.045, 0.13), Vector3(goal.get_center().x, 0.323, goal.end.y + 0.02), _red)
	for x: float in [goal.position.x - 0.02, goal.end.x + 0.02]:
		_box(Vector3(0.13, 0.045, goal.size.y), Vector3(x, 0.323, goal.get_center().y), _red)
	# A few quiet architectural joints; nothing intrudes into the channel.
	for z: float in [-3.0, -1.0, 1.0, 3.0]:
		_box(Vector3(0.20, 0.008, 0.012), Vector3(bounds.position.x + 0.13, -0.044, z), _floor)
	_box(Vector3(0.045, 0.012, 0.65), Vector3(bounds.position.x + 0.12, -0.04, -3.7), _material(Color("299ec2"), 0.6))


func _box(size: Vector3, center: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	instance.mesh = shape
	instance.material_override = material
	instance.position = center
	add_child(instance)
	return instance


func _floor_polygon(polygon: PackedVector2Array, height: float, material: Material) -> void:
	var indices := Geometry2D.triangulate_polygon(polygon)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(material)
	for i: int in indices:
		surface.set_normal(Vector3.UP)
		surface.add_vertex(Vector3(polygon[i].x, height, polygon[i].y))
	var instance := MeshInstance3D.new()
	instance.mesh = surface.commit()
	# Both sides render: polygon conventions must not hide the basin on GLES.
	var two_sided := material.duplicate() as StandardMaterial3D
	two_sided.cull_mode = BaseMaterial3D.CULL_DISABLED
	instance.material_override = two_sided
	add_child(instance)
