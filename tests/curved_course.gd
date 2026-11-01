extends RefCounted
## A repeatable player input: collect the tail above the bend, then steer
## along the floor away from the open bank. No fluid markers are moved.
const DIRECTIONS: Array[Vector2] = [Vector2.DOWN, Vector2(1, 0.1), Vector2.DOWN, Vector2(-1, -1), Vector2.DOWN, Vector2(1, 0.75), Vector2.DOWN, Vector2.LEFT, Vector2(1, 0.75)]
const FRAMES: Array[int] = [100, 140, 60, 190, 60, 400, 400, 80, 400]
const TURN_SPEED: float = 1.4
