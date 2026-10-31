class_name HydrologicHUD
extends Control

signal start_requested
signal release_requested
signal pause_requested
signal restart_requested
signal resume_requested
signal menu_requested
signal settings_requested
signal about_requested
signal levels_requested
signal level_selected(index: int)
signal calibrate_requested
signal sensitivity_changed(value: float)
signal mode_changed(use_touch: bool)
signal feedback_changed(enabled: bool)
signal sound_changed(enabled: bool)
signal interaction

const INK := Color("203740")
const MUTED := Color("627981")
const RED := Color("eb4c42")
const PRIMARY := Color("087f9b")
const REGULAR = preload("res://assets/fonts/NotoSans-Regular.ttf")
const BOLD = preload("res://assets/fonts/NotoSans-Bold.ttf")

var field: FieldInput
var pause_button: Button
var page: Control
var brand: HydrologicBrand
var _modal: Control
var _frames: Array[Control] = []
var _calibration_status: Label
var _calibration_button: Button
var _sensor_available: bool = false
var buttons: Dictionary = {}
var slider: HSlider
var feedback_toggle: CheckButton
var sound_toggle: CheckButton
var settings_scroll: ScrollContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var app_theme := Theme.new()
	app_theme.default_font = REGULAR
	app_theme.default_font_size = 28
	theme = app_theme
	field = FieldInput.new()
	field.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(field)
	pause_button = _button("Ⅱ", Rect2(0, 0, 104, 104), false, func(): pause_requested.emit(), self, "pause")
	pause_button.tooltip_text = "Пауза"
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	for frame: Control in _frames:
		if is_instance_valid(frame): frame.position = (size - Vector2(720, 1280)) * 0.5
	pause_button.position = Vector2(size.x - 136, 32)


func _clear_page() -> void:
	hide_modal()
	if is_instance_valid(page):
		page.hide()
		page.queue_free()
	page = null
	brand = null
	_frames.clear()
	buttons.clear()
	buttons["pause"] = pause_button
	_calibration_status = null
	_calibration_button = null
	field.active = false
	field.reset()


func _layer(veil: float = 1.0) -> Control:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.93, 0.96, 0.96, veil)
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
	page = _layer()
	var frame := _frame(page)
	brand = HydrologicBrand.new()
	brand.position = Vector2(48, 140)
	brand.size = Vector2(624, 412)
	frame.add_child(brand)
	_button("01   " + level_title + "   ›", Rect2(48, 620, 624, 104), false, func(): levels_requested.emit(), frame, "levels")
	var play := _button("Играть", Rect2(48, 752, 624, 120), true, func(): start_requested.emit(), frame, "play")
	play.add_theme_font_size_override("font_size", 40)
	_button("Настройки", Rect2(48, 904, 300, 104), false, func(): settings_requested.emit(), frame, "settings")
	_button("Об игре", Rect2(372, 904, 300, 104), false, func(): about_requested.emit(), frame, "about")


func show_game(touch_enabled: bool) -> void:
	_clear_page()
	pause_button.show()
	field.active = touch_enabled


func show_ready(opening: bool = false) -> void:
	show_game(false)
	page = Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page)
	var card := PanelContainer.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	card.offset_left = 32
	card.offset_right = -32
	card.offset_top = -266
	card.offset_bottom = -32
	var style := _style(Color(0.98, 0.99, 0.99, 0.96), 24)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 16
	style.content_margin_bottom = 20
	card.add_theme_stylebox_override("panel", style)
	page.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	card.add_child(column)
	var caption := _text("Держите телефон удобно.\nОткройте резервуар, когда будете готовы.", column, 26)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var release := _button("Открываем…" if opening else "Открыть резервуар", Rect2(0, 0, 0, 104), true, func(): release_requested.emit(), column, "release")
	release.custom_minimum_size.y = 104
	release.disabled = opening


func _page_header(title: String) -> VBoxContainer:
	_clear_page()
	pause_button.hide()
	page = _layer()
	_label(title, Vector2(48, 56), 52, INK, true, page)
	settings_scroll = ScrollContainer.new()
	settings_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_scroll.offset_left = 48
	settings_scroll.offset_right = -48
	settings_scroll.offset_top = 160
	settings_scroll.offset_bottom = -192
	settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	settings_scroll.follow_focus = true
	page.add_child(settings_scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 24)
	settings_scroll.add_child(column)
	var footer := Panel.new()
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -168
	var style := _style(Color("f8fbfc"), 0)
	style.border_color = Color("d4e1e5")
	style.border_width_top = 2
	footer.add_theme_stylebox_override("panel", style)
	page.add_child(footer)
	_button("В главное меню", Rect2(48, 32, 624, 104), false, func(): menu_requested.emit(), footer, "back")
	return column


func show_levels(level_title: String) -> void:
	var column := _page_header("Уровни")
	_text("Выберите маршрут", column, 30)
	var level := _button("01   " + level_title, Rect2(0, 0, 0, 120), true, func(): level_selected.emit(0), column, "level_0")
	level.custom_minimum_size.y = 120
	_text("Полный виток по объёмному каналу.\nСтупени, инерция и переливание в сосуд.", column)
	_text("В прототипе пока доступен один уровень.", column, 26)


