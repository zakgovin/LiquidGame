class_name HydrologicHUD
extends Control

signal start_requested
signal pause_requested
signal resume_requested
signal restart_requested
signal menu_requested
signal settings_requested
signal about_requested
signal levels_requested
signal level_selected(index: int)
signal calibrate_requested
signal sensitivity_changed(value: float)
signal mode_changed(use_touch: bool)
signal feedback_changed(enabled: bool)

const INK := Color("203740")
const MUTED := Color("6d8289")
const RED := Color("eb4c42")
const REGULAR = preload("res://assets/fonts/NotoSans-Regular.ttf")
const BOLD = preload("res://assets/fonts/NotoSans-Bold.ttf")

var field: FieldInput
var pause_button: Button
var page: Control
var _modal: Control
var _frames: Array[Control] = []
var _calibration_status: Label
var buttons: Dictionary = {}
var slider: HSlider
var mode_picker: OptionButton
var feedback_toggle: CheckButton


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var app_theme := Theme.new()
	app_theme.default_font = REGULAR
	app_theme.default_font_size = 24
	theme = app_theme
	field = FieldInput.new()
	field.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(field)
	pause_button = _button("Ⅱ", Rect2(0, 0, 96, 96), false, func(): pause_requested.emit(), self, "pause")
	pause_button.tooltip_text = "Пауза"
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	for frame: Control in _frames:
		if is_instance_valid(frame):
			frame.position = (size - Vector2(720, 1280)) * 0.5
	pause_button.position = Vector2(size.x - 124, 32)


func _clear_page() -> void:
	hide_modal()
	if is_instance_valid(page):
		page.hide()
		page.queue_free()
	page = null
	_frames.clear()
	buttons.clear()
	buttons["pause"] = pause_button
	_calibration_status = null
	field.active = false
	field.reset()


func _layer(veil: float = 0.98) -> Control:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.92, 0.95, 0.94, veil)
	layer.add_child(background)
	return layer


func _frame(parent: Control) -> Control:
	var frame := Control.new()
	frame.position = (size - Vector2(720, 1280)) * 0.5
	frame.size = Vector2(720, 1280)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(frame)
	_frames.append(frame)
	return frame


func show_menu(level_title: String) -> void:
	_clear_page()
	pause_button.hide()
	page = _layer(0.94)
	var frame := _frame(page)
	var icon := TextureRect.new()
	icon.texture = preload("res://assets/icon.svg")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = Vector2(296, 230)
	icon.size = Vector2(128, 128)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(icon)
	_center_label("ГИДРОЛОГИКА", 394, 49, INK, true, frame)
	_center_label("HYDROLOGIC", 463, 21, MUTED, false, frame)
	_button("01  /  " + level_title + "   ›", Rect2(80, 578, 560, 88), false, func(): levels_requested.emit(), frame, "levels")
	_button("Играть", Rect2(80, 690, 560, 112), true, func(): start_requested.emit(), frame, "play")
	_button("Настройки", Rect2(80, 832, 272, 96), false, func(): settings_requested.emit(), frame, "settings")
	_button("Об игре", Rect2(368, 832, 272, 96), false, func(): about_requested.emit(), frame, "about")


func show_game(touch_enabled: bool) -> void:
	_clear_page()
	pause_button.show()
	field.active = touch_enabled


func show_levels(level_title: String) -> void:
	var frame := _page_header("Уровни")
	_label("Выберите маршрут", Vector2(80, 310), 25, MUTED, false, frame)
	_button("01   " + level_title, Rect2(80, 382, 560, 120), true, func(): level_selected.emit(0), frame, "level_0")
	_label("Полный виток вокруг центрального сосуда", Vector2(80, 540), 23, MUTED, false, frame)
	_label("В прототипе пока доступен один уровень.", Vector2(80, 596), 23, MUTED, false, frame)


func show_settings(sensitivity: float, use_touch: bool, feedback: bool, sensor: bool) -> void:
	var frame := _page_header("Настройки")
	_label("Управление", Vector2(80, 304), 26, INK, true, frame)
	mode_picker = OptionButton.new()
	mode_picker.position = Vector2(80, 356)
	mode_picker.size = Vector2(560, 80)
	mode_picker.add_item("Наклон телефона")
	mode_picker.add_item("Касание экрана")
	mode_picker.select(1 if use_touch else 0)
	mode_picker.add_theme_font_size_override("font_size", 26)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		mode_picker.add_theme_color_override(state, INK)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		mode_picker.add_theme_stylebox_override(state, _style(Color("e3ebed"), 10))
	mode_picker.item_selected.connect(func(index: int): mode_changed.emit(index == 1))
	frame.add_child(mode_picker)
	var sensitivity_label := _label("Чувствительность  ×%.1f" % sensitivity, Vector2(80, 484), 25, INK, false, frame)
	slider = HSlider.new()
	slider.position = Vector2(80, 538)
	slider.size = Vector2(560, 56)
	slider.min_value = 0.5
	slider.max_value = 1.8
	slider.step = 0.1
	slider.value = sensitivity
	var track := _style(Color("ccdadd"), 3)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", _style(Color("159fc7"), 3))
	slider.add_theme_stylebox_override("grabber_area_highlight", _style(Color("159fc7"), 3))
	for state: String in ["grabber", "grabber_highlight", "grabber_disabled"]:
		slider.add_theme_icon_override(state, preload("res://assets/ui/slider.svg"))
	slider.value_changed.connect(func(value: float):
		sensitivity_label.text = "Чувствительность  ×%.1f" % value
		sensitivity_changed.emit(value))
	frame.add_child(slider)
	feedback_toggle = CheckButton.new()
	feedback_toggle.position = Vector2(80, 624)
	feedback_toggle.size = Vector2(560, 76)
	feedback_toggle.text = "Наклонять поле вслед за телефоном"
	feedback_toggle.button_pressed = feedback
	feedback_toggle.add_theme_font_size_override("font_size", 24)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		feedback_toggle.add_theme_color_override(state, INK)
	feedback_toggle.add_theme_icon_override("checked", preload("res://assets/ui/toggle_on.svg"))
	feedback_toggle.add_theme_icon_override("unchecked", preload("res://assets/ui/toggle_off.svg"))
	feedback_toggle.toggled.connect(func(value: bool): feedback_changed.emit(value))
	frame.add_child(feedback_toggle)
	var zero := _button("Калибровать наклон", Rect2(80, 750, 560, 88), false, func(): calibrate_requested.emit(), frame, "calibrate")
	zero.disabled = not sensor
	_calibration_status = _label("Держите телефон удобно и нажмите кнопку." if sensor else "Датчик не найден. Доступно касание экрана.", Vector2(80, 864), 22, MUTED, false, frame)
	_label("Касание: ведите пальцем по игровому полю.\nНаклон калибруется также при нажатии «Играть».", Vector2(80, 964), 22, MUTED, false, frame)


