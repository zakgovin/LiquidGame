extends Node3D

enum Screen { MENU, READY, PLAYING, PAUSED, SETTINGS, LEVELS, ABOUT, FINISHING, WON, FAILED }
const LEVELS: Array[LevelDefinition] = [preload("res://resources/first_level.tres"), preload("res://resources/second_level.tres")]
var level_index: int = 0
var level: LevelDefinition = LEVELS[0]
const WATER: LiquidProfile = preload("res://resources/water.tres")
const MAX_TILT: float = PI / 20.0 # Nine degrees; purely visual, never a second gravity.
const ROTATION_CAMERA_ELEVATION: float = PI * 65.0 / 180.0

var simulation: LiquidSimulation
var controls := TiltInput.new()
var turntable: Node3D
var pivot: Node3D
var surface: FluidSurface
var hud: HydrologicHUD
var board: HydrologicBoard
var sounds: SoundFeedback
var camera: Camera3D
var screen: Screen = Screen.MENU
var running: bool = false
var tilt_feedback: bool = true
var language_code: String = "ru"
var _render_tick: int = 0
var _screenshot_frame: int = -1
var _screenshot_path: String = ""
var opening: bool = false
var _opening_remaining: float = 0.0
var _paused_from: Screen = Screen.PLAYING
const OPEN_SECONDS: float = 0.70
const FINISH_SECONDS: float = 0.50
var finish_remaining: float = 0.0
var _finish_elapsed: float = 0.0
var _finish_delivered: int = 0
var _finish_tilt := Vector2.ZERO
const MAX_FINISH_SECONDS: float = 2.0
var _camera_size: float = 8.35
var _camera_offset: float = 0.0
var _camera_horizontal: float = 0.0
var _camera_basis := Basis.IDENTITY
var _fit_viewport := Vector2.ZERO
var _fit_rotation: bool = false
var _fit_feedback: bool = false
var rotation_angle: float = 0.0


func _ready() -> void:
	get_tree().auto_accept_quit = false
	_setup_environment()
	turntable = Node3D.new()
	add_child(turntable)
	pivot = Node3D.new()
	turntable.add_child(pivot)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = HydrologicHUD.new()
	canvas.add_child(hud)
	sounds = SoundFeedback.new()
	add_child(sounds)
	hud.interaction.connect(func(): sounds.play_event(&"click"))
	hud.start_requested.connect(_start)
	hud.restart_requested.connect(_restart)
	hud.pause_requested.connect(_pause)
	hud.resume_requested.connect(_resume)
	hud.menu_requested.connect(_menu)
	hud.settings_requested.connect(_settings)
	hud.about_requested.connect(_about)
	hud.levels_requested.connect(_levels)
	hud.level_selected.connect(_select_level)
	hud.next_requested.connect(_next_level)
	hud.language_changed.connect(_set_language)
	hud.sensitivity_changed.connect(func(value: float):
		controls.sensitivity = value
		_save_settings())
	hud.mode_changed.connect(_set_control_mode)
	hud.feedback_changed.connect(func(value: bool):
		tilt_feedback = value
		_save_settings())
	hud.sound_changed.connect(func(value: bool):
		sounds.set_enabled(value)
		_save_settings())
	hud.field.rotation_changed.connect(_rotate_field)
	hud.field.tapped.connect(_tap_field)
	hud.field.plane_vector = _rotation_vector
	_load_settings()
	_build_level()
	_configure_camera()
	controls.sensor_vector()
	_menu()
	var args := OS.get_cmdline_user_args()
	for i: int in range(args.size()):
		if args[i] == "--capture" and i + 1 < args.size():
			_screenshot_path = args[i + 1]
			_screenshot_frame = 30
			_start()


