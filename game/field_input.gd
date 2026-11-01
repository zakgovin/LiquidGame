class_name FieldInput
extends Control
## Rotate around the visible field centre. The UI stays upright.
signal rotation_changed(radians: float)
var active: bool = false
var centre := Vector2.ZERO
var blocked_bottom: float = 0.0
var _finger: int = -1
var _mouse: bool = false
var _last_vector := Vector2.ZERO
const MIN_RADIUS: float = 48.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func reset() -> void:
	_finger = -1
	_mouse = false
	_last_vector = Vector2.ZERO


func is_dragging() -> bool:
	return _finger >= 0 or _mouse


func _allowed(point: Vector2) -> bool:
	return point.y < size.y - blocked_bottom and not Rect2(size.x - 160.0, 0, 160, 176).has_point(point) and point.distance_to(centre) >= MIN_RADIUS


func _move(point: Vector2) -> void:
	var vector := point - centre
	if vector.length() < MIN_RADIUS:
		_last_vector = Vector2.ZERO
		return
	if not _last_vector.is_zero_approx():
		rotation_changed.emit(_last_vector.angle_to(vector))
	_last_vector = vector


func _input(event: InputEvent) -> void:
	if not active: return
	event = make_input_local(event)
	if event is InputEventScreenTouch:
		if event.pressed and _finger < 0 and _allowed(event.position):
			_finger = event.index
			_mouse = false
			_last_vector = event.position - centre
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _finger:
			reset()
	elif event is InputEventScreenDrag and event.index == _finger:
		_move(event.position)
		get_viewport().set_input_as_handled()
	elif event.device != InputEvent.DEVICE_ID_EMULATION and _finger < 0:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and _allowed(event.position):
				_mouse = true
				_last_vector = event.position - centre
			elif not event.pressed and _mouse: reset()
		elif event is InputEventMouseMotion and _mouse: _move(event.position)
