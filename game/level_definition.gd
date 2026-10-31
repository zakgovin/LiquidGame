class_name LevelDefinition
extends Resource
## True 3D terraced channels. Rectangles describe floor footprints, while
## elevations, finite solid walls and gravity supply the vertical geometry.

@export var title: String
@export var floor_regions: Array[Rect2] = []
@export var floor_elevations := PackedFloat32Array()
@export var outline: PackedVector2Array
@export var spawn: Rect2
@export var goal: Rect2
@export var particle_count: int = 512
@export var required_fraction: float = 0.8
@export var hold_seconds: float = 0.75
@export var board_bounds: Rect2 = Rect2(-2.95, -4.9, 5.9, 9.8)
@export var board_top: float = 0.82
@export var base_height: float = -0.55
@export var route: PackedVector2Array
var _tiles: Array[Dictionary] = []
var _walls: Array[PackedFloat32Array] = []


func elevation(index: int) -> float:
	return floor_elevations[index] if index < floor_elevations.size() else 0.0


func contains(point: Vector2, margin: float = 0.0) -> bool:
	for region: Rect2 in floor_regions:
		if region.grow(-margin).has_point(point): return true
	return false


func floor_height(point: Vector2) -> float:
	if not board_bounds.has_point(point): return -INF
	var result := board_top
	for i: int in range(floor_regions.size()):
		if floor_regions[i].has_point(point): result = minf(result, elevation(i))
	return result


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
	return goal.has_point(horizontal) and point.y < floor_height(horizontal) + 0.34


func terrain_tiles() -> Array[Dictionary]:
	_build_geometry()
	return _tiles


func wall_segments() -> Array[PackedFloat32Array]:
	_build_geometry()
	return _walls


func _build_geometry() -> void:
	if not _tiles.is_empty(): return
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