func show_settings(sensitivity: float, use_touch: bool, feedback: bool, sensor: bool, sound: bool = true) -> void:
	var column := _page_header("Настройки")
	_sensor_available = sensor
	_text("Управление", column, 34, true, INK)
	var choices := HBoxContainer.new()
	choices.add_theme_constant_override("separation", 0)
	column.add_child(choices)
	var group := ButtonGroup.new()
	for choice: int in range(2):
		var touch := choice == 1
		var option := _button("Касание" if touch else "Наклон", Rect2(0, 0, 0, 104), false, func(): _select_mode(touch), choices, "mode_touch" if touch else "mode_tilt")
		option.custom_minimum_size.y = 104
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.toggle_mode = true
		option.button_group = group
		option.button_pressed = use_touch == touch
		var selected := _style(Color("d0eef3"), 24)
		var normal_style := _style(Color("f3f7f8"), 0)
		normal_style.border_color = Color("77929b")
		normal_style.set_border_width_all(2)
		for appearance: StyleBoxFlat in [normal_style, selected]:
			appearance.corner_radius_top_left = 0 if touch else 52
			appearance.corner_radius_bottom_left = 0 if touch else 52
			appearance.corner_radius_top_right = 52 if touch else 0
			appearance.corner_radius_bottom_right = 52 if touch else 0
		option.add_theme_stylebox_override("normal", normal_style)
		selected.border_color = PRIMARY
		selected.set_border_width_all(2)
		option.add_theme_stylebox_override("pressed", selected)
		option.add_theme_color_override("font_pressed_color", PRIMARY)
		option.add_theme_color_override("font_hover_pressed_color", PRIMARY)
	_update_mode_labels(use_touch)
	var value_row := HBoxContainer.new()
	column.add_child(value_row)
	var caption := _text("Чувствительность", value_row, 30, false, INK)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var amount := _text("×%.1f" % sensitivity, value_row, 30, true, PRIMARY)
	amount.custom_minimum_size.x = 84
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	slider = HSlider.new()
	slider.custom_minimum_size.y = 96 # 48 dp hit area at the 720-unit canvas scale.
	slider.min_value = 0.5
	slider.max_value = 1.8
	slider.step = 0.1
	slider.value = sensitivity
	slider.scrollable = false
	slider.tick_count = 14
	slider.ticks_on_borders = true
	var track := _style(Color("d0dfe4"), 4)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", _style(PRIMARY, 4))
	slider.add_theme_stylebox_override("grabber_area_highlight", _style(PRIMARY, 4))
	for state: String in ["grabber", "grabber_highlight", "grabber_disabled"]:
		slider.add_theme_icon_override(state, preload("res://assets/ui/slider.svg"))
	slider.value_changed.connect(func(value: float):
		amount.text = "×%.1f" % value
		sensitivity_changed.emit(value))
	slider.drag_ended.connect(func(changed: bool):
		if changed: interaction.emit())
	var padding := MarginContainer.new()
	padding.add_theme_constant_override("margin_left", 20)
	padding.add_theme_constant_override("margin_right", 20)
	column.add_child(padding)
	padding.add_child(slider)
	var limits := HBoxContainer.new()
	column.add_child(limits)
	_text("Мягче  0,5", limits, 24)
	var faster := _text("Быстрее  1,8", limits, 24)
	faster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	faster.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_divider(column)
	feedback_toggle = _switch("Наклон поля", "Слегка поворачивать сцену вслед за телефоном", feedback, column)
	feedback_toggle.toggled.connect(func(value: bool):
		feedback_changed.emit(value)
		interaction.emit())
	sound_toggle = _switch("Звуки игры", "Нажатия, открытие резервуара и результат уровня", sound, column)
	sound_toggle.toggled.connect(func(value: bool):
		sound_changed.emit(value)
		interaction.emit())
	_divider(column)
	_calibration_button = _button("Калибровать наклон", Rect2(0, 0, 0, 104), false, func(): calibrate_requested.emit(), column, "calibrate")
	_calibration_button.custom_minimum_size.y = 104
	_calibration_button.disabled = not sensor or use_touch
	_calibration_status = _text("Держите телефон удобно и нажмите кнопку." if sensor else "Датчик не найден. Используйте касание экрана.", column, 26)
	_text("При ×1: первые 6° — спокойная зона, полный наклон — 36°.\n\nВ начале уровня вода закрыта. Положение телефона запомнится, когда вы откроете резервуар.", column, 26)


func _select_mode(touch: bool) -> void:
	_update_mode_labels(touch)
	if is_instance_valid(_calibration_button): _calibration_button.disabled = touch or not _sensor_available
	mode_changed.emit(touch)


func _update_mode_labels(touch: bool) -> void:
	buttons["mode_tilt"].text = "Наклон" if touch else "✓  Наклон"
	buttons["mode_touch"].text = "✓  Касание" if touch else "Касание"


func calibration_done() -> void:
	if is_instance_valid(_calibration_status): _calibration_status.text = "Удобное положение сохранено."


