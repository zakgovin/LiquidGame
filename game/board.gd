class_name HydrologicBoard
extends Node3D
## Functional transparent channels: physical rims stay legible while water
## remains visible through the walls and the top of every raised obstacle.

var _steel := _material(Color("657078"), 0.55)
var _base := _material(Color("abb3b0"), 0.9)
var _rim := _material(Color("78868a"), 0.55)
var foundation := _marble(Color("c2c9c6"))
var floor_materials: Array[ShaderMaterial] = []
var contact_material := ShaderMaterial.new()
var contact_bands: int = 0
var open_edges: int = 0
var bank_jambs: int = 0
var _slab_edge := _material(Color("919d99"), 0.85)
var _well := _material(Color("253139"), 0.95)
var _lowest_floor: float = 0.0
var _step := ShaderMaterial.new()
var _red := _material(Color("ec5448"), 0.6)
var _glass: ShaderMaterial
var _glass_edge: ShaderMaterial
var _arrow_dark := _material(Color("152c36"), 0.7)
var _arrow_light := _material(Color("f6fcff"), 0.7)
var glass_faces: int = 0
var reservoir: Node3D
var gate_open_amount: float = 0.0
var _gate: Node3D
var _lid_closed: Vector3
var _status: MeshInstance3D
var _closed_light: StandardMaterial3D
var _open_light: StandardMaterial3D
var hazard_edges: Array[Node3D] = []
var _step_lower := ShaderMaterial.new()
var source_targets: Dictionary = {}
var source_lids: Dictionary = {}
var primary_source: StringName = &""
var _spill_cues: Array[MeshInstance3D] = []
var _spill_ages: Array[float] = []
var _spill_material: StandardMaterial3D
var _batches: Dictionary = {}
var _caps: Array[Dictionary] = []
var _goal_flaps: Array[Node3D] = []
var _intake_phase: float = 0.0
var _secured_seen: int = 0
var _floor_support: Array[Dictionary] = []
var step_patches: Array[Dictionary] = []
var _impact_leaf: Node3D
var _impact_status: StandardMaterial3D
var _cold_lights: Array[StandardMaterial3D] = []
var _intake_angle: float = 0.55


static func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	return result


