class_name HydrologicBoard
extends Node3D
## Functional transparent channels: physical rims stay legible while water
## remains visible through the walls and the top of every raised obstacle.

var _steel := _material(Color("657078"), 0.55)
var _base := _material(Color("abb3b0"), 0.9)
var _rim := _material(Color("78868a"), 0.55)
var foundation := _material(Color("b7b0a1"), 0.9)
var floor_materials: Array[StandardMaterial3D] = []
var contact_material := ShaderMaterial.new()
var contact_bands: int = 0
var open_edges: int = 0
var bank_jambs: int = 0
var _slab_edge := _material(Color("918676"), 0.85)
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
var _spill_cues: Array[MeshInstance3D] = []
var _spill_ages: Array[float] = []
var _spill_material: StandardMaterial3D
var _batches: Dictionary = {}
var _caps: Array[Dictionary] = []


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
	for height: float in level.channel_heights():
		if not heights.has(height): heights.append(height)
	heights.sort()
	_lowest_floor = heights[0]
	var floors := {}
	for height: float in heights:
		var depth := (heights[-1] - height) / maxf(0.01, heights[-1] - heights[0])
		var material := _material(Color("e8dfca").lerp(Color("b9b09f"), depth * 0.5), 0.92)
		floors[roundi(height * 10000)] = material
		floor_materials.append(material)
	if not level.channel_curves.is_empty() or not level.void_regions.is_empty():
		for face: Dictionary in level.floor_faces(): _polygon(face.polygon, face.height, Vector3.UP, floors[roundi(face.height * 10000)])
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
			var plate := _box(Vector3(r.size.x, 0.06, r.size.y), Vector3(r.get_center().x, y - 0.03, r.get_center().y), material)
			plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
		var edge_material: Material = _slab_edge if step and opening else (_step if step else _glass)
		_quad(Vector3(a.x, low, a.y), Vector3(b.x, low, b.y), Vector3(b.x, high, b.y), Vector3(a.x, high, a.y), Vector3(normal.x, 0, normal.y), edge_material)
		if step and opening:
			var n := Vector3(normal.x, 0, normal.y)
			var ah := Vector3(a.x, high + 0.006, a.y)
			var bh := Vector3(b.x, high + 0.006, b.y)
			_quad(ah - n * 0.10, bh - n * 0.10, bh, ah, Vector3.UP, _step_lower if high <= _lowest_floor + 0.001 else _step)
			open_edges += 1
		elif step:
			_mark_step(a, b, low, high, normal)
		else:
			glass_faces += 1
			_caps.append({"a": a, "b": b, "height": high, "normal": normal})
			_mark_bank_jamb(level, a, b, low, high, normal)
		if not opening and is_finite(level.floor_height(midpoint + normal * 0.06)):
			_contact_strip(a, b, low, normal, 0.17 if not step else 0.11)

	_finish_caps()
	_finish_mesh()
	if level.channel_curves.is_empty() and level.void_regions.is_empty():
		_box(Vector3(level.board_bounds.size.x + 0.08, 0.08, level.board_bounds.size.y + 0.08), Vector3(level.board_bounds.get_center().x, level.base_height - 0.045, level.board_bounds.get_center().y), foundation)
	var goal := level.goal
	var top := level.board_top + 0.026
	var rim := _box(Vector3(goal.size.x + 0.15, 0.04, 0.10), Vector3(goal.get_center().x, top, goal.end.y), _red)
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for x: float in [goal.position.x, goal.end.x]:
		var side := _box(Vector3(0.10, 0.04, goal.size.y), Vector3(x, top, goal.get_center().y), _red)
		side.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_build_reservoir(level)
	_build_spill_cues()


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


func _mark_step(a: Vector2, b: Vector2, low: float, high: float, downhill: Vector2) -> void:
	# One continuous marking wraps over the lip, down the riser and onto
	# the landing. Arrows on the high side identify the descent direction.
	var n := Vector3(downhill.x, 0, downhill.y)
	var ah := Vector3(a.x, high + 0.004, a.y)
	var bh := Vector3(b.x, high + 0.004, b.y)
	var al := Vector3(a.x, low + 0.004, a.y)
	var bl := Vector3(b.x, low + 0.004, b.y)
	_quad(ah - n * 0.24, bh - n * 0.24, bh, ah, Vector3.UP, _step)
	_quad(al, bl, bl + n * 0.20, al + n * 0.20, Vector3.UP, _step_lower)
	var tangent := Vector3(b.x - a.x, 0, b.y - a.y).normalized()
	var arrows: Array[float] = []
	if a.distance_to(b) > 0.75: arrows.assign([0.33, 0.67])
	elif a.distance_to(b) > 0.40: arrows.append(0.5)
	for fraction: float in arrows:
		var centre := ah.lerp(bh, fraction) - n * 0.13 + Vector3.UP * 0.003
		_triangle(centre + n * 0.095, centre - n * 0.08 - tangent * 0.075, centre - n * 0.08 + tangent * 0.075, Vector3.UP, _arrow_dark)
		centre += Vector3.UP * 0.002
		_triangle(centre + n * 0.065, centre - n * 0.052 - tangent * 0.045, centre - n * 0.052 + tangent * 0.045, Vector3.UP, _arrow_light)
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
	set_reservoir_open_amount(0)


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
	for i: int in range(_spill_cues.size()):
		_spill_ages[i] += delta
		var age := _spill_ages[i]
		_spill_cues[i].visible = age < 0.6
		_spill_cues[i].scale = Vector3.ONE * (1.0 + age * 2.0)
		_spill_cues[i].transparency = clampf(age / 0.6, 0.0, 1.0)


func clear_effects() -> void:
	for i: int in range(_spill_cues.size()):
		_spill_ages[i] = 1.0
		_spill_cues[i].hide()


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
