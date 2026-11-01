class_name HydrologicBoard
extends Node3D
## Functional transparent channels: physical rims stay legible while water
## remains visible through the walls and the top of every raised obstacle.

var _steel := _material(Color("617b8a"), 0.65)
var _base := _material(Color("a7bac5"), 0.9)
var _rim := _material(Color("789eaf"), 0.65)
var _step := _material(Color("d58a52"), 0.85)
var _red := _material(Color("ec5448"), 0.6)
var _glass: StandardMaterial3D
var reservoir: Node3D
var gate_open_amount: float = 0.0
var _gate: Node3D
var _piston: MeshInstance3D
var _status: MeshInstance3D
var _closed_light: StandardMaterial3D
var _open_light: StandardMaterial3D
var _gate_base: float
var _gate_stroke: float
var _piston_top: float
var _piston_x: float
var _piston_z: float
var _batches: Dictionary = {}


static func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	return result


func _glass_material(alpha: float) -> StandardMaterial3D:
	var material := _material(Color(0.63, 0.81, 0.89, alpha), 0.24)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = 2
	return material


func build(level: LevelDefinition) -> void:
	_glass = _glass_material(0.07)
	_step.cull_mode = BaseMaterial3D.CULL_DISABLED
	var floors: Array[Material] = []
	for i: int in range(level.floor_regions.size()):
		floors.append(_material(Color("d7e6ea").lerp(Color("97bdce"), float(i) / 5.0), 0.85))
	for tile: Dictionary in level.terrain_tiles():
		var r: Rect2 = tile.bounds
		var y: float = tile.height
		if tile.channel:
			var material: Material = floors[0]
			for i: int in range(level.floor_regions.size()):
				if absf(level.elevation(i) - y) < 0.001: material = floors[i]
			var plate := _box(Vector3(r.size.x, 0.06, r.size.y), Vector3(r.get_center().x, y - 0.03, r.get_center().y), material)
			plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			_quad(Vector3(r.position.x, y, r.position.y), Vector3(r.end.x, y, r.position.y), Vector3(r.end.x, y, r.end.y), Vector3(r.position.x, y, r.end.y), Vector3.UP, _glass)
	for wall: PackedFloat32Array in level.wall_segments():
		var a := Vector2(wall[0], wall[1])
		var b := Vector2(wall[2], wall[3])
		var low := wall[4]
		var high := wall[5]
		if low <= level.base_height + 0.001: continue
		var midpoint := (a + b) * 0.5
		var normal := Vector2(-(b.y - a.y), b.x - a.x).normalized()
		if level.floor_height(midpoint + normal * 0.002) > level.floor_height(midpoint - normal * 0.002): normal = -normal
		var step := high < level.board_top - 0.001
		_quad(Vector3(a.x, low, a.y), Vector3(b.x, low, b.y), Vector3(b.x, high, b.y), Vector3(a.x, high, a.y), Vector3(normal.x, 0, normal.y), _step if step else _glass)
		var cap := _box(Vector3(a.distance_to(b), 0.016, 0.022), Vector3(midpoint.x, high + 0.009, midpoint.y), _step if step else _rim)
		cap.rotation.y = -atan2(b.y - a.y, b.x - a.x)
		cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_finish_mesh()
	var goal := level.goal
	var top := level.board_top + 0.026
	_box(Vector3(goal.size.x + 0.15, 0.04, 0.10), Vector3(goal.get_center().x, top, goal.end.y + 0.02), _red)
	for x: float in [goal.position.x - 0.02, goal.end.x + 0.02]:
		_box(Vector3(0.10, 0.04, goal.size.y), Vector3(x, top, goal.get_center().y), _red)
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
	terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(terrain)
	_batches.clear()