static func _marble(color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/materials/marble.gdshader")
	material.set_shader_parameter("stone_noise", preload("res://assets/materials/marble_noise.tres"))
	material.set_shader_parameter("stone_color", color)
	return material


func _glass_material(alpha: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/materials/glass.gdshader")
	material.set_shader_parameter("face_opacity", alpha)
	material.render_priority = 2
	return material


func build(level: LevelDefinition) -> void:
	_intake_angle = 1.3 if level.goal_phase == 1 else 0.55
	_glass = _glass_material(0.065)
	_glass_edge = _glass_material(0.24)
	contact_material.shader = preload("res://assets/materials/contact.gdshader")
	contact_material.render_priority = -1
	_step.shader = preload("res://assets/materials/hazard.gdshader")
	_step_lower.shader = _step.shader
	_step_lower.set_shader_parameter("stripe_direction", -1.0)
	var heights: Array[float] = []
	for i: int in range(level.floor_regions.size()):
		if not heights.has(level.elevation(i)): heights.append(level.elevation(i))
	for ramp: Dictionary in level.ramps:
		for height: float in [float(ramp.start_height), float(ramp.end_height)]:
			if not heights.has(height): heights.append(height)
	for height: float in level.channel_heights():
		if not heights.has(height): heights.append(height)
	heights.sort()
	_lowest_floor = heights[0]
	_floor_support = level.floor_faces().duplicate()
	if _floor_support.is_empty():
		for tile: Dictionary in level.terrain_tiles():
			if tile.channel: _floor_support.append({"polygon": LevelDefinition.rectangle_polygon(tile.bounds), "height": tile.height})
	var floors := {}
	var marble := _marble(Color("e9e8df"))
	marble.set_shader_parameter("low_height", heights[0])
	marble.set_shader_parameter("high_height", heights[-1])
	floor_materials.append(marble)
	for height: float in heights:
		floors[roundi(height * 10000)] = marble
	if level.uses_polygons():
		for face: Dictionary in level.floor_faces():
			var centre := Vector2.ZERO
			for point: Vector2 in face.polygon: centre += point
			centre /= face.polygon.size()
			if face.has("ramp"):
				_ramp_polygon(face.polygon, level.ramps[face.ramp], floors[roundi(face.height * 10000)])
			else:
				_polygon(face.polygon, face.height, Vector3.UP, _glass if level.is_spill_bank(centre) else floors[roundi(face.height * 10000)])
		for polygon: PackedVector2Array in level.glass_patches():
			_polygon(polygon, level.board_top, Vector3.UP, _glass)
			_polygon(polygon, level.base_height, Vector3.DOWN, _glass)
			glass_faces += 2
		for polygon: PackedVector2Array in level.base_patches(): _slab(polygon, level.base_height - 0.005, 0.08, foundation)
		for polygon: PackedVector2Array in level.opening_polygons(): _drain(polygon, level.base_height)
	for tile: Dictionary in level.terrain_tiles():
		var r: Rect2 = tile.bounds
		var y: float = tile.height
		if tile.channel:
			var material: Material = floors[roundi(y * 10000)]
			_slab(LevelDefinition.rectangle_polygon(r), y, 0.06, material)
		else:
			_quad(Vector3(r.position.x, y, r.position.y), Vector3(r.end.x, y, r.position.y), Vector3(r.end.x, y, r.end.y), Vector3(r.position.x, y, r.end.y), Vector3.UP, _glass)
			_quad(Vector3(r.position.x, level.base_height, r.position.y), Vector3(r.end.x, level.base_height, r.position.y), Vector3(r.end.x, level.base_height, r.end.y), Vector3(r.position.x, level.base_height, r.end.y), Vector3.DOWN, _glass)
			glass_faces += 2
	for wall: PackedFloat32Array in level.wall_segments():
		var a := Vector2(wall[0], wall[1])
		var b := Vector2(wall[2], wall[3])
		var low := wall[4]
		var high := wall[5]
		var midpoint := (a + b) * 0.5
		var normal := Vector2(-(b.y - a.y), b.x - a.x).normalized()
		if level.floor_height(midpoint + normal * 0.002) > level.floor_height(midpoint - normal * 0.002): normal = -normal
		var step := high < level.board_top - 0.001
		var front := midpoint + normal * 0.01
		var back := midpoint - normal * 0.01
		var opening := level.is_void(front) or level.is_void(back) or not level.board_bounds.has_point(front) or not level.board_bounds.has_point(back)
		var spill_bank := level.is_spill_bank(front) or level.is_spill_bank(back)
		var edge_material: Material = _glass if spill_bank or not step else _slab_edge
		var low_a := low
		var low_b := low
		if not level.ramps.is_empty() and not step:
			var start_height := level.floor_height(a.lerp(b, 0.002) + normal * 0.004)
			var end_height := level.floor_height(b.lerp(a, 0.002) + normal * 0.004)
			if is_finite(start_height): low_a = start_height
			if is_finite(end_height): low_b = end_height
		_quad(Vector3(a.x, low_a, a.y), Vector3(b.x, low_b, b.y), Vector3(b.x, high, b.y), Vector3(a.x, high, a.y), Vector3(normal.x, 0, normal.y), edge_material)
		if spill_bank:
			glass_faces += 1
			_caps.append({"a": a, "b": b, "height": high, "normal": normal})
			var lip := PackedVector2Array([a - normal * 0.075, b - normal * 0.075, b, a])
			_paint_floor(lip, high, _step)
		elif step and opening:
			_paint_floor(PackedVector2Array([a - normal * 0.10, b - normal * 0.10, b, a]), high, _step_lower if high <= _lowest_floor + 0.001 else _step)
			open_edges += 1
		elif step:
			_mark_step(level, a, b, low, high, normal)
		else:
			glass_faces += 1
			_caps.append({"a": a, "b": b, "height": high, "normal": normal})
			_mark_bank_jamb(level, a, b, low, high, normal)
		if level.ramps.is_empty() and not opening and is_finite(level.floor_height(midpoint + normal * 0.06)):
			_contact_strip(a, b, low, normal, 0.17 if not step else 0.11)

	_finish_caps()
	_build_ramp_guides(level)
	if not level.uses_polygons():
		_slab(LevelDefinition.rectangle_polygon(level.board_bounds.grow(0.04)), level.base_height - 0.005, 0.08, foundation)
	var goal := level.goal
	var top := level.board_top + 0.026
	var rim := _box(Vector3(goal.size.x + 0.15, 0.04, 0.10), Vector3(goal.get_center().x, top, goal.end.y), _red)
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for x: float in [goal.position.x, goal.end.x]:
		var side := _box(Vector3(0.10, 0.04, goal.size.y), Vector3(x, top, goal.get_center().y), _red)
		side.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for obstacle: AABB in level.obstacles: _build_lintel(level, obstacle)
	if level.safe_goal: _build_safe_goal(level)
	_build_thermal_plates(level)
	if not level.impact_gate.is_empty(): _build_impact_gate(level)
	primary_source = level.reservoir_id
	if level.sources.is_empty():
		_build_reservoir(level)
	else:
		for source: Dictionary in level.sources:
			var fixture := LevelDefinition.new()
			fixture.reservoir_id = source.id
			fixture.reservoir_bounds = source.bounds
			fixture.floor_elevations = PackedFloat32Array([float(source.height)])
			fixture.board_top = level.board_top
			fixture.board_bounds = level.board_bounds
			_build_reservoir(fixture)
			if source.id == level.collection_source:
				fixture.goal = source.bounds
				fixture.floor_regions = [source.bounds]
				_build_safe_goal(fixture, false)
		var first: Dictionary = source_lids[primary_source]
		_gate = first.gate
		_lid_closed = first.closed
		_status = first.status
	_build_spill_cues()
	_finish_mesh()


func _build_lintel(level: LevelDefinition, box: AABB) -> void:
	_box(box.size, box.get_center(), _glass)
	var bottom := level.floor_height(Vector2(box.get_center().x, box.get_center().z))
	var height := box.position.y - bottom
	for z: float in [box.position.z - 0.012, box.end.z + 0.012]:
		for x: float in [box.position.x - 0.025, box.end.x + 0.025]:
			_box(Vector3(0.05, height + 0.05, 0.04), Vector3(x, bottom + height * 0.5, z), _steel)
		_box(Vector3(box.size.x + 0.10, 0.05, 0.04), Vector3(box.get_center().x, box.position.y + 0.005, z), _step)
		_box(Vector3(box.size.x + 0.10, 0.025, 0.035), Vector3(box.get_center().x, bottom + 0.006, z), _steel)


func _build_safe_goal(level: LevelDefinition, covered: bool = true) -> void:
	var g := level.goal
	var accent: Material = _red if covered else _steel
	var floor_y := level.floor_height(g.get_center())
	var roof := level.board_top + 0.05
	if covered: _box(Vector3(g.size.x, 0.08, g.size.y), Vector3(g.get_center().x, roof, g.get_center().y), _glass)
	for x: float in [g.position.x, g.end.x]:
		_box(Vector3(0.04, 0.04, g.size.y), Vector3(x, roof + 0.05, g.get_center().y), _steel)
		_box(Vector3(0.035, 0.025, g.size.y), Vector3(x, floor_y + 0.012, g.get_center().y), accent)
		for z: float in [g.position.y, g.end.y]:
			_box(Vector3(0.035, roof - floor_y, 0.035), Vector3(x, (roof + floor_y) * 0.5, z), _steel)
	_box(Vector3(g.size.x, 0.025, 0.035), Vector3(g.get_center().x, floor_y + 0.012, g.end.y), accent)
	_box(Vector3(g.size.x + 0.04, 0.04, 0.04), Vector3(g.get_center().x, roof + 0.05, g.position.y), _steel)
	for side: int in range(2):
		var hinge := Node3D.new()
		hinge.name = "CheckValve%d" % side
		hinge.position = Vector3(g.position.x if side == 0 else g.end.x, (floor_y + level.board_top) * 0.5, g.position.y + 0.015)
		add_child(hinge)
		var offset := g.size.x * 0.25 * (1.0 if side == 0 else -1.0)
		_box(Vector3(g.size.x * 0.5 - 0.02, level.board_top - floor_y - 0.04, 0.025), Vector3(offset, 0, 0), _glass_material(0.12), hinge)
		_box(Vector3(0.025, level.board_top - floor_y, 0.04), Vector3(offset * 2, 0, 0), _rim, hinge)
		_goal_flaps.append(hinge)
	# An inset arrow on the receiver floor makes the allowed direction clear.
	var centre := Vector3(g.get_center().x, floor_y + 0.009, g.position.y + 0.30)
	_triangle(centre + Vector3(0, 0, 0.17), centre + Vector3(-0.14, 0, -0.12), centre + Vector3(0.14, 0, -0.12), Vector3.UP, accent)
	if not covered:
		# A separate low outlet valve stays behind after the removable lid
		# flies away. Its leaves can swing downstream only.
		for side: int in range(2):
			var hinge := Node3D.new()
			hinge.name = "CollectorOutletValve%d" % side
			hinge.position = Vector3(g.position.x if side == 0 else g.end.x, floor_y + 0.175, g.end.y + 0.045)
			add_child(hinge)
			var offset := g.size.x * 0.25 * (1.0 if side == 0 else -1.0)
			_box(Vector3(g.size.x * 0.5 - 0.02, 0.30, 0.025), Vector3(offset, 0, 0), _glass_material(0.16), hinge)
			_box(Vector3(0.025, 0.30, 0.035), Vector3(offset * 2, 0, 0), _rim, hinge)
			_goal_flaps.append(hinge)
		var outlet := Vector3(g.get_center().x, floor_y + 0.009, g.end.y + 0.20)
		_triangle(outlet + Vector3(0, 0, 0.13), outlet + Vector3(-0.10, 0, -0.09), outlet + Vector3(0.10, 0, -0.09), Vector3.UP, accent)


func show_goal_intake(secured: int, activity: bool = false) -> void:
	# The collector outlet moves while its fill decreases as well as when
	# incoming water increases the protected volume.
	if secured != _secured_seen or activity: _intake_phase = 1.0
	_secured_seen = secured


func _build_thermal_plates(level: LevelDefinition) -> void:
	for region: Dictionary in level.heat_regions:
		var bounds: AABB = region.bounds
		if region.has("plate_bounds"):
			var plate: Rect2 = region.plate_bounds
			bounds.position.x = plate.position.x
			bounds.position.z = plate.position.y
			bounds.size.x = plate.size.x
			bounds.size.z = plate.size.y
		var cold := float(region.temperature) < 0
		var centre := Vector2(bounds.get_center().x, bounds.get_center().z)
		var floor_y := level.floor_height(centre)
		var plate := _material(Color("263b45") if cold else Color("40372e"), 0.8)
		var glow := _material(Color("56c7ed") if cold else Color("ef802e"), 0.5)
		glow.emission_enabled = true
		glow.emission = glow.albedo_color * 0.35
		if cold: _cold_lights.append(glow)
		_box(Vector3(bounds.size.x - 0.06, 0.018, bounds.size.z - 0.06), Vector3(centre.x, floor_y + 0.009, centre.y), plate)
		for side: float in [-1.0, 1.0]:
			_box(Vector3(bounds.size.x - 0.04, 0.018, 0.035), Vector3(centre.x, floor_y + 0.025, centre.y + side * (bounds.size.z * 0.5 - 0.035)), _steel)
		var bars := maxi(3, floori(bounds.size.z / 0.22))
		for i: int in range(bars):
			var z := bounds.position.z + 0.10 + (bounds.size.z - 0.20) * i / maxf(1, bars - 1)
			_box(Vector3(bounds.size.x - 0.18, 0.009, 0.022), Vector3(centre.x, floor_y + 0.024, z), glow)
		var indicator := _box(Vector3(0.07, 0.06, bounds.size.z * 0.45), Vector3(bounds.position.x + 0.06, floor_y + 0.05, centre.y), glow)
		indicator.name = "CoolingIndicator" if cold else "HeatingIndicator"


func _build_impact_gate(level: LevelDefinition) -> void:
	var gate := level.impact_gate
	var frame := Node3D.new()
	frame.name = "ImpulseGate"
	frame.position = gate.hinge
	var direction: Vector2 = gate.direction
	frame.rotation.y = atan2(direction.x, direction.y)
	add_child(frame)
	var width: float = gate.width
	var height: float = gate.height
	_impact_leaf = Node3D.new()
	_impact_leaf.name = "SpringLeaf"
	frame.add_child(_impact_leaf)
	_box(Vector3(width - 0.05, height, float(gate.thickness)), Vector3(0, -height * 0.5, 0), _steel, _impact_leaf)
	_impact_status = _material(Color("de9d48"), 0.45)
	_box(Vector3(width * 0.65, height * 0.34, 0.018), Vector3(0, -height * 0.5, -float(gate.thickness) * 0.5 - 0.01), _impact_status, _impact_leaf)
	_box(Vector3(width + 0.14, 0.09, 0.11), Vector3.ZERO, _rim, frame)
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.07, height + 0.06, 0.09), Vector3(side * (width * 0.5 + 0.035), -height * 0.5, 0), _steel, frame)
		for turn: int in range(5):
			_box(Vector3(0.025, 0.15, 0.14), Vector3(side * (width * 0.5 + 0.03) + (turn - 2) * 0.035, 0.01, 0), _rim, frame)


