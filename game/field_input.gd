class_name FieldInput
extends Control
## Taps select a reservoir; drags turn the board in its horizontal plane.
signal rotation_changed(radians: float)
signal tapped(point: Vector2)
var active: bool = false
var rotation_enabled: bool = false
var plane_vector: Callable
var centre := Vector2.ZERO
var _finger: int = -1
var _mouse: bool = false
var _press := Vector2.ZERO
var _dragged: bool = false
var _last_vector := Vector2.ZERO
const MIN_RADIUS: float = 48.0
const TAP_SLOP: float = 12.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func reset() -> void:
	_finger = -1
	_mouse = false
	_dragged = false
	_last_vector = Vector2.ZERO


func is_dragging() -> bool:
	return _finger >= 0 or _mouse


func _allowed(point: Vector2) -> bool:
	return not Rect2(size.x - 160.0, 0, 160, 176).has_point(point)


func _vector(point: Vector2) -> Vector2:
	return plane_vector.call(point) if plane_vector.is_valid() else point - centre


func _begin(point: Vector2) -> void:
	_press = point
	_dragged = false
	_last_vector = _vector(point) if point.distance_to(centre) >= MIN_RADIUS else Vector2.ZERO


func _move(point: Vector2) -> void:
	_dragged = _dragged or point.distance_to(_press) > TAP_SLOP
	if not rotation_enabled or not _dragged: return
	if point.distance_to(centre) < MIN_RADIUS:
		_last_vector = Vector2.ZERO
		return
	var vector := _vector(point)
	if not _last_vector.is_zero_approx() and not vector.is_zero_approx():
		rotation_changed.emit(_last_vector.angle_to(vector))
	_last_vector = vector


func _end(point: Vector2) -> void:
	var is_tap := not _dragged and point.distance_to(_press) <= TAP_SLOP
	reset()
	if is_tap: tapped.emit(point)


func _input(event: InputEvent) -> void:
	if not active: return
	event = make_input_local(event)
	if event is InputEventScreenTouch:
		if event.pressed and _finger < 0 and _allowed(event.position):
			_finger = event.index
			_mouse = false
			_begin(event.position)
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _finger:
			_end(event.position)
	elif event is InputEventScreenDrag and event.index == _finger:
		_move(event.position)
		get_viewport().set_input_as_handled()
	elif event.device != InputEvent.DEVICE_ID_EMULATION and _finger < 0:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and _allowed(event.position):
				_mouse = true
				_begin(event.position)
			elif not event.pressed and _mouse: _end(event.position)
		elif event is InputEventMouseMotion and _mouse: _move(event.position)