func _build_reservoir(level: LevelDefinition) -> void:
	reservoir = Node3D.new()
	add_child(reservoir)
	var r := level.reservoir_bounds
	var floor_y := level.elevation(0)
	var roof := level.board_top + 0.07
	var front := r.end.y
	var center_x := r.get_center().x
	var port_top := floor_y + 0.35
	_gate_stroke = port_top - floor_y + 0.05
	_gate_base = (port_top + floor_y) * 0.5
	_gate = Node3D.new()
	_gate.position = Vector3(center_x, _gate_base, front)
	reservoir.add_child(_gate)
	# A glazed sluice plate moves on two fixed guides into the upper housing.
	_box(Vector3(r.size.x - 0.06, port_top - floor_y, 0.045), Vector3.ZERO, _glass_material(0.20), _gate)
	for x: float in [-r.size.x * 0.5, r.size.x * 0.5]:
		_box(Vector3(0.05, port_top - floor_y, 0.07), Vector3(x, 0, 0.015), _steel, _gate)
	for y: float in [-(port_top - floor_y) * 0.5, (port_top - floor_y) * 0.5]:
		_box(Vector3(r.size.x + 0.04, 0.055, 0.07), Vector3(0, y, 0.02), _steel, _gate)
		for x: float in [-r.size.x * 0.44, r.size.x * 0.44]:
			var bolt := _cylinder(0.022, 0.018, Vector3(x, y, 0.063), _base, _gate)
			bolt.rotation.x = PI * 0.5
	for x: float in [r.position.x - 0.06, r.end.x + 0.06]:
		_box(Vector3(0.08, _gate_stroke * 2 + 0.1, 0.10), Vector3(x, floor_y + _gate_stroke, front + 0.025), _steel, reservoir)
	_box(Vector3(r.size.x, roof - port_top, 0.045), Vector3(center_x, (roof + port_top) * 0.5, front), _glass, reservoir)
	_box(Vector3(r.size.x, 0.04, r.size.y), Vector3(center_x, roof + 0.02, r.get_center().y), _glass, reservoir)
	for x: float in [r.position.x, r.end.x]:
		_box(Vector3(0.035, 0.04, r.size.y), Vector3(x, roof + 0.03, r.get_center().y), _rim, reservoir)
	_box(Vector3(r.size.x + 0.18, _gate_stroke + 0.16, 0.24), Vector3(center_x, port_top + _gate_stroke * 0.5 + 0.09, front + 0.04), _steel, reservoir)
	_piston_top = port_top + _gate_stroke + 0.20
	_piston_x = center_x
	_piston_z = front + 0.20
	_cylinder(0.10, 0.32, Vector3(center_x, _piston_top + 0.12, _piston_z), _steel, reservoir)
	_piston = _cylinder(0.036, 1.0, Vector3.ZERO, _base, reservoir)
	_closed_light = _material(Color("dba45d"), 0.35)
	_open_light = _material(Color("48b8b0"), 0.35)
	_status = _box(Vector3(0.09, 0.05, 0.03), Vector3(r.end.x - 0.10, port_top + _gate_stroke + 0.07, front + 0.17), _closed_light, reservoir)
	set_reservoir_open_amount(0)


func set_reservoir_open_amount(amount: float) -> void:
	gate_open_amount = clampf(amount, 0.0, 1.0)
	var eased := gate_open_amount * gate_open_amount * (3.0 - 2.0 * gate_open_amount)
	_gate.position.y = _gate_base + eased * _gate_stroke
	_gate.visible = gate_open_amount < 0.999
	var rod_bottom := _gate.position.y + _gate_stroke * 0.5
	var length := maxf(0.05, _piston_top - rod_bottom)
	_piston.position = Vector3(_piston_x, (rod_bottom + _piston_top) * 0.5, _piston_z)
	_piston.scale.y = length
	_status.material_override = _open_light if gate_open_amount >= 0.999 else _closed_light


func _box(size: Vector3, center: Vector3, material: Material, parent: Node = self) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	instance.mesh = shape
	instance.material_override = material
	instance.position = center
	parent.add_child(instance)
	return instance


func _cylinder(radius: float, height: float, center: Vector3, material: Material, parent: Node) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = 10
	instance.mesh = shape
	instance.material_override = material
	instance.position = center
	parent.add_child(instance)
	return instance