func show_mechanisms(angle: float, load: float, latched: bool, frozen: float) -> void:
	if is_instance_valid(_impact_leaf):
		_impact_leaf.rotation.x = -angle
		_impact_status.albedo_color = Color("72c9a0") if latched else Color("de9d48").lerp(Color("f1d48b"), clampf(load, 0, 1))
	for light: StandardMaterial3D in _cold_lights:
		light.albedo_color = Color("56c7ed").lerp(Color("d8f6ff"), clampf(frozen, 0, 1))


func _mark_bank_jamb(level: LevelDefinition, a: Vector2, b: Vector2, low: float, high: float, normal: Vector2) -> void:
	# Mark the exposed ends of a missing outer bank, without an arrow that
	# could suggest that pouring out through it is the intended route.
	var inside := level.board_bounds.grow(-0.002)
	var a_at_edge := not inside.has_point(a)
	var b_at_edge := not inside.has_point(b)
	if a_at_edge == b_at_edge: return
	var start := a if a_at_edge else b
	var end := b if a_at_edge else a
	end = start + (end - start).normalized() * minf(0.06, start.distance_to(end))
	var n := Vector3(normal.x, 0, normal.y)
	var p := Vector3(start.x, low + 0.003, start.y) + n * 0.003
	var q := Vector3(end.x, low + 0.003, end.y) + n * 0.003
	_quad(p, q, Vector3(q.x, high + 0.003, q.z), Vector3(p.x, high + 0.003, p.z), n, _step)
	bank_jambs += 1


