class_name HydrologicHUD
extends Control

signal start_requested
signal pause_requested
signal restart_requested
signal resume_requested
signal menu_requested
signal settings_requested
signal about_requested
signal levels_requested
signal level_selected(index: int)
signal next_requested
signal collector_camera_requested
signal language_changed(code: String)
signal sensitivity_changed(value: float)
signal mode_changed(use_rotation: bool)
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
var collector_camera_button: Button
var page: Control
var brand: HydrologicBrand
var _modal: Control
var _frames: Array[Control] = []
var buttons: Dictionary = {}
var slider: HSlider
var feedback_toggle: CheckButton
var sound_toggle: CheckButton
var settings_scroll: ScrollContainer
var source_hint: PanelContainer


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
	pause_button.tooltip_text = tr("PAUSE")
	collector_camera_button = _button(tr("CAMERA_COLLECTOR"), Rect2(32,32,290,88), false, func(): collector_camera_requested.emit(), self, "collector_camera")
	collector_camera_button.add_theme_font_size_override("font_size", 24)
	collector_camera_button.hide()
	resized.connect(_layout)
	_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_instance_valid(pause_button): pause_button.tooltip_text = tr("PAUSE")


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
	source_hint = null
	brand = null
	_frames.clear()
	buttons.clear()
	buttons["pause"] = pause_button
	collector_camera_button.hide()
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


func show_menu(level_title: String, number: int = 1) -> void:
	_clear_page()
	pause_button.hide()
	page = _layer()
	var frame := _frame(page)
	brand = HydrologicBrand.new()
	brand.position = Vector2(48, 140)
	brand.size = Vector2(624, 412)
	frame.add_child(brand)
	_button("%02d   %s   ›" % [number, tr(level_title)], Rect2(48, 620, 624, 104), false, func(): levels_requested.emit(), frame, "levels")
	var play := _button(tr("PLAY"), Rect2(48, 752, 624, 120), true, func(): start_requested.emit(), frame, "play")
	play.add_theme_font_size_override("font_size", 40)
	_button(tr("SETTINGS"), Rect2(48, 904, 300, 104), false, func(): settings_requested.emit(), frame, "settings")
	_button(tr("ABOUT"), Rect2(372, 904, 300, 104), false, func(): about_requested.emit(), frame, "about")


func show_game(rotation_enabled: bool) -> void:
	_clear_page()
	pause_button.show()
	field.active = rotation_enabled
	field.rotation_enabled = rotation_enabled


func show_collector_camera(available: bool, focused: bool) -> void:
	collector_camera_button.visible = available
	collector_camera_button.text = tr("CAMERA_WATER" if focused else "CAMERA_COLLECTOR")
	if available: buttons["collector_camera"] = collector_camera_button
	else: buttons.erase("collector_camera")


func show_ready(opening: bool = false, rotate: bool = false) -> void:
	show_game(rotate and not opening)
	field.active = not opening
	page = Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page)
	if opening: return
	source_hint = PanelContainer.new()
	source_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	source_hint.add_theme_stylebox_override("panel", _style(Color(0.98, 0.99, 0.99, 0.92), 16))
	page.add_child(source_hint)
	var caption := Label.new()
	caption.text = tr("TAP_RESERVOIR")
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_color_override("font_color", INK)
	caption.add_theme_font_size_override("font_size", 24)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	source_hint.add_child(caption)
	source_hint.reset_size()


func position_source_hint(point: Vector2) -> void:
	if not is_instance_valid(source_hint): return
	source_hint.position = Vector2(clampf(point.x - source_hint.size.x * 0.5, 24.0, size.x - source_hint.size.x - 24.0), maxf(24.0, point.y - source_hint.size.y - 18.0))


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
	settings_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
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
	_button(tr("MAIN_MENU"), Rect2(48, 32, 624, 104), false, func(): menu_requested.emit(), footer, "back")
	return column


