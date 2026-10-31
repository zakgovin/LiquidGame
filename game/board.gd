class_name HydrologicBoard
extends Node3D

var _white := _material(Color("fafcfa"), 0.82)
var _floor := _material(Color("d8e2e4"), 0.65)
var _red := _material(Color("ef493f"), 0.55)
var _ink := _material(Color("596d75"), 0.8)


static func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	return result


func build(level: LevelDefinition) -> void:
	_box(Vector3(7.35, 0.16, 9.4), Vector3(0, -0.48, 0), _material(Color("b3c4c7"), 0.9))
	_box(Vector3(7.2, 0.42, 9.2), Vector3(0, -0.25, 0), _white)
	_floor_polygon(level.outline, 0.005, _floor)
	for i: int in range(level.outline.size()):
		var a := level.outline[i]
		var b := level.outline[(i + 1) % level.outline.size()]
		var center := (a + b) * 0.5
		var length := a.distance_to(b)
		var wall := _box(Vector3(length + 0.11, 0.40, 0.11), Vector3(center.x, 0.20, center.y), _white)
		wall.rotation.y = -atan2(b.y - a.y, b.x - a.x)
	# The target is a physical basin, marked in vermilion rather than a floating icon.
	_box(Vector3(2.7, 0.055, 0.15), Vector3(1.8, 0.423, 4.0), _red)
	_box(Vector3(0.15, 0.055, 2.5), Vector3(3.1, 0.423, 2.75), _red)
	_box(Vector3(0.15, 0.055, 1.8), Vector3(0.5, 0.423, 3.15), _red)
	# Original architectural forms: no borrowed Mirror's Edge assets.
	_box(Vector3(2.3, 0.38, 2.1), Vector3(1.6, 0.15, -2.85), _white)
	_box(Vector3(0.55, 0.95, 1.55), Vector3(0.65, 0.47, -3.0), _white)
	_box(Vector3(1.45, 0.16, 0.8), Vector3(1.95, 0.42, -3.2), _white)
	_box(Vector3(0.07, 0.015, 1.25), Vector3(0.96, 0.64, -3.0), _red)
	for x: float in [1.35, 1.55, 1.75]:
		_box(Vector3(0.075, 0.018, 0.52), Vector3(x, 0.515, -3.2), _ink)
	_box(Vector3(2.15, 0.18, 0.58), Vector3(1.65, 0.05, -1.1), _white)
	for z: float in [-1.26, -1.1, -0.94]:
		_box(Vector3(1.8, 0.025, 0.035), Vector3(1.65, 0.155, z), _floor)
	_label("H / 01", Vector3(1.8, 0.015, -0.15), 55, Color("9aaeb3"))
	_label("ИСТОК", Vector3(-1.5, 0.015, -4.32), 23, Color("718a91"))
	_label("ПРИЁМНИК / 80%", Vector3(1.75, 0.015, 4.32), 20, Color("bd493e"))
	_arrow(Vector2(-1.5, -0.40), Vector2.DOWN)
	_arrow(Vector2(-0.05, 1.40), Vector2.RIGHT)
	_arrow(Vector2(1.65, 1.96), Vector2.DOWN)
	# Floor joints convey scale while leaving the fluid path visually clean.
	for z: float in [-3.4, -1.0, 1.4, 3.6]:
		_box(Vector3(0.3, 0.01, 0.015), Vector3(-3.28, -0.032, z), _floor)
	_box(Vector3(0.06, 0.015, 0.8), Vector3(-3.3, -0.028, -3.6), _red)


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


func _label(text: String, center: Vector3, font_size: int, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = preload("res://assets/fonts/NotoSans-Bold.ttf")
	label.font_size = font_size
	label.pixel_size = 0.007
	label.modulate = color
	label.outline_size = 0
	label.rotation.x = -PI / 2.0
	label.position = center
	add_child(label)


func _arrow(center: Vector2, direction: Vector2) -> void:
	var normal := Vector2(-direction.y, direction.x)
	var polygon := PackedVector2Array([
		center + direction * 0.2,
		center - direction * 0.12 + normal * 0.14,
		center - direction * 0.04,
		center - direction * 0.12 - normal * 0.14])
	_floor_polygon(polygon, 0.016, _material(Color("a1b8bf"), 0.8))
