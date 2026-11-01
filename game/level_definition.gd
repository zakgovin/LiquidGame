class_name LevelDefinition
extends Resource
## True 3D terraced channels authored with rectangles or Bezier ribbons.
## Elevations, exact curved boundaries and cutouts are shared with physics.

@export var title: String
@export var description: String = "LEVEL_ROUTE"
@export var floor_regions: Array[Rect2] = []
@export var floor_elevations := PackedFloat32Array()
@export var channel_curves: Array[Curve2D] = []
@export var channel_widths := PackedFloat32Array()
@export var channel_end_widths := PackedFloat32Array()
@export var channel_elevations := PackedFloat32Array()
@export var void_regions: Array[Rect2] = []
@export var camera_elevation: float = 65.0
@export var outline: PackedVector2Array
@export var spawn: Rect2
@export var reservoir_bounds: Rect2 = Rect2(-2.6, -4.5, 1.4, 1.8)
@export var goal: Rect2
@export var particle_count: int = 6144
@export var safe_goal: bool = false
@export var obstacles: Array[AABB] = []
@export var required_fraction: float = 0.8
@export var hold_seconds: float = 0.75
@export var flow_speed: float = 1.15
@export var reservoir_id: StringName = &"source_01"
@export var board_bounds: Rect2 = Rect2(-2.95, -4.9, 5.9, 9.8)
@export var board_top: float = 1.26
@export var base_height: float = -0.56
@export var route: PackedVector2Array
var _tiles: Array[Dictionary] = []
var _walls: Array[PackedFloat32Array] = []
var _geometry_ready: bool = false
var _ribbons: Array[PackedVector2Array] = []
var _ribbon_heights := PackedFloat32Array()
var _floors: Array[Dictionary] = []
var _glass_patches: Array[PackedVector2Array] = []
var _base_patches: Array[PackedVector2Array] = []
var _openings: Array[PackedVector2Array] = []


func elevation(index: int) -> float:
	return floor_elevations[index] if index < floor_elevations.size() else 0.0


func contains(point: Vector2, margin: float = 0.0) -> bool:
	for region: Rect2 in floor_regions:
		if region.grow(-margin).has_point(point): return true
	_prepare_ribbons()
	for polygon: PackedVector2Array in _ribbons:
		if Geometry2D.is_point_in_polygon(point, polygon):
			if margin <= 0.0: return true
			var distance := INF
			for i: int in range(polygon.size()): distance = minf(distance, point.distance_to(Geometry2D.get_closest_point_to_segment(point, polygon[i], polygon[(i + 1) % polygon.size()])))
			if distance >= margin: return true
	return false


func floor_height(point: Vector2) -> float:
	if not board_bounds.has_point(point): return -INF
	var result := board_top
	for i: int in range(floor_regions.size()):
		if floor_regions[i].has_point(point): result = minf(result, elevation(i))
	_prepare_ribbons()
	for i: int in range(_ribbons.size()):
		if Geometry2D.is_point_in_polygon(point, _ribbons[i]): result = minf(result, _ribbon_heights[i])
	if result == board_top:
		for opening: Rect2 in void_regions:
			if opening.has_point(point): return -INF
	return result


func is_void(point: Vector2) -> bool:
	if contains(point): return false
	for opening: Rect2 in void_regions:
		if opening.has_point(point): return true
	return false


func _prepare_ribbons() -> void:
	if not _ribbons.is_empty() or channel_curves.is_empty(): return
	for i: int in range(channel_curves.size()):
		var width := channel_widths[i] if i < channel_widths.size() else 1.2
		var end_width := channel_end_widths[i] if i < channel_end_widths.size() else width
		if not is_equal_approx(width, end_width):
			var points := channel_curves[i].get_baked_points()
			var left := PackedVector2Array()
			var right := PackedVector2Array()
			var distance := 0.0
			for j: int in range(points.size()):
				if j > 0: distance += points[j].distance_to(points[j - 1])
				var tangent := (points[mini(j + 1, points.size() - 1)] - points[maxi(0, j - 1)]).normalized()
				var normal := Vector2(-tangent.y, tangent.x)
				var half := lerpf(width, end_width, smoothstep(0.0, channel_curves[i].get_baked_length(), distance)) * 0.5
				left.append(points[j] + normal * half)
				right.append(points[j] - normal * half)
			right.reverse()
			left.append_array(right)
			_ribbons.append(left)
			_ribbon_heights.append(channel_elevations[i])
			continue
		for polygon: PackedVector2Array in Geometry2D.offset_polyline(channel_curves[i].get_baked_points(), width * 0.5, Geometry2D.JOIN_ROUND, Geometry2D.END_BUTT):
			_ribbons.append(polygon)
			_ribbon_heights.append(channel_elevations[i])