func _physics_process(delta: float) -> void:
	var tilt := controls.sample(delta)
	var world_tilt := input_to_world(Vector2.DOWN if controls.use_rotation else tilt)
	if screen == Screen.PLAYING and opening:
		_opening_remaining = maxf(0.0, _opening_remaining - delta)
		board.set_reservoir_open_amount(1.0 - _opening_remaining / OPEN_SECONDS)
		simulation.set_gate_opening(minf((1.0 - _opening_remaining / OPEN_SECONDS) / 0.30, 1.0))
		if _opening_remaining <= 0.0:
			opening = false
			hud.show_game(controls.use_rotation)
	if running:
		simulation.step(delta, world_tilt)
		board.show_spills(simulation.spill_points)
		_render_tick += 1
		if _render_tick % 2 == 0:
			surface.rebuild(simulation.positions, level, simulation.active, simulation.native_solver())
		hud.field.active = not opening and (controls.use_rotation)
		if simulation.completed:
			_begin_finish(world_tilt)
			return
		elif simulation.is_unwinnable():
			running = false
			screen = Screen.FAILED
			sounds.play_event(&"failure")
			hud.show_failure()
	if screen == Screen.FINISHING:
		# Let the tail of the stream reach the vessel before measuring the
		# result. The quiet interval is real foreground time, not fluid time.
		simulation.settle(delta, _finish_tilt)
		board.show_spills(simulation.spill_points)
		_render_tick += 1
		if _render_tick % 2 == 0:
			surface.rebuild(simulation.positions, level, simulation.active, simulation.native_solver())
		_finish_elapsed += delta
		if simulation.delivered_count > _finish_delivered + 8:
			_finish_delivered = simulation.delivered_count
			finish_remaining = FINISH_SECONDS
		finish_remaining = maxf(0.0, finish_remaining - delta)
		if simulation.goal_fraction < level.required_fraction:
			screen = Screen.PLAYING
			running = true
			board.set_goal_complete(false)
			hud.show_game(controls.use_rotation)
		elif finish_remaining <= 0.0 or _finish_elapsed >= MAX_FINISH_SECONDS:
			screen = Screen.WON
			sounds.play_event(&"complete")
			hud.show_win(simulation.delivered_count, level.particle_count, simulation.lost_count, level_index + 1 < LEVELS.size())
	if screen != Screen.PAUSED:
		_update_camera(delta)
		board.advance_effects(delta)
	var target := Vector3.ZERO
	if tilt_feedback and not controls.use_rotation and screen == Screen.PLAYING:
		var visible_tilt := world_tilt.normalized() * sqrt(world_tilt.length())
		target = Vector3(visible_tilt.y * MAX_TILT, 0.0, -visible_tilt.x * MAX_TILT)
	if screen != Screen.PAUSED:
		pivot.rotation = pivot.rotation.lerp(target, 1.0 - exp(-7.5 * delta))
		_position_source_hint()
	if _screenshot_frame > 0:
		_screenshot_frame -= 1
		if _screenshot_frame == 0:
			_capture.call_deferred()