func _finish_caps() -> void:
	var joins := {}
	for edge: Dictionary in _caps:
		for point: Vector2 in [edge.a, edge.b]:
			var key := Vector3i(roundi(point.x * 10000), roundi(edge.height * 10000), roundi(point.y * 10000))
			joins[key] = (joins.get(key, Vector2.ZERO) as Vector2) + edge.normal
	for edge: Dictionary in _caps:
		var offsets: Array[Vector2] = []
		for point: Vector2 in [edge.a, edge.b]:
			var key := Vector3i(roundi(point.x * 10000), roundi(edge.height * 10000), roundi(point.y * 10000))
			var normal: Vector2 = joins[key]
			if normal.length_squared() < 0.01: normal = edge.normal
			normal = normal.normalized()
			offsets.append(normal * (0.0275 / maxf(0.5, normal.dot(edge.normal))))
		var a: Vector2 = edge.a
		var b: Vector2 = edge.b
		var al := a - offsets[0]
		var ar := a + offsets[0]
		var bl := b - offsets[1]
		var br := b + offsets[1]
		var top: float = edge.height + 0.029
		_quad(Vector3(al.x, top, al.y), Vector3(bl.x, top, bl.y), Vector3(br.x, top, br.y), Vector3(ar.x, top, ar.y), Vector3.UP, _glass_edge)
		var n := Vector3(edge.normal.x, 0, edge.normal.y)
		_quad(Vector3(ar.x, top - 0.035, ar.y), Vector3(br.x, top - 0.035, br.y), Vector3(br.x, top, br.y), Vector3(ar.x, top, ar.y), n, _glass_edge)
		_quad(Vector3(al.x, top - 0.035, al.y), Vector3(bl.x, top - 0.035, bl.y), Vector3(bl.x, top, bl.y), Vector3(al.x, top, al.y), -n, _glass_edge)


