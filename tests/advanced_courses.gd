extends RefCounted
## World-space player actions shared by native, sensor and rotation checks.
static func directions(number: int) -> Array[Vector2]:
	match number:
		5: return [Vector2.DOWN, Vector2.RIGHT, Vector2.UP, Vector2.LEFT, Vector2.DOWN]
		6: return [Vector2.DOWN, Vector2(0.2, 0.12), Vector2(-1, 0.35), Vector2(1, 0.35), Vector2(0.35, 1)]
		7: return [Vector2.DOWN, Vector2.RIGHT, Vector2.DOWN]
		8: return [Vector2.DOWN, Vector2.DOWN, Vector2.RIGHT, Vector2.DOWN]
		9: return [Vector2.DOWN, Vector2.RIGHT, Vector2.DOWN]
	return []


static func frames(number: int) -> Array[int]:
	match number:
		5: return [500, 260, 650, 260, 600]
		6: return [300, 180, 120, 600, 480]
		7: return [300, 240, 360]
		8: return [240, 360, 320, 480]
		9: return [180, 210, 420]
	return []


const TURN_SPEED: float = 1.5
