class_name LevelDefinition
extends Resource
## World coordinates are (x, z); a fixed camera looks down onto this plane.

@export var title: String
@export var floor_regions: Array[Rect2] = []
@export var outline: PackedVector2Array
@export var spawn: Rect2
@export var goal: Rect2
@export var particle_count: int = 288
@export_range(0.0, 1.0) var required_fraction: float = 0.8
@export var hold_seconds: float = 0.75
@export var board_bounds: Rect2 = Rect2(-2.95, -4.9, 5.9, 9.8)
@export var route: PackedVector2Array


func contains(point: Vector2, margin: float = 0.0) -> bool:
	for region: Rect2 in floor_regions:
		if region.grow(-margin).has_point(point):
			return true
	return false


func constrain(point: Vector2, margin: float) -> Vector2:
	if contains(point, margin):
		return point
	var closest := point
	var best := INF
	for region: Rect2 in floor_regions:
		var bounds := region.grow(-margin)
		var candidate := point.clamp(bounds.position, bounds.end)
		var distance := point.distance_squared_to(candidate)
		if distance < best:
			closest = candidate
			best = distance
	return closest
