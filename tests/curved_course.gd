extends RefCounted
## A repeatable player input: collect the tail at each bend, then line up the
## jet before the cutout. These inputs do not move or replace fluid markers.
const DIRECTIONS: Array[Vector2] = [Vector2.DOWN, Vector2(1, 0.1), Vector2.DOWN, Vector2(-1, -0.18), Vector2(1, 0.55), Vector2.DOWN]
const FRAMES: Array[int] = [100, 140, 60, 190, 400, 400]
const TURN_SPEED: float = 2.0