func channel_polygons() -> Array[PackedVector2Array]:
	_prepare_ribbons()
	return _ribbons


func channel_heights() -> PackedFloat32Array:
	_prepare_ribbons()
	return _ribbon_heights


func floor_faces() -> Array[Dictionary]:
	_build_geometry()
	return _floors


func glass_patches() -> Array[PackedVector2Array]:
	_build_geometry()
	return _glass_patches


func base_patches() -> Array[PackedVector2Array]:
	_build_geometry()
	return _base_patches


func opening_polygons() -> Array[PackedVector2Array]:
	_build_geometry()
	return _openings


static func rectangle_polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])


static func _subtract(pieces: Array[PackedVector2Array], cutter: PackedVector2Array) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for piece: PackedVector2Array in pieces:
		result.append_array(Geometry2D.clip_polygons(piece, cutter))
	return result


func _build_curved_geometry() -> void:
	_prepare_ribbons()
	var shapes: Array[Dictionary] = []
	for i: int in range(floor_regions.size()): shapes.append({"polygon": rectangle_polygon(floor_regions[i]), "height": elevation(i)})
	for i: int in range(_ribbons.size()): shapes.append({"polygon": _ribbons[i], "height": _ribbon_heights[i]})
	for i: int in range(shapes.size()):
		var pieces: Array[PackedVector2Array] = [shapes[i].polygon]
		for j: int in range(shapes.size()):
			if shapes[j].height < shapes[i].height - 0.0001 or (j < i and is_equal_approx(shapes[j].height, shapes[i].height)):
				pieces = _subtract(pieces, shapes[j].polygon)
		for piece: PackedVector2Array in pieces: _floors.append({"polygon": piece, "height": shapes[i].height})
	for opening: Rect2 in void_regions:
		var pieces: Array[PackedVector2Array] = [rectangle_polygon(opening)]
		for shape: Dictionary in shapes: pieces = _subtract(pieces, shape.polygon)
		_openings.append_array(pieces)
	# Clip small tiles against the exact curved outlines. Their interiors have
	# no holes, so triangulation preserves both the channel and the cutout.
	var cell := 0.35
	for iz: int in range(ceili(board_bounds.size.y / cell)):
		for ix: int in range(ceili(board_bounds.size.x / cell)):
			var rect := Rect2(board_bounds.position + Vector2(ix, iz) * cell, Vector2.ONE * cell).intersection(board_bounds)
			var base: Array[PackedVector2Array] = [rectangle_polygon(rect)]
			for opening: PackedVector2Array in _openings: base = _subtract(base, opening)
			_base_patches.append_array(base)
			var glass: Array[PackedVector2Array] = [rectangle_polygon(rect)]
			for shape: Dictionary in shapes: glass = _subtract(glass, shape.polygon)
			for opening: Rect2 in void_regions: glass = _subtract(glass, rectangle_polygon(opening))
			_glass_patches.append_array(glass)
	var outlines: Array[PackedVector2Array] = [rectangle_polygon(board_bounds)]
	for shape: Dictionary in shapes: outlines.append(shape.polygon)
	for opening: Rect2 in void_regions: outlines.append(rectangle_polygon(opening))
	var edges: Array[Dictionary] = []
	for polygon: PackedVector2Array in outlines:
		for i: int in range(polygon.size()):
			var a := polygon[i]
			var b := polygon[(i + 1) % polygon.size()]
			if a.distance_squared_to(b) < 0.00000001: continue
			edges.append({"a": a, "b": b, "bounds": Rect2(a.min(b), (b - a).abs()).grow(0.0001)})
	var seen := {}
	for edge: Dictionary in edges:
		var a: Vector2 = edge.a
		var b: Vector2 = edge.b
		var vector := b - a
		var cuts: Array[float] = [0.0, 1.0]
		for other: Dictionary in edges:
			if not edge.bounds.intersects(other.bounds): continue
			var hit: Variant = Geometry2D.segment_intersects_segment(a, b, other.a, other.b)
			if hit is Vector2: cuts.append(clampf((hit - a).dot(vector) / vector.length_squared(), 0.0, 1.0))
			for point: Vector2 in [other.a, other.b]:
				if point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b)) < 0.0001: cuts.append(clampf((point - a).dot(vector) / vector.length_squared(), 0.0, 1.0))
		cuts.sort()
		for i: int in range(cuts.size() - 1):
			var start := a + vector * cuts[i]
			var end := a + vector * cuts[i + 1]
			if start.distance_to(end) < 0.0002: continue
			var midpoint := (start + end) * 0.5
			var normal := Vector2(-vector.y, vector.x).normalized()
			var left := floor_height(midpoint + normal * 0.002)
			var right := floor_height(midpoint - normal * 0.002)
			if not is_finite(left): left = base_height
			if not is_finite(right): right = base_height
			if absf(left - right) < 0.0001: continue
			var qa := Vector2i(roundi(start.x * 10000), roundi(start.y * 10000))
			var qb := Vector2i(roundi(end.x * 10000), roundi(end.y * 10000))
			var key := "%s:%s" % [qa, qb] if (qa.x < qb.x or (qa.x == qb.x and qa.y < qb.y)) else "%s:%s" % [qb, qa]
			if seen.has(key): continue
			seen[key] = true
			_walls.append(PackedFloat32Array([start.x, start.y, end.x, end.y, minf(left, right), maxf(left, right)]))


