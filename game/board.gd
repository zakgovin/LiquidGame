class_name HydrologicBoard
extends Node3D
## Functional transparent channels: physical rims stay legible while water
## remains visible through the walls and the top of every raised obstacle.

var _steel := _material(Color("617b8a"), 0.65)
var _base := _material(Color("a7bac5"), 0.9)
var _rim := _material(Color("789eaf"), 0.65)
var _step := ShaderMaterial.new()
var _red := _material(Color("ec5448"), 0.6)
var _glass: ShaderMaterial
var reservoir: Node3D
var gate_open_amount: float = 0.0
var _gate: Node3D
var _lid_closed: Vector3
var _status: MeshInstance3D
var _closed_light: StandardMaterial3D
var _open_light: StandardMaterial3D
var hazard_edges: Array[MeshInstance3D] = []
var _batches: Dictionary = {}


static func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	return result


func _glass_material(alpha: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/materials/glass.gdshader")
	material.set_shader_parameter("face_opacity", alpha)
	material.render_priority = 2
	return material


func build(level: LevelDefinition) -> void:
	_glass = _glass_material(0.22)
	_step.shader = preload("res://assets/materials/hazard.gdshader")
	var floors: Array[Material] = []
	for i: int in range(level.floor_regions.size()):
		floors.append(_material(Color("e1e7e5").lerp(Color("b5c3c2"), float(i) / 5.0), 0.85))
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
		var cap := _box(Vector3(a.distance_to(b), 0.025 if step else 0.04, 0.12 if step else 0.055), Vector3(midpoint.x, high + 0.009, midpoint.y), _step if step else _rim)
		cap.rotation.y = -atan2(b.y - a.y, b.x - a.x)
		cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if step: hazard_edges.append(cap)
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
	_gate = Node3D.new()
	_gate.name = "ReleaseLid"
	_lid_closed = Vector3(center_x, (port_top + floor_y) * 0.5, front + 0.025)
	_gate.position = _lid_closed
	reservoir.add_child(_gate)
	# A sealed removable outlet cover is kicked clear, then tumbles away.
	_box(Vector3(r.size.x - 0.06, port_top - floor_y, 0.07), Vector3.ZERO, _glass_material(0.30), _gate)
	for x: float in [-r.size.x * 0.5, r.size.x * 0.5]:
		_box(Vector3(0.06, port_top - floor_y + 0.06, 0.10), Vector3(x, 0, 0.01), _steel, _gate)
	for y: float in [-(port_top - floor_y) * 0.5, (port_top - floor_y) * 0.5]:
		_box(Vector3(r.size.x + 0.06, 0.06, 0.10), Vector3(0, y, 0.015), _steel, _gate)
		for x: float in [-r.size.x * 0.43, r.size.x * 0.43]:
			var bolt := _cylinder(0.026, 0.022, Vector3(x, y, 0.08), _base, _gate)
			bolt.rotation.x = PI * 0.5
	# The fixed collar and two clamps make the sealed opening readable.
	for x: float in [r.position.x - 0.055, r.end.x + 0.055]:
		_box(Vector3(0.075, port_top - floor_y + 0.17, 0.12), Vector3(x, (port_top + floor_y) * 0.5, front), _rim, reservoir)
		_box(Vector3(0.14, 0.11, 0.14), Vector3(x, port_top - 0.04, front + 0.045), _steel, reservoir)
	_box(Vector3(r.size.x + 0.12, 0.06, 0.12), Vector3(center_x, port_top + 0.045, front), _steel, reservoir)
	_box(Vector3(r.size.x, roof - port_top, 0.045), Vector3(center_x, (roof + port_top) * 0.5, front), _glass, reservoir)
	_box(Vector3(r.size.x, 0.04, r.size.y), Vector3(center_x, roof + 0.02, r.get_center().y), _glass, reservoir)
	for x: float in [r.position.x, r.end.x]:
		_box(Vector3(0.045, 0.04, r.size.y), Vector3(x, roof + 0.03, r.get_center().y), _rim, reservoir)
	_closed_light = _material(Color("dba45d"), 0.35)
	_open_light = _material(Color("48b8b0"), 0.35)
	_status = _box(Vector3(0.09, 0.045, 0.03), Vector3(r.end.x - 0.12, port_top + 0.047, front + 0.075), _closed_light, reservoir)
	set_reservoir_open_amount(0)


func set_reservoir_open_amount(amount: float) -> void:
	gate_open_amount = clampf(amount, 0.0, 1.0)
	var kick := smoothstep(0.0, 0.30, gate_open_amount)
	var flight := smoothstep(0.12, 1.0, gate_open_amount)
	_gate.position = _lid_closed + Vector3(-4.8 * flight, 2.2 * flight - 0.4 * flight * flight, 0.28 * kick + 0.5 * flight)
	_gate.rotation = Vector3(-2.8 * flight, 1.8 * flight, -2.1 * flight)
	_gate.visible = gate_open_amount < 0.999
	_status.material_override = _open_light if gate_open_amount >= 0.30 else _closed_light


func set_goal_complete(complete: bool) -> void:
	_red.albedo_color = Color("42bcb0") if complete else Color("ec5448")
	_red.emission_enabled = complete
	_red.emission = Color("197c71") if complete else Color.BLACK


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
