class_name TiltInput
extends RefCounted
## Relative device inclination in radians; a deliberate 6° neutral zone and
## 36° full input replace the old very sensitive raw-acceleration mapping.

const DEAD_ANGLE: float = PI / 30.0
const FULL_ANGLE: float = PI / 5.0
var sensitivity: float = 1.0
var neutral := Vector2.ZERO
var filtered := Vector2.ZERO
var has_sensor: bool = false
var use_rotation: bool = false


func sensor_vector() -> Vector2:
	var raw := Input.get_gravity()
	if raw.length_squared() < 0.1: raw = Input.get_accelerometer()
	has_sensor = raw.length_squared() > 0.1
	if not has_sensor: return Vector2.ZERO
	var gravity := raw.normalized()
	return Vector2(asin(clampf(gravity.x, -1.0, 1.0)), asin(clampf(-gravity.y, -1.0, 1.0)))


func calibrate() -> void:
	neutral = sensor_vector()
	filtered = Vector2.ZERO


func sample(delta: float) -> Vector2:
	var angles := sensor_vector()
	var desired := Vector2.ZERO
	if has_sensor and not use_rotation:
		var relative := angles - neutral
		var magnitude := relative.length()
		if magnitude > DEAD_ANGLE:
			desired = relative / magnitude * clampf((magnitude - DEAD_ANGLE) / (FULL_ANGLE - DEAD_ANGLE) * sensitivity, 0.0, 1.0)
	var keyboard := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	if not use_rotation and keyboard.length_squared() > 0.0: desired = keyboard.normalized()
	filtered = filtered.lerp(desired.limit_length(1.0), 1.0 - exp(-10.0 * delta))
	return filtered