func show_levels(levels: Array[LevelDefinition], selected: int) -> void:
	var column := _page_header(tr("LEVELS"))
	_text(tr("CHOOSE_ROUTE"), column, 30)
	for i: int in range(levels.size()):
		var choice := _button("%02d   %s" % [i + 1, tr(levels[i].title)], Rect2(0, 0, 0, 120), i == selected, func(): level_selected.emit(i), column, "level_%d" % i)
		choice.custom_minimum_size.y = 120
		_text(tr(levels[i].description), column)
	_text(tr("LEVEL_COUNT"), column, 26)


func show_settings(sensitivity: float, use_rotation: bool, feedback: bool, sensor: bool, sound: bool = true, language: String = "ru") -> void:
	var content := _page_header(tr("SETTINGS"))
	var language_group := _settings_card(content)
	_text(tr("LANGUAGE"), language_group, 32, true, INK)
	_segments(["Русский", "English"], ["language_ru", "language_en"], 1 if language == "en" else 0, language_group, func(choice: int): language_changed.emit("en" if choice == 1 else "ru"))
	var controls_group := _settings_card(content)
	_text(tr("CONTROLS"), controls_group, 32, true, INK)
	_segments([tr("MODE_TILT"), tr("MODE_ROTATE")], ["mode_tilt", "mode_rotate"], 1 if use_rotation else 0, controls_group, func(choice: int): mode_changed.emit(choice == 1))
	if not sensor and not use_rotation: _text(tr("NO_SENSOR"), controls_group, 24)
	if use_rotation: _text(tr("ROTATION_HELP"), controls_group, 24)
	var sensitivity_group := _settings_card(content)
	sensitivity_group.name = "SensitivityGroup"
	var value_row := HBoxContainer.new()
	sensitivity_group.add_child(value_row)
	var caption := _text(tr("SENSITIVITY"), value_row, 32, true, INK)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var amount := _text("×%.1f" % sensitivity, value_row, 28, true, PRIMARY)
	amount.custom_minimum_size.x = 84
	amount.size_flags_horizontal = Control.SIZE_SHRINK_END
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	slider = HSlider.new()
	slider.custom_minimum_size.y = 96
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
	sensitivity_group.add_child(padding)
	padding.add_child(slider)
	var limits := HBoxContainer.new()
	sensitivity_group.add_child(limits)
	_text(tr("SOFTER"), limits, 24)
	var faster := _text(tr("FASTER"), limits, 24)
	faster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	faster.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_text(tr("ROTATION_SENSITIVITY") if use_rotation else tr("CONTROL_HELP"), sensitivity_group, 24)
	var feedback_group := _settings_card(content)
	_text(tr("FEEDBACK"), feedback_group, 32, true, INK)
	feedback_toggle = _switch(tr("TILT_FEEDBACK"), tr("TILT_ONLY") if use_rotation else tr("TILT_DESCRIPTION"), feedback, feedback_group)
	feedback_toggle.disabled = use_rotation
	feedback_toggle.toggled.connect(func(value: bool):
		feedback_changed.emit(value)
		interaction.emit())
	_divider(feedback_group)
	sound_toggle = _switch(tr("SOUNDS"), tr("SOUND_DESCRIPTION"), sound, feedback_group)
	sound_toggle.toggled.connect(func(value: bool):
		sound_changed.emit(value)
		interaction.emit())


func _settings_card(parent: Node) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var style := _style(Color("f8fbfc"), 24)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	style.border_color = Color("dce6ea")
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 12)
	panel.add_child(group)
	return group