func _ramp_polygon(points: PackedVector2Array, ramp: Dictionary, material: Material) -> void:
	var indices := Geometry2D.triangulate_polygon(points)
	for i: int in range(0, indices.size(), 3):
		var vertices: Array[Vector3] = []
		for k: int in range(3):
			var p := points[indices[i+k]]
			vertices.append(Vector3(p.x, LevelDefinition.ramp_height(ramp, p), p.y))
		var normal := (vertices[2] - vertices[0]).cross(vertices[1] - vertices[0]).normalized()
		if normal.y < 0: normal = -normal
		_triangle(vertices[0], vertices[1], vertices[2], normal, material)


func _build_ramp_guides(level: LevelDefinition) -> void:
	for ramp: Dictionary in level.ramps:
		var rect: Rect2 = ramp.bounds
		var axis: Vector2 = ramp.axis
		var length := absf(axis.x * rect.size.x) + absf(axis.y * rect.size.y)
		var start := rect.position + Vector2(rect.size.x if axis.x < 0 else 0.0, rect.size.y if axis.y < 0 else 0.0)
		var cross_axis := Vector2(-axis.y, axis.x)
		var across := rect.size.x if axis.x == 0 else rect.size.y
		start += cross_axis * (across * 0.5 * (-1.0 if cross_axis.x < 0 or cross_axis.y < 0 else 1.0))
		var markers := maxi(2, floori(length / 1.1))
		for i: int in range(markers):
			var centre := start + axis * length * float(i + 1) / (markers + 1)
			var arrow := PackedVector2Array([centre + axis * 0.14, centre - axis * 0.10 - cross_axis * 0.10, centre - axis * 0.10 + cross_axis * 0.10])
			var overlay := ramp.duplicate()
			overlay.start_height = float(ramp.start_height) + 0.009
			overlay.end_height = float(ramp.end_height) + 0.009
			_ramp_polygon(arrow, overlay, _arrow_light)