func _switch(title: String, description: String, value: bool, parent: Node) -> CheckButton:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 0)
	parent.add_child(group)
	var button := CheckButton.new()
	button.text = title
	button.button_pressed = value
	button.custom_minimum_size.y = 104
	button.add_theme_font_size_override("font_size", 32)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, INK)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, _style(Color.TRANSPARENT, 24))
	button.add_theme_icon_override("checked", preload("res://assets/ui/toggle_on.svg"))
	button.add_theme_icon_override("unchecked", preload("res://assets/ui/toggle_off.svg"))
	group.add_child(button)
	_text(description, group, 26)
	return button


func _divider(parent: Node) -> void:
	var divider := HSeparator.new()
	divider.add_theme_stylebox_override("separator", _style(Color("d4e1e5"), 0))
	divider.custom_minimum_size.y = 2
	parent.add_child(divider)


func show_about() -> void:
	var column := _page_header("Об игре")
	_text("Гидрологика / Hydrologic", column, 34, true, INK)
	_text("Откройте резервуар и направляйте воду наклоном телефона. Проведите поток по спирали в красный сосуд. Для победы доставьте не менее 80% воды.", column, 30)
	_text("Тёплые кромки отмечают ступени. Голубая линия на борту показывает его верхнюю границу. Резкие движения могут расплескать воду.", column)
	_text("Пауза останавливает поток. Из неё можно начать заново или вернуться в главное меню.", column)
	_text("Вода — первая жидкость прототипа. Дальше — новые свойства и взаимодействия.", column)
	_divider(column)
	_text("Авторы игры", column, 30, true, INK)
	_text("Zakhar Govin\nCodex (OpenAI)", column, 32, false, INK)
	_text("Версия 0.4.0\nGodot / godot-cpp · MIT\nNoto Sans · SIL OFL", column, 24)


func show_pause() -> void:
	field.active = false
	field.reset()
	var frame := _modal_card("Пауза", 580)
	_button("Продолжить", Rect2(96, 508, 528, 104), true, func(): resume_requested.emit(), frame, "resume")
	_button("Начать заново", Rect2(96, 636, 528, 104), false, func(): restart_requested.emit(), frame, "restart")
	_button("В главное меню", Rect2(96, 764, 528, 104), false, func(): menu_requested.emit(), frame, "exit")


func show_win(fraction: float) -> void:
	field.active = false
	field.reset()
	var frame := _modal_card("Уровень пройден", 500)
	_center_label("В сосуде %d%% воды" % floori(fraction * 100.0), 490, 28, MUTED, false, frame)
	_button("Ещё раз", Rect2(96, 574, 528, 104), true, func(): restart_requested.emit(), frame, "replay")
	_button("В главное меню", Rect2(96, 702, 528, 104), false, func(): menu_requested.emit(), frame, "win_menu")


func show_failure() -> void:
	field.active = false
	field.reset()
	var frame := _modal_card("Вода расплескалась", 500)
	_center_label("Оставшегося объёма недостаточно", 490, 26, MUTED, false, frame)
	_button("Начать заново", Rect2(96, 574, 528, 104), true, func(): restart_requested.emit(), frame, "retry")
	_button("В главное меню", Rect2(96, 702, 528, 104), false, func(): menu_requested.emit(), frame, "fail_menu")


func _modal_card(title: String, height: float) -> Control:
	hide_modal()
	_modal = _layer(0.64)
	var frame := _frame(_modal)
	var panel := Panel.new()
	panel.position = Vector2(56, 370)
	panel.size = Vector2(608, height)
	var style := _style(Color("fcfefd"), 28)
	style.shadow_size = 16
	style.shadow_color = Color(0.1, 0.2, 0.25, 0.10)
	panel.add_theme_stylebox_override("panel", style)
	frame.add_child(panel)
	_center_label(title, 416, 40, INK, true, frame)
	return frame


func hide_modal() -> void:
	if is_instance_valid(_modal):
		_modal.hide()
		_modal.queue_free()
	_modal = null


func _text(text: String, parent: Node, font_size: int = 28, bold: bool = false, color: Color = MUTED) -> Label:
	var label := _label(text, Vector2.ZERO, font_size, color, bold, parent)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


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
	button.add_theme_font_size_override("font_size", 30)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, Color.WHITE if primary else INK)
	button.add_theme_stylebox_override("normal", _style(RED if primary else Color("dfe9ed"), 28))
	button.add_theme_stylebox_override("hover", _style(Color("d43b35") if primary else Color("d4e4e9"), 28))
	button.add_theme_stylebox_override("pressed", _style(Color("bf3833") if primary else Color("bfd6de"), 28))
	button.add_theme_stylebox_override("disabled", _style(Color("e7edef"), 28))
	button.add_theme_color_override("font_disabled_color", MUTED.lightened(0.25))
	var focus := _style(Color.TRANSPARENT, 28)
	focus.border_color = PRIMARY
	focus.set_border_width_all(3)
	button.add_theme_stylebox_override("focus", focus)
	button.pressed.connect(func():
		interaction.emit()
		callback.call())
	parent.add_child(button)
	buttons[id] = button
	return button


static func _style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	return style
