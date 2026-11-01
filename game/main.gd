extends Node3D

enum Screen { MENU, READY, PLAYING, PAUSED, SETTINGS, LEVELS, ABOUT, FINISHING, WON, FAILED }
const LEVEL: LevelDefinition = preload("res://resources/first_level.tres")
const WATER: LiquidProfile = preload("res://resources/water.tres")
const MAX_TILT: float = PI / 45.0 # Four degrees; purely visual, never a second gravity.

var simulation: LiquidSimulation
var controls := TiltInput.new()
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
var _camera_size: float = 8.35
var _camera_offset: float = 0.0


func _ready() -> void:
	get_tree().auto_accept_quit = false
	_setup_environment()
	pivot = Node3D.new()
	add_child(pivot)
	board = HydrologicBoard.new()
	pivot.add_child(board)
	board.build(LEVEL)
	simulation = LiquidSimulation.new(LEVEL, WATER)
	surface = FluidSurface.new(WATER)
	pivot.add_child(surface)
	surface.rebuild(simulation.positions, LEVEL, simulation.active, simulation.native_solver())
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = HydrologicHUD.new()
	canvas.add_child(hud)
	sounds = SoundFeedback.new()
	add_child(sounds)
	hud.interaction.connect(func(): sounds.play_event(&"click"))
	hud.start_requested.connect(_start)
	hud.release_requested.connect(_release)
	hud.restart_requested.connect(_restart)
	hud.pause_requested.connect(_pause)
	hud.resume_requested.connect(_resume)
	hud.menu_requested.connect(_menu)
	hud.settings_requested.connect(_settings)
	hud.about_requested.connect(_about)
	hud.levels_requested.connect(_levels)
	hud.level_selected.connect(func(_index: int): _menu())
	hud.language_changed.connect(_set_language)
	hud.sensitivity_changed.connect(func(value: float):
		controls.sensitivity = value
		_save_settings())
	hud.mode_changed.connect(func(value: bool):
		controls.use_touch = value
		_save_settings())
	hud.feedback_changed.connect(func(value: bool):
		tilt_feedback = value
		_save_settings())
	hud.sound_changed.connect(func(value: bool):
		sounds.set_enabled(value)
		_save_settings())
	hud.field.vector_changed.connect(func(value: Vector2): controls.touch = value)
	_load_settings()
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
	var world_tilt := input_to_world(tilt)
	if screen == Screen.PLAYING and opening:
		_opening_remaining = maxf(0.0, _opening_remaining - delta)
		board.set_reservoir_open_amount(1.0 - _opening_remaining / OPEN_SECONDS)
		simulation.set_gate_opening(minf((1.0 - _opening_remaining / OPEN_SECONDS) / 0.30, 1.0))
		if _opening_remaining <= 0.0:
			opening = false
			hud.show_game(controls.use_touch or not controls.has_sensor)
			_fit_camera()
	if running:
		simulation.step(delta, world_tilt)
		_render_tick += 1
		if _render_tick % 2 == 0:
			surface.rebuild(simulation.positions, LEVEL, simulation.active, simulation.native_solver())
		hud.field.active = not opening and (controls.use_touch or not controls.has_sensor)
		if simulation.completed:
			_begin_finish()
			return
		elif simulation.is_unwinnable():
			running = false
			screen = Screen.FAILED
			sounds.play_event(&"failure")
			hud.show_failure()
	if screen == Screen.FINISHING:
		finish_remaining = maxf(0.0, finish_remaining - delta)
		if finish_remaining <= 0.0:
			screen = Screen.WON
			hud.show_win(simulation.goal_fraction)
	if screen != Screen.PAUSED:
		camera.size = lerpf(camera.size, _camera_size, 1.0 - exp(-5.0 * delta))
		camera.v_offset = lerpf(camera.v_offset, _camera_offset, 1.0 - exp(-5.0 * delta))
	var target := Vector3.ZERO
	if tilt_feedback and screen == Screen.PLAYING:
		target = Vector3(world_tilt.y * MAX_TILT, 0.0, -world_tilt.x * MAX_TILT)
	if screen != Screen.PAUSED:
		pivot.rotation = pivot.rotation.lerp(target, 1.0 - exp(-7.5 * delta))
	if _screenshot_frame > 0:
		_screenshot_frame -= 1
		if _screenshot_frame == 0:
			_capture.call_deferred()


func _fit_camera() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var preparing := screen == Screen.READY or opening
	var reserved := 440.0 if preparing else 180.0
	_camera_size = maxf(8.35, 10.4 * viewport_size.x / maxf(500.0, viewport_size.y - reserved))
	_camera_offset = -80.0 * _camera_size / viewport_size.x if preparing else 0.0


