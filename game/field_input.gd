class_name FieldInput
extends Control
## Invisible drag control. Gameplay has no joystick or other persistent HUD.

signal vector_changed(value: Vector2)

var active: bool = false
var _finger: int = -1
var _mouse: bool = false
var _origin := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func reset() -> void:
	_finger = -1
	_mouse = false
	vector_changed.emit(Vector2.ZERO)


func _allowed(point: Vector2) -> bool:
	# Keep the pause button available, including before its GUI event is routed.
	return not Rect2(size.x - 132.0, 0, 132, 160).has_point(point)


func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventScreenTouch:
		if event.pressed and _finger == -1 and _allowed(event.position):
			_finger = event.index
			_origin = event.position
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _finger:
			reset()
	elif event is InputEventScreenDrag and event.index == _finger:
		vector_changed.emit(((event.position - _origin) / 145.0).limit_length(1.0))
	elif event.device != InputEvent.DEVICE_ID_EMULATION:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and _allowed(event.position):
				_mouse = true
				_origin = event.position
			elif not event.pressed and _mouse:
				reset()
		elif event is InputEventMouseMotion and _mouse:
			vector_changed.emit(((event.position - _origin) / 145.0).limit_length(1.0))