func calibration_done() -> void:
	if is_instance_valid(_calibration_status):
		_calibration_status.text = "Удобное положение сохранено."


func show_about() -> void:
	var frame := _page_header("Об игре")
	_label("Гидрологика / Hydrologic", Vector2(80, 320), 31, INK, true, frame)
	_label("Направляйте воду наклоном телефона.\nПроведите поток по спирали в красный сосуд.\nДля победы доставьте не менее 80% воды.\n\nПауза останавливает поток.\nИз неё можно начать заново или вернуться\nв главное меню.\n\nВода — первая жидкость прототипа.\nДальше — новые свойства и взаимодействия.", Vector2(80, 400), 24, MUTED, false, frame)
	_label("Версия 0.2.0\nGodot · MIT   /   Noto Sans · SIL OFL", Vector2(80, 1016), 21, MUTED, false, frame)


func _page_header(title: String) -> Control:
	_clear_page()
	pause_button.hide()
	page = _layer()
	var frame := _frame(page)
	_button("‹  Главное меню", Rect2(48, 110, 300, 88), false, func(): menu_requested.emit(), frame, "back")
	_label(title, Vector2(80, 224), 44, INK, true, frame)
	return frame


func show_pause() -> void:
	field.active = false
	field.reset()
	var frame := _modal_card("Пауза", 540)
	_button("Продолжить", Rect2(96, 510, 528, 88), true, func(): resume_requested.emit(), frame, "resume")
	_button("Начать заново", Rect2(96, 616, 528, 88), false, func(): restart_requested.emit(), frame, "restart")
	_button("Выйти", Rect2(96, 722, 528, 88), false, func(): menu_requested.emit(), frame, "exit")


func show_win(fraction: float) -> void:
	field.active = false
	field.reset()
	var frame := _modal_card("Уровень пройден", 480)
	_center_label("В сосуде %d%% воды" % floori(fraction * 100.0), 490, 24, MUTED, false, frame)
	_button("Ещё раз", Rect2(96, 574, 528, 88), true, func(): restart_requested.emit(), frame, "replay")
	_button("В главное меню", Rect2(96, 680, 528, 88), false, func(): menu_requested.emit(), frame, "win_menu")


func _modal_card(title: String, height: float) -> Control:
	hide_modal()
	_modal = _layer(0.64)
	var frame := _frame(_modal)
	var panel := Panel.new()
	panel.position = Vector2(56, 370)
	panel.size = Vector2(608, height)
	var style := _style(Color("fcfefd"), 16)
	style.shadow_size = 22
	style.shadow_color = Color(0.1, 0.2, 0.25, 0.12)
	panel.add_theme_stylebox_override("panel", style)
	frame.add_child(panel)
	_center_label(title, 416, 38, INK, true, frame)
	return frame


func hide_modal() -> void:
	if is_instance_valid(_modal):
		_modal.hide()
		_modal.queue_free()
	_modal = null


func _center_label(text: String, y: float, font_size: int, color: Color, bold: bool, parent: Node) -> Label:
	var label := _label(text, Vector2(40, y), font_size, color, bold, parent)
	label.size.x = 640
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _label(text: String, at: Vector2, font_size: int, color: Color, bold: bool, parent: Node) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_override("font", BOLD if bold else REGULAR)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _button(text: String, bounds: Rect2, primary: bool, callback: Callable, parent: Node, id: String) -> Button:
	var button := Button.new()
	button.text = text
	button.position = bounds.position
	button.size = bounds.size
	button.add_theme_font_override("font", BOLD)
	button.add_theme_font_size_override("font_size", 26)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(state, Color.WHITE if primary else INK)
	button.add_theme_stylebox_override("normal", _style(RED if primary else Color("e3ebed"), 10))
	button.add_theme_stylebox_override("hover", _style(Color("d43b35") if primary else Color("d9e4e7"), 10))
	button.add_theme_stylebox_override("pressed", _style(Color("bf3833") if primary else Color("cbdce0"), 10))
	button.add_theme_stylebox_override("disabled", _style(Color("edf2f2"), 10))
	button.add_theme_color_override("font_disabled_color", MUTED.lightened(0.25))
	var focus := _style(Color.TRANSPARENT, 10)
	focus.border_color = Color("159fc7")
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override("focus", focus)
	button.pressed.connect(callback)
	parent.add_child(button)
	buttons[id] = button
	return button


static func _style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	return style