func _segments(labels: Array[String], ids: Array[String], selected: int, parent: Node, changed: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	parent.add_child(row)
	var group := ButtonGroup.new()
	for i: int in range(labels.size()):
		var choice := i
		var option := _button(("✓  " if selected == i else "") + labels[i], Rect2(0, 0, 0, 104), false, func():
			for j: int in range(ids.size()): buttons[ids[j]].text = ("✓  " if choice == j else "") + labels[j]
			changed.call(choice), row, ids[i])
		option.custom_minimum_size.y = 104
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.toggle_mode = true
		option.button_group = group
		option.button_pressed = selected == i
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			var fill := Color("d0eef3") if state == "pressed" or state == "hover_pressed" else Color("f3f7f8")
			if state == "hover": fill = Color("e4f1f4")
			if state == "focus": fill = Color.TRANSPARENT
			var style := _style(fill, 0)
			style.corner_radius_top_left = 52 if i == 0 else 0
			style.corner_radius_bottom_left = 52 if i == 0 else 0
			style.corner_radius_top_right = 52 if i == labels.size() - 1 else 0
			style.corner_radius_bottom_right = 52 if i == labels.size() - 1 else 0
			style.border_color = Color("77929b") if state == "normal" else PRIMARY
			style.set_border_width_all(2)
			style.content_margin_left = 12
			style.content_margin_right = 12
			option.add_theme_stylebox_override(state, style)
		option.add_theme_color_override("font_pressed_color", PRIMARY)
		option.add_theme_color_override("font_hover_pressed_color", PRIMARY)


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
	var column := _page_header(tr("ABOUT"))
	_text(tr("ABOUT_NAME"), column, 34, true, INK)
	_text(tr("ABOUT_GAMEPLAY"), column, 30)
	_text(tr("ABOUT_HEIGHTS"), column)
	_text(tr("ABOUT_PAUSE"), column)
	_text(tr("ABOUT_FUTURE"), column)
	_divider(column)
	_text(tr("AUTHORS"), column, 30, true, INK)
	_text("Zakhar Govin\nCodex (OpenAI)", column, 32, false, INK)
	_text(tr("VERSION") % str(ProjectSettings.get_setting("application/config/version")), column, 24)


func show_pause() -> void:
	field.active = false
	field.reset()
	var frame := _modal_card(tr("PAUSE"), 580)
	_button(tr("CONTINUE"), Rect2(96, 508, 528, 104), true, func(): resume_requested.emit(), frame, "resume")
	_button(tr("RESTART"), Rect2(96, 636, 528, 104), false, func(): restart_requested.emit(), frame, "restart")
	_button(tr("MAIN_MENU"), Rect2(96, 764, 528, 104), false, func(): menu_requested.emit(), frame, "exit")


func show_win(delivered: int, total: int, lost: int, has_next: bool = false) -> void:
	field.active = false
	field.reset()
	var frame := _modal_card(tr("WIN_TITLE"), 628 if has_next else 500)
	_center_label(tr("WIN_VOLUME") % (100.0 * delivered / total), 472, 28, MUTED, false, frame)
	_center_label(tr("WIN_BALANCE") % [100.0 * (total - delivered - lost) / total, 100.0 * lost / total], 518, 22, MUTED, false, frame)
	if has_next:
		_button(tr("NEXT_LEVEL"), Rect2(96, 574, 528, 104), true, func(): next_requested.emit(), frame, "next")
	var offset := 128.0 if has_next else 0.0
	_button(tr("REPLAY"), Rect2(96, 574 + offset, 528, 104), not has_next, func(): restart_requested.emit(), frame, "replay")
	_button(tr("MAIN_MENU"), Rect2(96, 702 + offset, 528, 104), false, func(): menu_requested.emit(), frame, "win_menu")


func show_failure() -> void:
	field.active = false
	field.reset()
	var frame := _modal_card(tr("FAIL_TITLE"), 500)
	_center_label(tr("FAIL_HINT"), 490, 26, MUTED, false, frame)
	_button(tr("RESTART"), Rect2(96, 574, 528, 104), true, func(): restart_requested.emit(), frame, "retry")
	_button(tr("MAIN_MENU"), Rect2(96, 702, 528, 104), false, func(): menu_requested.emit(), frame, "fail_menu")


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
