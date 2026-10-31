class_name TiltInput
extends RefCounted
## Portrait device axes -> board X/Z. Keyboard/touch use the same normalized input.

var sensitivity: float = 1.0
var neutral := Vector2.ZERO
var filtered := Vector2.ZERO
var touch := Vector2.ZERO
var has_sensor: bool = false
var use_touch: bool = false


func sensor_vector() -> Vector2:
	var raw := Input.get_gravity()
	if raw.length_squared() < 0.1:
		raw = Input.get_accelerometer()
	has_sensor = raw.length_squared() > 0.1
	return Vector2(raw.x, -raw.y)


func calibrate() -> void:
	neutral = sensor_vector()
	filtered = Vector2.ZERO


func sample(delta: float) -> Vector2:
	var raw := sensor_vector()
	var desired := Vector2.ZERO
	if has_sensor and not use_touch:
		desired = (raw - neutral) / 4.6 * sensitivity
		if desired.length() < 0.045:
			desired = Vector2.ZERO
	if use_touch or touch.length_squared() > 0.0:
		desired = touch * sensitivity
	var keyboard := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	if keyboard.length_squared() > 0.0:
		desired = keyboard.normalized()
	filtered = filtered.lerp(desired.limit_length(1.0), 1.0 - exp(-12.0 * delta))
	return filtered