func _polygon(points: PackedVector2Array, y: float, normal: Vector3, material: Material) -> void:
	var indices := Geometry2D.triangulate_polygon(points)
	for i: int in range(0, indices.size(), 3):
		var a := points[indices[i]]
		var b := points[indices[i + 1]]
		var c := points[indices[i + 2]]
		_triangle(Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(c.x, y, c.y), normal, material)


func _slab(points: PackedVector2Array, top: float, depth: float, material: Material) -> void:
	_polygon(points, top, Vector3.UP, material)
	_polygon(points, top - depth, Vector3.DOWN, material)
	for i: int in range(points.size()):
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var n := Vector2(b.y - a.y, a.x - b.x).normalized()
		_quad(Vector3(a.x, top - depth, a.y), Vector3(b.x, top - depth, b.y), Vector3(b.x, top, b.y), Vector3(a.x, top, a.y), Vector3(n.x, 0, n.y), material)


func _drain(points: PackedVector2Array, base: float) -> void:
	_polygon(points, base - 0.66, Vector3.UP, _well)
	for i: int in range(points.size()):
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var n := Vector2(-(b.y - a.y), b.x - a.x).normalized()
		if not Geometry2D.is_point_in_polygon((a + b) * 0.5 + n * 0.002, points): n = -n
		_quad(Vector3(a.x, base - 0.66, a.y), Vector3(b.x, base - 0.66, b.y), Vector3(b.x, base - 0.005, b.y), Vector3(a.x, base - 0.005, a.y), Vector3(n.x, 0, n.y), _well)


func _contact_strip(a: Vector2, b: Vector2, height: float, normal: Vector2, opacity: float) -> void:
	if not _batches.has(contact_material):
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		builder.set_material(contact_material)
		_batches[contact_material] = builder
	var builder: SurfaceTool = _batches[contact_material]
	var n := Vector3(normal.x, 0, normal.y) * 0.13
	var p := Vector3(a.x, height + 0.005, a.y)
	var q := Vector3(b.x, height + 0.005, b.y)
	var points: Array[Vector3] = [p, q, q + n, p, q + n, p + n]
	var alphas: Array[float] = [opacity, opacity, 0.0, opacity, 0.0, 0.0]
	if (q - p).cross(n).dot(Vector3.UP) > 0.0:
		points = [p, q + n, q, p, p + n, q + n]
		alphas = [opacity, 0.0, opacity, opacity, 0.0, 0.0]
	for i: int in range(points.size()):
		builder.set_color(Color(1, 1, 1, alphas[i]))
		builder.set_normal(Vector3.UP)
		builder.add_vertex(points[i])
	contact_bands += 1