func _fit_camera() -> void:
	if not is_instance_valid(pivot) or not is_instance_valid(hud): return
	var viewport_size := hud.size
	if viewport_size.x <= 0.0: viewport_size = get_viewport().get_visible_rect().size
	if _fit_viewport == viewport_size and _fit_rotation == controls.use_rotation and _fit_feedback == tilt_feedback: return
	_fit_viewport = viewport_size
	_fit_rotation = controls.use_rotation
	_fit_feedback = tilt_feedback
	var top := 136.0
	var bottom := 48.0
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	var poses: Array[Vector3] = [Vector3.ZERO]
	if controls.use_rotation:
		# Fit the swept 3D bounds once. Neither zoom nor framing changes as
		# the board turns or its reservoir opens.
		for i: int in range(64): poses.append(Vector3(0, TAU * i / 64.0, 0))
	elif tilt_feedback:
		poses += [Vector3(MAX_TILT, 0, MAX_TILT), Vector3(-MAX_TILT, 0, MAX_TILT), Vector3(MAX_TILT, 0, -MAX_TILT), Vector3(-MAX_TILT, 0, -MAX_TILT)]
	for pose: Vector3 in poses:
		var transform_basis := Basis.from_euler(pose)
		for x: float in [level.board_bounds.position.x, level.board_bounds.end.x]:
			for z: float in [level.board_bounds.position.y, level.board_bounds.end.y]:
				for y: float in [level.base_height - 0.10, level.board_top + 0.15]:
					var point := transform_basis * Vector3(x, y, z) - camera.position
					var projected := Vector2(camera.basis.x.dot(point), camera.basis.y.dot(point))
					low = low.min(projected)
					high = high.max(projected)
	var extent := high - low
	_camera_size = maxf(extent.x * viewport_size.x / maxf(300.0, viewport_size.x - 64.0), extent.y * viewport_size.x / maxf(420.0, viewport_size.y - top - bottom))
	_camera_horizontal = (high.x + low.x) * 0.5
	_camera_offset = (high.y + low.y) * 0.5 + (top - bottom) * 0.5 * _camera_size / viewport_size.x


func _update_camera(_delta: float) -> void:
	_fit_camera()
	camera.size = _camera_size
	camera.h_offset = _camera_horizontal
	camera.v_offset = _camera_offset
	hud.field.centre = camera.unproject_position(Vector3(0, 0.35, 0))


func _configure_camera() -> void:
	var target := Vector3(0, 0.2, 0)
	# Keep the 45-degree azimuth, but look down steeply enough to see into
	# the channels at every turn. Projection, framing and scale stay fixed.
	if controls.use_rotation:
		var horizontal := cos(ROTATION_CAMERA_ELEVATION) * 32.0 / sqrt(2.0)
		camera.position = target + Vector3(horizontal, sin(ROTATION_CAMERA_ELEVATION) * 32.0, horizontal)
	else:
		camera.position = Vector3(2.8, 24, 14)
	camera.look_at(target)
	_camera_basis = camera.basis
	_fit_viewport = Vector2.ZERO


func _rotation_vector(point: Vector2) -> Vector2:
	var hit: Variant = Plane(Vector3.UP, 0.35).intersects_ray(camera.project_ray_origin(point), camera.project_ray_normal(point))
	return Vector2(hit.x, hit.z) if hit is Vector3 else Vector2.ZERO


func _tap_field(point: Vector2) -> void:
	if screen != Screen.READY or opening: return
	var source := board.pick_source(camera.project_ray_origin(point), camera.project_ray_normal(point))
	if not source.is_empty(): _release(source)


func _position_source_hint() -> void:
	if screen != Screen.READY: return
	hud.position_source_hint(camera.unproject_position(board.to_global(board.source_anchor(level.reservoir_id))))


func _rotate_field(amount: float) -> void:
	if not controls.use_rotation or screen not in [Screen.READY, Screen.PLAYING] or opening: return
	rotation_angle = wrapf(rotation_angle + amount * controls.sensitivity, -PI, PI)
	turntable.rotation.y = -rotation_angle
	_position_source_hint()


func _set_control_mode(rotate: bool) -> void:
	var scroll_position := hud.settings_scroll.scroll_vertical
	controls.use_rotation = rotate
	controls.filtered = Vector2.ZERO
	rotation_angle = 0.0
	turntable.rotation = Vector3.ZERO
	_configure_camera()
	_save_settings()
	_settings()
	hud.settings_scroll.set_deferred("scroll_vertical", scroll_position)


func _begin_finish(tilt: Vector2 = Vector2.ZERO) -> void:
	running = false
	screen = Screen.FINISHING
	finish_remaining = FINISH_SECONDS
	_finish_elapsed = 0.0
	_finish_delivered = simulation.delivered_count
	_finish_tilt = tilt
	hud.show_game(false)
	board.set_goal_complete(true)
	surface.rebuild(simulation.positions, level, simulation.active, simulation.native_solver())


