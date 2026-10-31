class_name TiltPad
extends Control

signal vector_changed(value: Vector2)

var vector := Vector2.ZERO
var indicator := Vector2.ZERO
var active: bool = false
var _finger: int = -1
var _mouse: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func reset() -> void:
	_finger = -1
	_mouse = false
	vector = Vector2.ZERO
	vector_changed.emit(vector)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not active:
		return
	# Native Buttons use Godot's touch -> mouse emulation. The pad tracks real
	# fingers separately, so never consume their emulated mouse duplicates.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_mouse = true
		_set_vector_from_point(event.position)
		accept_event()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed and active and _finger == -1:
		var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if Rect2(Vector2.ZERO, size).has_point(local):
			_finger = event.index
			_set_vector_from_point(local)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and event.index == _finger and not event.pressed:
		reset()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and _mouse:
		reset()
	elif event is InputEventScreenDrag and event.index == _finger:
		_set_vector_from_point(get_global_transform_with_canvas().affine_inverse() * event.position)
	elif event is InputEventMouseMotion and _mouse:
		_set_vector_from_point(get_global_transform_with_canvas().affine_inverse() * event.position)


func _set_vector_from_point(point: Vector2) -> void:
	vector = ((point - size * 0.5) / (size.x * 0.38)).limit_length(1.0)
	vector_changed.emit(vector)
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := size.x * 0.46
	draw_circle(center, radius, Color("e8eff0"))
	draw_arc(center, radius, 0, TAU, 64, Color("cbd8db"), 1.5, true)
	draw_line(center - Vector2(24, 0), center + Vector2(24, 0), Color("c4d2d6"), 1.0, true)
	draw_line(center - Vector2(0, 24), center + Vector2(0, 24), Color("c4d2d6"), 1.0, true)
	draw_circle(center + indicator * radius * 0.65, 12.0, Color("ef493f"))
	draw_circle(center + indicator * radius * 0.65 - Vector2(2, 2), 3.0, Color(1, 1, 1, 0.65))