func _paint_floor(points: PackedVector2Array, height: float, material: Material) -> void:
	# A band may only cover its actual landing. Extending an uncut quad over
	# a curved junction produces the floating spikes seen in the old levels.
	for face: Dictionary in _floor_support:
		if absf(float(face.height) - height) > 0.0001: continue
		for piece: PackedVector2Array in Geometry2D.intersect_polygons(points, face.polygon):
			_polygon(piece, height + 0.006, Vector3.UP, material)
			step_patches.append({"polygon": piece, "height": height})


func _mark_step(level: LevelDefinition, a: Vector2, b: Vector2, low: float, high: float, downhill: Vector2) -> void:
	# One continuous marking wraps over the lip, down the riser and onto
	# the landing. Arrows on the high side identify the descent direction.
	var n := Vector3(downhill.x, 0, downhill.y)
	var ah := Vector3(a.x, high + 0.004, a.y)
	var bh := Vector3(b.x, high + 0.004, b.y)
	var riser_bottom := maxf(low, high - 0.075)
	_quad(Vector3(a.x, riser_bottom, a.y) + n * 0.002, Vector3(b.x, riser_bottom, b.y) + n * 0.002, bh + n * 0.002, ah + n * 0.002, n, _step)
	_paint_floor(PackedVector2Array([a - downhill * 0.12, b - downhill * 0.12, b, a]), high, _step)
	_paint_floor(PackedVector2Array([a, b, b + downhill * 0.10, a + downhill * 0.10]), low, _step_lower)
	var tangent := Vector3(b.x - a.x, 0, b.y - a.y).normalized()
	var arrows: Array[float] = []
	if a.distance_to(b) > 1.0: arrows.assign([0.33, 0.67])
	elif a.distance_to(b) > 0.55: arrows.append(0.5)
	for fraction: float in arrows:
		var centre := ah.lerp(bh, fraction) - n * 0.065 + Vector3.UP * 0.005
		var points: Array[Vector3] = [centre + n * 0.045, centre - n * 0.04 - tangent * 0.05, centre - n * 0.04 + tangent * 0.05]
		var supported := true
		for point: Vector3 in points: supported = supported and absf(level.floor_height(Vector2(point.x, point.z)) - high) < 0.0001
		if not supported: continue
		_triangle(points[0], points[1], points[2], Vector3.UP, _arrow_dark)
		centre += Vector3.UP * 0.002
		_triangle(centre + n * 0.03, centre - n * 0.024 - tangent * 0.025, centre - n * 0.024 + tangent * 0.025, Vector3.UP, _arrow_light)
	var marker := Node3D.new()
	marker.name = "StepFold"
	marker.position = ah.lerp(bh, 0.5)
	add_child(marker)
	hazard_edges.append(marker)


func _triangle(a: Vector3, b: Vector3, c: Vector3, normal: Vector3, material: Material) -> void:
	if not _batches.has(material):
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		builder.set_material(material)
		_batches[material] = builder
	var surface: SurfaceTool = _batches[material]
	var points: Array[Vector3] = [a, b, c]
	if (b - a).cross(c - a).dot(normal) > 0.0: points.reverse()
	for point: Vector3 in points:
		surface.set_normal(normal)
		surface.set_uv(Vector2(point.x, point.z))
		surface.add_vertex(point)


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
		surface.set_uv(Vector2(point.x, point.z))
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
	source_targets[level.reservoir_id] = AABB(Vector3(r.position.x - 0.08, floor_y, r.position.y - 0.08), Vector3(r.size.x + 0.16, roof - floor_y + 0.16, r.size.y + 0.16))
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
	source_lids[level.reservoir_id] = {"gate":_gate,"closed":_lid_closed,"status":_status,"closed_light":_closed_light,"open_light":_open_light,"amount":0.0}
	set_source_open_amount(level.reservoir_id,0)


func source_anchor(id: StringName) -> Vector3:
	var target: AABB = source_targets[id]
	return target.get_center() + Vector3.UP * target.size.y * 0.5


