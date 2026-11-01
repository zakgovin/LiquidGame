extends RefCounted
## World-space player inputs for the new lessons. Markers are never moved.
const BOTTLENECK_DIRECTIONS: Array[Vector2] = [Vector2.DOWN * 0.2]
const BOTTLENECK_FRAMES: Array[int] = [1500]
const FORK_DIRECTIONS: Array[Vector2] = [Vector2.DOWN, Vector2(-1, -0.2), Vector2.UP, Vector2(-0.5, 1), Vector2.DOWN]
const FORK_FRAMES: Array[int] = [300, 180, 240, 180, 400]
const TURN_SPEED: float = 1.5
