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
	_box(Vector3(bounds.size.x + 0.10, 0.12, bounds.size.y + 0.10), Vector3(middle.x, level.base_height - 0.06, middle.y), _material(Color("b3c4c7"), 0.9))
	for tile: Dictionary in level.terrain_tiles():
		var rectangle: Rect2 = tile.bounds
		var center := rectangle.get_center()
		var height: float = tile.height
		_box(Vector3(rectangle.size.x, height - level.base_height, rectangle.size.y), Vector3(center.x, (height + level.base_height) * 0.5, center.y), _white)
		if tile.channel:
			_box(Vector3(rectangle.size.x, 0.008, rectangle.size.y), Vector3(center.x, height + 0.004, center.y), _floor)
	var goal := level.goal
	var top := level.board_top + 0.02
	_box(Vector3(goal.size.x + 0.15, 0.045, 0.12), Vector3(goal.get_center().x, top, goal.end.y + 0.02), _red)
	for x: float in [goal.position.x - 0.02, goal.end.x + 0.02]:
		_box(Vector3(0.12, 0.045, goal.size.y), Vector3(x, top, goal.get_center().y), _red)
	_box(Vector3(0.045, 0.012, 0.65), Vector3(bounds.position.x + 0.12, level.board_top + 0.009, -3.7), _material(Color("299ec2"), 0.6))


func _box(size: Vector3, center: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	instance.mesh = shape
	instance.material_override = material
	instance.position = center
	add_child(instance)
	return instance