func pick_source(ray_origin: Vector3, ray_direction: Vector3) -> StringName:
	var inverse := global_transform.affine_inverse()
	var origin := inverse * ray_origin
	var direction := (inverse.basis * ray_direction).normalized()
	var closest := INF
	var selected: StringName = &""
	for id: StringName in source_targets:
		var hit: Variant = (source_targets[id] as AABB).intersects_ray(origin, direction)
		if hit is Vector3 and origin.distance_squared_to(hit) < closest:
			closest = origin.distance_squared_to(hit)
			selected = id
	return selected


func _build_spill_cues() -> void:
	_spill_material = _material(Color("269fc9"), 0.3)
	_spill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spill_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_spill_material.albedo_color.a = 0.4
	for i: int in range(8):
		var cue := MeshInstance3D.new()
		var ring := TorusMesh.new()
		ring.inner_radius = 0.10
		ring.outer_radius = 0.14
		ring.rings = 12
		ring.ring_segments = 6
		cue.mesh = ring
		cue.material_override = _spill_material
		cue.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cue.hide()
		add_child(cue)
		_spill_cues.append(cue)
		_spill_ages.append(1.0)


func show_spills(points: PackedVector3Array) -> void:
	for point: Vector3 in points:
		var nearby := false
		for i: int in range(_spill_cues.size()):
			if _spill_ages[i] < 0.6 and _spill_cues[i].position.distance_to(point) < 0.6: nearby = true
		if nearby: continue
		var slot := _spill_ages.find(_spill_ages.max())
		_spill_ages[slot] = 0.0
		_spill_cues[slot].position = point
		_spill_cues[slot].show()


func advance_effects(delta: float) -> void:
	_intake_phase = maxf(0.0, _intake_phase - delta * 3.0)
	for i: int in range(_goal_flaps.size()):
		_goal_flaps[i].rotation.y = _intake_phase * _intake_angle * (-1.0 if i % 2 == 0 else 1.0)
	for i: int in range(_spill_cues.size()):
		_spill_ages[i] += delta
		var age := _spill_ages[i]
		_spill_cues[i].visible = age < 0.6
		_spill_cues[i].scale = Vector3.ONE * (1.0 + age * 2.0)
		_spill_cues[i].transparency = clampf(age / 0.6, 0.0, 1.0)


func clear_effects() -> void:
	show_mechanisms(0, 0, false, 0)
	_secured_seen = 0
	_intake_phase = 0.0
	for flap: Node3D in _goal_flaps: flap.rotation = Vector3.ZERO
	for i: int in range(_spill_cues.size()):
		_spill_ages[i] = 1.0
		_spill_cues[i].hide()


func set_reservoir_open_amount(amount: float) -> void:
	set_source_open_amount(primary_source, amount)


func set_source_open_amount(id: StringName, amount: float) -> void:
	if not source_lids.has(id): return
	var lid: Dictionary = source_lids[id]
	lid.amount = clampf(amount,0.0,1.0)
	if id == primary_source: gate_open_amount = lid.amount
	var kick := smoothstep(0.0,0.30,lid.amount)
	var flight := smoothstep(0.12,1.0,lid.amount)
	(lid.gate as Node3D).position = lid.closed + Vector3(-4.8*flight,2.2*flight-0.4*flight*flight,0.28*kick+0.5*flight)
	(lid.gate as Node3D).rotation = Vector3(-2.8*flight,1.8*flight,-2.1*flight)
	(lid.gate as Node3D).visible = lid.amount < 0.999
	(lid.status as MeshInstance3D).material_override = lid.open_light if lid.amount >= 0.30 else lid.closed_light


func reset_sources() -> void:
	for id: StringName in source_lids: set_source_open_amount(id,0.0)


func set_source_ready(id: StringName, ready: bool) -> void:
	if not source_lids.has(id): return
	var lid: Dictionary = source_lids[id]
	if lid.amount < 0.30:
		(lid.status as MeshInstance3D).material_override = lid.open_light if ready else lid.closed_light


func set_goal_complete(complete: bool) -> void:
	_red.albedo_color = Color("42bcb0") if complete else Color("ec5448")
	_red.emission_enabled = complete
	_red.emission = Color("197c71") if complete else Color.BLACK


func _box(size: Vector3, center: Vector3, material: Material, parent: Node = self) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shape := BoxMesh.new()
	shape.size = size
	instance.mesh = shape
	instance.material_override = material
	instance.position = center
	parent.add_child(instance)
	return instance


func _cylinder(radius: float, height: float, center: Vector3, material: Material, parent: Node) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
