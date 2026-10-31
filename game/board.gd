class_name HydrologicBoard
extends Node3D
## Only exposed terrain faces are drawn; no overlapping boxes at tile joins.

var _white := _material(Color("f8fbfc"), 0.82)
var _side := _material(Color("c8d9e0"), 0.9)
var _red := _material(Color("ef493f"), 0.55)
var _rim := _material(Color("83bfcc"), 0.72)
var _step := _material(Color("d98d62"), 0.85)
var reservoir: Node3D
var _gate: MeshInstance3D
var _lid: MeshInstance3D
var _gate_y: float
var _lid_z: float
var _batches: Dictionary = {}


static func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	return result


func build(level: LevelDefinition) -> void:
	var bounds := level.board_bounds
	var middle := bounds.get_center()
	_box(Vector3(bounds.size.x + 0.10, 0.12, bounds.size.y + 0.10), Vector3(middle.x, level.base_height - 0.06, middle.y), _material(Color("bbcdd4"), 0.9))
	var floors: Array[Material] = []
	for i: int in range(level.floor_regions.size()):
		floors.append(_material(Color("e2eff2").lerp(Color("b6d2dd"), float(i) / 5.0), 0.85))
	for tile: Dictionary in level.terrain_tiles():
		var r: Rect2 = tile.bounds
		var y: float = tile.height
		var material: Material = _white
		if tile.channel:
			for i: int in range(level.floor_regions.size()):
				if absf(level.elevation(i) - y) < 0.001: material = floors[i]
		_quad(Vector3(r.position.x, y, r.position.y), Vector3(r.end.x, y, r.position.y), Vector3(r.end.x, y, r.end.y), Vector3(r.position.x, y, r.end.y), Vector3.UP, material)
	for wall: PackedFloat32Array in level.wall_segments():
		var a := Vector2(wall[0], wall[1])
		var b := Vector2(wall[2], wall[3])
		var low := wall[4]
		var high := wall[5]
		var midpoint := (a + b) * 0.5
		var normal := Vector2(-(b.y - a.y), b.x - a.x).normalized()
		if level.floor_height(midpoint + normal * 0.002) > level.floor_height(midpoint - normal * 0.002): normal = -normal
		var step := high < level.board_top - 0.001 and low > level.base_height + 0.001
		_quad(Vector3(a.x, low, a.y), Vector3(b.x, low, b.y), Vector3(b.x, high, b.y), Vector3(a.x, high, a.y), Vector3(normal.x, 0, normal.y), _step if step else _side)
		# Narrow physical caps reveal actual heights without relying on shadows.
		if low > level.base_height + 0.001:
			var cap := _box(Vector3(a.distance_to(b), 0.018, 0.035), Vector3(midpoint.x, high + 0.01, midpoint.y), _step if step else _rim)
			cap.rotation.y = -atan2(b.y - a.y, b.x - a.x)
			cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_finish_mesh()
	var goal := level.goal
	var top := level.board_top + 0.026
	_box(Vector3(goal.size.x + 0.15, 0.045, 0.12), Vector3(goal.get_center().x, top, goal.end.y + 0.02), _red)
	for x: float in [goal.position.x - 0.02, goal.end.x + 0.02]:
		_box(Vector3(0.12, 0.045, goal.size.y), Vector3(x, top, goal.get_center().y), _red)
	_build_reservoir(level)


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, material: Material) -> void:
	if not _batches.has(material):
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		builder.set_material(material)
		_batches[material] = builder
	var surface: SurfaceTool = _batches[material]
	var points: Array[Vector3] = [a, b, c, a, c, d]
	if (b - a).cross(c - a).dot(normal) > 0.0: points = [a, c, b, a, d, c]
	for point: Vector3 in points:
		surface.set_normal(normal)
		surface.add_vertex(point)


func _finish_mesh() -> void:
	var mesh := ArrayMesh.new()
	for builder: SurfaceTool in _batches.values(): builder.commit(mesh)
	var terrain := MeshInstance3D.new()
	terrain.mesh = mesh
	add_child(terrain)
	_batches.clear()


func _build_reservoir(level: LevelDefinition) -> void:
	reservoir = Node3D.new()
	add_child(reservoir)
	var channel := level.floor_regions[0]
	var front := level.spawn.end.y + 0.12
	var back := channel.position.y
	var floor_y := level.elevation(0)
	var top := level.board_top + 0.04
	var center_x := channel.get_center().x
	var glass := _material(Color(0.25, 0.75, 0.86, 0.21), 0.18)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	_gate_y = (floor_y + top) * 0.5
	_gate = _box(Vector3(channel.size.x, top - floor_y, 0.045), Vector3(center_x, _gate_y, front), glass, reservoir)
	_gate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lid_z = (front + back) * 0.5
	_lid = _box(Vector3(channel.size.x, 0.025, front - back), Vector3(center_x, top, _lid_z), glass, reservoir)
	_lid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rail := _box(Vector3(channel.size.x + 0.06, 0.055, 0.06), Vector3(center_x, top, front), _rim, _gate)
	# Child coordinates are relative to the moving gate.
	rail.position -= _gate.position
	var handle := _box(Vector3(0.35, 0.07, 0.07), Vector3(center_x, _gate_y, front + 0.04), _white, _gate)
	handle.position -= _gate.position
	set_reservoir_open_amount(0.0)


func set_reservoir_open_amount(amount: float) -> void:
	reservoir.visible = amount < 1.0
	_gate.position.y = _gate_y + amount * 0.7
	_lid.position.z = _lid_z - amount * 2.3


func _box(size: Vector3, center: Vector3, material: Material, parent: Node = self) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	instance.mesh = shape
	instance.material_override = material
	instance.position = center
	parent.add_child(instance)
	return instance