func _begin_finish() -> void:
	running = false
	screen = Screen.FINISHING
	finish_remaining = FINISH_SECONDS
	controls.touch = Vector2.ZERO
	hud.show_game(false)
	board.set_goal_complete(true)
	surface.rebuild(simulation.positions, LEVEL, simulation.active, simulation.native_solver())
	sounds.play_event(&"complete")


func _start() -> void:
	_restart()


func input_to_world(value: Vector2) -> Vector2:
	if value.is_zero_approx(): return Vector2.ZERO
	var right := camera.global_basis.x
	var up := camera.global_basis.y
	var determinant := right.x * -up.z - right.z * -up.x
	var world := Vector2((value.x * -up.z - value.y * right.z) / determinant, (value.y * right.x + value.x * up.x) / determinant)
	return world.normalized() * value.length()


func world_to_input(value: Vector2) -> Vector2:
	if value.is_zero_approx(): return Vector2.ZERO
	var right := camera.global_basis.x
	var up := camera.global_basis.y
	return Vector2(right.x * value.x + right.z * value.y, -up.x * value.x - up.z * value.y).normalized() * value.length()


func _release() -> void:
	if screen != Screen.READY or opening: return
	controls.calibrate()
	controls.touch = Vector2.ZERO
	opening = true
	running = true
	screen = Screen.PLAYING
	simulation.set_gate_opening(0.0)
	_opening_remaining = OPEN_SECONDS
	hud.show_ready(true)
	sounds.play_event(&"start")


func _restart() -> void:
	simulation.reset()
	surface.rebuild(simulation.positions, LEVEL, simulation.active, simulation.native_solver())
	pivot.show()
	controls.filtered = Vector2.ZERO
	controls.touch = Vector2.ZERO
	pivot.rotation = Vector3.ZERO
	board.set_reservoir_open_amount(0.0)
	board.set_goal_complete(false)
	finish_remaining = 0.0
	opening = false
	running = false
	screen = Screen.READY
	_fit_camera()
	camera.size = _camera_size
	camera.v_offset = _camera_offset
	hud.show_ready()


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
	controls.touch = Vector2.ZERO
	screen = _paused_from
	running = screen == Screen.PLAYING
	if running and opening: hud.show_ready(true)
	elif running: hud.show_game(controls.use_touch or not controls.has_sensor)
	elif screen == Screen.FINISHING: hud.show_game(false)
	else: hud.show_ready(opening)


func _menu() -> void:
	running = false
	screen = Screen.MENU
	pivot.hide()
	controls.touch = Vector2.ZERO
	controls.filtered = Vector2.ZERO
	hud.show_menu(LEVEL.title)


func _settings() -> void:
	running = false
	screen = Screen.SETTINGS
	pivot.hide()
	controls.sensor_vector()
	hud.show_settings(controls.sensitivity, controls.use_touch, tilt_feedback, controls.has_sensor, sounds.enabled, language_code)


func _levels() -> void:
	running = false
	screen = Screen.LEVELS
	pivot.hide()
	hud.show_levels(LEVEL.title)


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
	environment.ambient_light_energy = 0.28
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("9dbad0")
	sky_material.sky_horizon_color = Color("f3f8fa")
	sky_material.ground_horizon_color = Color("e1edf2")
	sky_material.ground_bottom_color = Color("a7bdc9")
	sky.sky_material = sky_material
	environment.sky = sky
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62, -28, 0)
	sun.light_color = Color("fff5e6")
	sun.light_energy = 0.22
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.33
	sun.shadow_bias = 0.1
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 24
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	ground.position.y = -1.15
	ground.material_override = HydrologicBoard._material(Color("eaf0ef"), 1.0)
	add_child(ground)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = 8.35
	camera.position = Vector3(2.8, 24, 14)
	camera.far = 100.0
	add_child(camera)
	camera.look_at(Vector3(0, 0.2, 0))
	camera.current = true
	get_viewport().size_changed.connect(_fit_camera)


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("controls", "sensitivity", controls.sensitivity)
	config.set_value("controls", "use_touch", controls.use_touch)
	config.set_value("visual", "tilt_feedback", tilt_feedback)
	config.set_value("audio", "enabled", sounds.enabled)
	config.set_value("locale", "language", language_code)
	config.save("user://settings.cfg")


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load("user://settings.cfg") == OK:
		controls.sensitivity = clampf(float(config.get_value("controls", "sensitivity", 1.0)), 0.5, 1.8)
		controls.use_touch = bool(config.get_value("controls", "use_touch", false))
		tilt_feedback = bool(config.get_value("visual", "tilt_feedback", true))
		sounds.set_enabled(bool(config.get_value("audio", "enabled", true)))
		language_code = str(config.get_value("locale", "language", "ru"))
	if language_code not in ["ru", "en"]: language_code = "ru"
	TranslationServer.set_locale(language_code)


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(_screenshot_path)
	print("Capture: ", _screenshot_path, " status=", error)
	get_tree().quit(error)
