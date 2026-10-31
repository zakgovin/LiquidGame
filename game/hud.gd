class_name HydrologicHUD
extends Control

signal start_requested
signal pause_requested
signal resume_requested
signal restart_requested
signal calibrate_requested
signal sensitivity_changed(value: float)
signal mode_changed(use_touch: bool)
signal touch_changed(value: Vector2)

const INK := Color("203740")
const MUTED := Color("6d8289")
const RED := Color("eb4c42")
const REGULAR = preload("res://assets/fonts/NotoSans-Regular.ttf")
const BOLD = preload("res://assets/fonts/NotoSans-Bold.ttf")

var pad: TiltPad
var progress: ProgressBar
var percent: Label
var hint: Label
var mode_button: Button
var pause_button: Button
var zero_button: Button
var slider: HSlider
var _modal: Control
var _use_touch: bool = false
var _toast_until: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var app_theme := Theme.new()
	app_theme.default_font = REGULAR
	app_theme.default_font_size = 19
	theme = app_theme
	_label("ГИДРОЛОГИКА / ПРОТОТИП", Vector2(36, 48), 17, RED, true)
	_label("HYDROLOGIC", Vector2(32, 78), 43, INK, true)
	pause_button = _button("Ⅱ", Rect2(612, 72, 72, 72), false, func(): pause_requested.emit())
	pause_button.tooltip_text = "Пауза (Esc)"
	_label("01", Vector2(36, 165), 27, RED, true)
	_label("ПЕРВЫЙ ПОТОК", Vector2(90, 170), 22, INK, true)
	_label("Направьте воду в красный сосуд", Vector2(36, 209), 19, MUTED)
	_label("H₂O", Vector2(625, 172), 23, MUTED, true)
	_line(Rect2(36, 254, 648, 1), Color("cddadd"))
	# White footer isolates the controls from architectural detail.
	_line(Rect2(0, 1000, 720, 280), Color("f6f9f8"))
	_line(Rect2(36, 1000, 648, 1), Color("cddadd"))
	_label("В ПРИЁМНИКЕ", Vector2(36, 1021), 16, MUTED, true)
	percent = _label("0%", Vector2(32, 1046), 43, INK, true)
	_label("ЦЕЛЬ 80%", Vector2(350, 1070), 16, MUTED, true)
	progress = ProgressBar.new()
	progress.position = Vector2(36, 1112)
	progress.size = Vector2(416, 6)
	progress.show_percentage = false
	progress.add_theme_font_size_override("font_size", 1)
	progress.add_theme_stylebox_override("background", _style(Color("dce6e8"), 3))
	progress.add_theme_stylebox_override("fill", _style(Color("159fc7"), 3))
	add_child(progress)
	# Mark the actual threshold, rather than implying the player needs 100%.
	_line(Rect2(36 + 416 * 0.8, 1108, 2, 14), RED)
	pad = TiltPad.new()
	pad.position = Vector2(521, 1016)
	pad.size = Vector2(154, 154)
	pad.vector_changed.connect(func(value: Vector2): touch_changed.emit(value))
	add_child(pad)
	_label("Чувствительность", Vector2(36, 1139), 16, MUTED)
	slider = HSlider.new()
	slider.position = Vector2(234, 1134)
	slider.size = Vector2(214, 40)
	slider.min_value = 0.5
	slider.max_value = 1.8
	slider.step = 0.1
	slider.value = 1.0
	slider.tooltip_text = "Чувствительность наклона"
	slider.value_changed.connect(func(value: float): sensitivity_changed.emit(value))
	add_child(slider)
	_button("Заново", Rect2(36, 1188, 196, 72), false, func(): restart_requested.emit())
	zero_button = _button("Ноль наклона", Rect2(246, 1188, 214, 72), false, func(): calibrate_requested.emit())
	mode_button = _button("Наклон", Rect2(474, 1188, 210, 72), false, _toggle_mode)
	hint = _label("", Vector2(36, 271), 16, MUTED)
	show_intro()


func update_state(fraction: float, tilt: Vector2, sensor: bool, running: bool) -> void:
	progress.value = fraction * 100.0
	percent.text = "%d%%" % floori(fraction * 100.0)
	pad.indicator = tilt
	pad.active = running and (_use_touch or not sensor)
	pad.queue_redraw()
	pause_button.disabled = not running and _modal != null
	if not sensor and not _use_touch:
		mode_button.text = "Касание"
		pad.active = running
	else:
		mode_button.text = "Касание" if _use_touch else "Наклон"
	zero_button.disabled = not sensor or _use_touch
	if _modal == null and Time.get_ticks_msec() > _toast_until:
		if sensor and not _use_touch:
			hint.text = "Плавно наклоняйте телефон · Ноль — калибровка"
		else:
			hint.text = "Управляйте кругом справа или клавишами WASD / ↑↓←→"