func _build_level() -> void:
	if is_instance_valid(board): board.free()
	# Release the previous native grid before allocating the next one.
	simulation = null
	level = LEVELS[level_index]
	board = HydrologicBoard.new()
	pivot.add_child(board)
	board.build(level)
	simulation = LiquidSimulation.new(level, WATER)
	if not is_instance_valid(surface):
		surface = FluidSurface.new(WATER)
		pivot.add_child(surface)
	surface.rebuild(simulation.positions, level, simulation.active, simulation.native_solver())
	_fit_viewport = Vector2.ZERO


func _change_level(index: int) -> bool:
	if index < 0 or index >= LEVELS.size(): return false
	running = false
	if index != level_index:
		level_index = index
		_build_level()
	_save_settings()
	return true


func _select_level(index: int) -> void:
	if _change_level(index): _menu()


func _next_level() -> void:
	if _change_level(level_index + 1): _restart()


func _start() -> void:
	_restart()


func input_to_world(value: Vector2) -> Vector2:
	if value.is_zero_approx(): return Vector2.ZERO
	var right := camera.global_basis.x
	var up := camera.global_basis.y
	var determinant := right.x * -up.z - right.z * -up.x
	var world := Vector2((value.x * -up.z - value.y * right.z) / determinant, (value.y * right.x + value.x * up.x) / determinant)
	var local := turntable.basis.inverse() * Vector3(world.x, 0, world.y)
	return Vector2(local.x, local.z).normalized() * value.length()


func world_to_input(value: Vector2) -> Vector2:
	if value.is_zero_approx(): return Vector2.ZERO
	var right := camera.global_basis.x
	var up := camera.global_basis.y
	var world := turntable.basis * Vector3(value.x, 0, value.y)
	return Vector2(right.dot(world), -up.dot(world)).normalized() * value.length()


func _release(source: StringName = &"") -> void:
	if source.is_empty(): source = level.reservoir_id
	if screen != Screen.READY or opening or source != level.reservoir_id: return
	controls.calibrate()
	opening = true
	running = true
	screen = Screen.PLAYING
	simulation.set_gate_opening(0.0)
	_opening_remaining = OPEN_SECONDS
	hud.show_ready(true, controls.use_rotation)
	sounds.play_event(&"start")


func _restart() -> void:
	simulation.reset()
	surface.rebuild(simulation.positions, level, simulation.active, simulation.native_solver())
	pivot.show()
	controls.filtered = Vector2.ZERO
	pivot.rotation = Vector3.ZERO
	rotation_angle = 0.0
	turntable.rotation = Vector3.ZERO
	_configure_camera()
	board.set_reservoir_open_amount(0.0)
	board.set_goal_complete(false)
	board.clear_effects()
	finish_remaining = 0.0
	opening = false
	running = false
	screen = Screen.READY
	hud.show_ready(false, controls.use_rotation)
	_update_camera(0.0)
	_position_source_hint()


func _pause() -> void:
	if screen in [Screen.PLAYING, Screen.READY, Screen.FINISHING]:
		_paused_from = screen
		running = false
		screen = Screen.PAUSED
		hud.show_pause()


func _resume() -> void:
	if screen != Screen.PAUSED:
		return
	controls.filtered = Vector2.ZERO
	screen = _paused_from
	running = screen == Screen.PLAYING
	if running and opening: hud.show_ready(true, controls.use_rotation)
	elif running: hud.show_game(controls.use_rotation)
	elif screen == Screen.FINISHING: hud.show_game(false)
	else: hud.show_ready(opening, controls.use_rotation)
	_position_source_hint()


func _menu() -> void:
	running = false
	screen = Screen.MENU
	pivot.hide()
	controls.filtered = Vector2.ZERO
	hud.show_menu(level.title, level_index + 1)


