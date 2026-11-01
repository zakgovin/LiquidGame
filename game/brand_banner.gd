class_name HydrologicBrand
extends Control
## One typographic lockup: architectural channels carry water into the title.

const INK := Color("203740")
const FONT = preload("res://assets/fonts/NotoSans-Bold.ttf")
const REGULAR = preload("res://assets/fonts/NotoSans-Regular.ttf")
var CHANNEL := PackedVector2Array([Vector2(76, 48), Vector2(76, 160), Vector2(202, 160), Vector2(202, 64), Vector2(332, 64), Vector2(332, 160), Vector2(466, 160), Vector2(466, 48), Vector2(548, 48)])
var phase: float = 0.0
var _redraw_time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(624, 412)
	var title := Label.new()
	title.text = tr("BRAND_TITLE")
	title.position = Vector2(24, 246)
	title.size = Vector2(576, 68)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", FONT)
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", INK)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	var subtitle := Label.new()
	subtitle.text = tr("BRAND_SUBTITLE")
	subtitle.position = Vector2(24, 326)
	subtitle.size = Vector2(576, 40)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_override("font", REGULAR)
	subtitle.add_theme_font_size_override("font_size", 24)
	subtitle.add_theme_color_override("font_color", Color("657e88"))
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(subtitle)


func _process(delta: float) -> void:
	phase = fposmod(phase + delta * 0.12, 1.0)
	_redraw_time += delta
	if _redraw_time >= 1.0 / 30.0:
		_redraw_time = 0.0
		queue_redraw()


func _draw() -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("f9fcfc")
	panel.border_color = Color("cfdee2")
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(28)
	panel.shadow_color = Color(0.16, 0.28, 0.32, 0.07)
	panel.shadow_size = 12
	panel.shadow_offset = Vector2(0, 6)
	draw_style_box(panel, Rect2(0, 0, 624, 412))
	# The channel, baseline and wordmark share the same frame and palette.
	draw_polyline(CHANNEL, Color("e0e9ec"), 42, true)
	draw_polyline(CHANNEL, Color("a6bec7"), 28, true)
	draw_polyline(CHANNEL, Color("19a8cb"), 21, true)
	var length := 0.0
	for i: int in range(CHANNEL.size() - 1): length += CHANNEL[i].distance_to(CHANNEL[i + 1])
	var remaining := (0.12 + phase * 0.88) * length
	var flow := PackedVector2Array([CHANNEL[0]])
	for i: int in range(CHANNEL.size() - 1):
		var distance := CHANNEL[i].distance_to(CHANNEL[i + 1])
		if remaining <= distance:
			flow.append(CHANNEL[i].lerp(CHANNEL[i + 1], remaining / distance))
			break
		flow.append(CHANNEL[i + 1])
		remaining -= distance
	draw_polyline(flow, Color("24b5d6"), 21, true)
	draw_polyline(flow, Color(0.58, 0.91, 0.98, 0.7), 3, true)
	draw_circle(flow[flow.size() - 1], 10.5, Color("24bce0"), true, -1, true)
	draw_rect(Rect2(539, 33, 18, 30), Color("ed4b42"))
	draw_line(Vector2(48, 220), Vector2(576, 220), Color("dce7e9"), 2, true)
	draw_line(Vector2(48, 220), Vector2(168, 220), Color("13afd6"), 3, true)