func show_intro() -> void:
	_modal_card("01 / ПЕРВЫЙ ПОТОК", "У воды свой путь", "Проведите воду по каналу в красный сосуд.\nДля победы соберите не менее 80%.\n\nДержите телефон удобно и нажмите «Начать»: \nэто положение станет нулём наклона.", "Начать", func():
		hide_modal()
		start_requested.emit(), false)


func show_pause() -> void:
	pad.reset()
	_modal_card("ПАУЗА", "Можно выдохнуть", "Поток остановлен.\n\n«Ноль наклона» запоминает удобное положение.\nНа компьютере работают WASD и стрелки.", "Продолжить", func():
		hide_modal()
		resume_requested.emit(), true)


func show_win(fraction: float) -> void:
	pad.reset()
	_modal_card("ПОТОК ДОСТАВЛЕН", "Отличное течение", "В приёмнике %d%% воды. Цель — 80%%.\n\nПервый уровень пройден.\nДальше — новые формы и свойства жидкости." % floori(fraction * 100.0), "Пройти ещё раз", func():
		hide_modal()
		restart_requested.emit(), false)


func hide_modal() -> void:
	if _modal != null:
		# Stay in the tree until the current native touch/mouse event has finished
		# propagating through Godot's GUI path.
		_modal.hide()
		_modal.queue_free()
		_modal = null


func toast(message: String) -> void:
	hint.text = message
	_toast_until = Time.get_ticks_msec() + 2000


func _toggle_mode() -> void:
	_use_touch = not _use_touch
	pad.reset()
	mode_changed.emit(_use_touch)


func _modal_card(kicker: String, title: String, body: String, action: String, callback: Callable, with_restart: bool) -> void:
	hide_modal()
	_modal = Control.new()
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_modal)
	var veil := ColorRect.new()
	veil.color = Color(0.91, 0.95, 0.95, 0.78)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(veil)
	var card := Panel.new()
	card.position = Vector2(40, 408)
	card.size = Vector2(640, 506 if with_restart else 466)
	var style := _style(Color("fcfefd"), 12)
	style.shadow_color = Color(0.1, 0.22, 0.26, 0.10)
	style.shadow_size = 26
	style.shadow_offset = Vector2(0, 10)
	card.add_theme_stylebox_override("panel", style)
	_modal.add_child(card)
	_label(kicker, Vector2(76, 440), 17, RED, true, _modal)
	_label(title, Vector2(72, 477), 35, INK, true, _modal)
	_label(body, Vector2(76, 548), 20, MUTED, false, _modal)
	_button(action, Rect2(76, 748, 568, 84), true, callback, _modal)
	if with_restart:
		_button("Начать заново", Rect2(76, 844, 568, 52), false, func():
			hide_modal()
			restart_requested.emit(), _modal)


func _label(text: String, at: Vector2, font_size: int, color: Color, bold: bool = false, parent: Node = self) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_override("font", BOLD if bold else REGULAR)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _button(text: String, bounds: Rect2, primary: bool, callback: Callable, parent: Node = self) -> Button:
	var button := Button.new()
	button.text = text
	button.position = bounds.position
	button.size = bounds.size
	button.add_theme_font_override("font", BOLD)
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", Color.WHITE if primary else INK)
	button.add_theme_color_override("font_hover_color", Color.WHITE if primary else INK)
	button.add_theme_color_override("font_pressed_color", Color.WHITE if primary else INK)
	button.add_theme_stylebox_override("normal", _style(RED if primary else Color("e6edef"), 8))
	button.add_theme_stylebox_override("hover", _style(Color("d43b35") if primary else Color("d9e4e7"), 8))
	button.add_theme_stylebox_override("pressed", _style(Color("bf3833") if primary else Color("cbdce0"), 8))
	button.add_theme_stylebox_override("disabled", _style(Color("edf2f2"), 8))
	button.add_theme_stylebox_override("focus", _outline())
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


static func _style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	return style


static func _outline() -> StyleBoxFlat:
	var style := _style(Color.TRANSPARENT, 8)
	style.border_color = Color("159fc7")
	style.set_border_width_all(2)
	return style


func _line(bounds: Rect2, color: Color) -> void:
	var line := ColorRect.new()
	line.position = bounds.position
	line.size = bounds.size
	line.color = color
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(line)