func _settings() -> void:
	running = false
	screen = Screen.SETTINGS
	pivot.hide()
	controls.sensor_vector()
	hud.show_settings(controls.sensitivity, controls.use_rotation, tilt_feedback, controls.has_sensor, sounds.enabled, language_code)


func _levels() -> void:
	running = false
	screen = Screen.LEVELS
	pivot.hide()
	hud.show_levels(LEVELS, level_index)


func _about() -> void:
	running = false
	screen = Screen.ABOUT
	pivot.hide()
	hud.show_about()


func _set_language(code: String) -> void:
	if code not in ["ru", "en"]: return
	var scroll_position := hud.settings_scroll.scroll_vertical
	language_code = code
	TranslationServer.set_locale(code)
	_save_settings()
	_settings()
	hud.settings_scroll.set_deferred("scroll_vertical", scroll_position)


func _back() -> void:
	match screen:
		Screen.PLAYING, Screen.READY, Screen.FINISHING: _pause()
		Screen.PAUSED: _resume()
		Screen.SETTINGS, Screen.LEVELS, Screen.ABOUT, Screen.WON, Screen.FAILED: _menu()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_back()
		elif controls.use_rotation and event.keycode in [KEY_Q, KEY_E]:
			_rotate_field(deg_to_rad(15.0) * (1.0 if event.keycode == KEY_E else -1.0))
		elif event.keycode == KEY_R and (screen in [Screen.PLAYING, Screen.READY, Screen.FINISHING]):
			_restart()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if is_instance_valid(hud):
			_pause()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().quit()


func _setup_environment() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("eaf0ef")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("e2f0f5")
	environment.ambient_light_energy = 1.0
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var sky := Sky.new()
	var sky_material := ShaderMaterial.new()
	sky_material.shader = preload("res://assets/materials/reflection_sky.gdshader")
	sky.sky_material = sky_material
	environment.sky = sky
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62, -28, 0)
	sun.light_color = Color("fff5e6")
	sun.light_energy = 0.22
	# Volume comes from the materials and fixed studio light. No moving
	# shadow maps, including those of the lid, hardware or transparent walls.
	sun.shadow_enabled = false
	add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = 8.35
	camera.position = Vector3(2.8, 24, 14)
	camera.far = 100.0
	add_child(camera)
	camera.look_at(Vector3(0, 0.2, 0))
	_camera_basis = camera.basis
	camera.current = true
	get_viewport().size_changed.connect(_fit_camera)


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("controls", "sensitivity", controls.sensitivity)
	config.set_value("controls", "mode", "rotation" if controls.use_rotation else "tilt")
	config.set_value("visual", "tilt_feedback", tilt_feedback)
	config.set_value("audio", "enabled", sounds.enabled)
	config.set_value("locale", "language", language_code)
	config.set_value("progress", "selected_level", level_index)
	config.save("user://settings.cfg")


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load("user://settings.cfg") == OK:
		controls.sensitivity = clampf(float(config.get_value("controls", "sensitivity", 1.0)), 0.5, 1.8)
		var legacy_rotation := bool(config.get_value("controls", "use_touch", false))
		controls.use_rotation = str(config.get_value("controls", "mode", "rotation" if legacy_rotation else "tilt")) == "rotation"
		tilt_feedback = bool(config.get_value("visual", "tilt_feedback", true))
		sounds.set_enabled(bool(config.get_value("audio", "enabled", true)))
		language_code = str(config.get_value("locale", "language", "ru"))
		level_index = clampi(int(config.get_value("progress", "selected_level", 0)), 0, LEVELS.size() - 1)
	if language_code not in ["ru", "en"]: language_code = "ru"
	TranslationServer.set_locale(language_code)
	if is_instance_valid(board) and level != LEVELS[level_index]: _build_level()


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(_screenshot_path)
	print("Capture: ", _screenshot_path, " status=", error)
	get_tree().quit(error)