func constrain_world(point: Vector3, _previous: Vector3, radius: float) -> Vector3:
	# Sphere versus the actual solid terrain. Connected floor rectangles must
	# not each be shrunk: that creates invisible gaps and accelerates parcels
	# across joins. Rounded contacts also let water fall over step edges.
	if not board_bounds.grow(radius).has_point(Vector2(point.x, point.z)): return point
	for tile: Dictionary in terrain_tiles():
		var rect: Rect2 = tile.bounds
		var height: float = tile.height
		if point.y >= height + radius or point.y < base_height - radius: continue
		if not rect.grow(radius).has_point(Vector2(point.x, point.z)): continue
		var lower := Vector3(rect.position.x, base_height, rect.position.y)
		var upper := Vector3(rect.end.x, height, rect.end.y)
		var nearest := point.clamp(lower, upper)
		var difference := point - nearest
		var distance := difference.length()
		if distance >= radius: continue
		if distance > 0.000001:
			point += difference * (radius / distance - 1.0)
		else:
			var exits: Array[Vector3] = [Vector3(0, upper.y + radius - point.y, 0), Vector3(lower.x - radius - point.x, 0, 0), Vector3(upper.x + radius - point.x, 0, 0), Vector3(0, 0, lower.z - radius - point.z), Vector3(0, 0, upper.z + radius - point.z)]
			var best := exits[0]
			for candidate: Vector3 in exits:
				if candidate.length_squared() < best.length_squared(): best = candidate
			point += best
	return point


func is_in_goal(point: Vector3) -> bool:
	var horizontal := Vector2(point.x, point.z)
	return goal.has_point(horizontal) and point.y >= floor_height(horizontal) and point.y < board_top


func terrain_tiles() -> Array[Dictionary]:
	_build_geometry()
	return _tiles


func wall_segments() -> Array[PackedFloat32Array]:
	_build_geometry()
	return _walls


func _build_geometry() -> void:
	if _geometry_ready: return
	_geometry_ready = true
	if not channel_curves.is_empty() or not void_regions.is_empty():
		_build_curved_geometry()
		return
	var xs: Array[float] = [board_bounds.position.x, board_bounds.end.x]
	var zs: Array[float] = [board_bounds.position.y, board_bounds.end.y]
	for region: Rect2 in floor_regions:
		for x: float in [region.position.x, region.end.x]:
			if not xs.has(x): xs.append(x)
		for z: float in [region.position.y, region.end.y]:
			if not zs.has(z): zs.append(z)
	xs.sort()
	zs.sort()
	var heights: Array[PackedFloat32Array] = []
	for iz: int in range(zs.size() - 1):
		var row := PackedFloat32Array()
		for ix: int in range(xs.size() - 1):
			var rectangle := Rect2(xs[ix], zs[iz], xs[ix + 1] - xs[ix], zs[iz + 1] - zs[iz])
			var height := floor_height(rectangle.get_center())
			row.append(height)
			_tiles.append({"bounds": rectangle, "height": height, "channel": contains(rectangle.get_center())})
		heights.append(row)
	for iz: int in range(zs.size() - 1):
		for ix: int in range(xs.size()):
			var left := heights[iz][ix - 1] if ix > 0 else base_height
			var right := heights[iz][ix] if ix < xs.size() - 1 else base_height
			if absf(left - right) > 0.0001:
				_walls.append(PackedFloat32Array([xs[ix], zs[iz], xs[ix], zs[iz + 1], minf(left, right), maxf(left, right)]))
	for ix: int in range(xs.size() - 1):
		for iz: int in range(zs.size()):
			var above := heights[iz - 1][ix] if iz > 0 else base_height
			var below := heights[iz][ix] if iz < zs.size() - 1 else base_height
			if absf(above - below) > 0.0001:
				_walls.append(PackedFloat32Array([xs[ix], zs[iz], xs[ix + 1], zs[iz], minf(above, below), maxf(above, below)]))
