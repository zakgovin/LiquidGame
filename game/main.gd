extends Node3D

enum Screen { MENU, PLAYING, PAUSED, SETTINGS, LEVELS, ABOUT, WON }
const LEVEL: LevelDefinition = preload("res://resources/first_level.tres")
const WATER: LiquidProfile = preload("res://resources/water.tres")
const MAX_TILT: float = PI / 45.0 # Four degrees; purely visual, never a second gravity.

var simulation: LiquidSimulation
var controls := TiltInput.new()
var pivot: Node3D
var surface: FluidSurface
var hud: HydrologicHUD
var screen: Screen = Screen.MENU
var running: bool = false
var tilt_feedback: bool = true
var _render_tick: int = 0
var _screenshot_frame: int = -1
var _screenshot_path: String = ""


func _ready() -> void:
	get_tree().auto_accept_quit = false
	_setup_environment()
	pivot = Node3D.new()
	add_child(pivot)
	var board := HydrologicBoard.new()
	pivot.add_child(board)
	board.build(LEVEL)
	simulation = LiquidSimulation.new(LEVEL, WATER)
	surface = FluidSurface.new(WATER)
	pivot.add_child(surface)
	surface.rebuild(simulation.positions, LEVEL)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = HydrologicHUD.new()
	canvas.add_child(hud)
	hud.start_requested.connect(_start)
	hud.restart_requested.connect(_restart)
	hud.pause_requested.connect(_pause)
	hud.resume_requested.connect(_resume)
	hud.menu_requested.connect(_menu)
	hud.settings_requested.connect(_settings)
	hud.about_requested.connect(_about)
	hud.levels_requested.connect(_levels)
	hud.level_selected.connect(func(_index: int): _menu())
	hud.calibrate_requested.connect(_calibrate)
	hud.sensitivity_changed.connect(func(value: float):
		controls.sensitivity = value
		_save_settings())
	hud.mode_changed.connect(func(value: bool):
		controls.use_touch = value
		_save_settings())
	hud.feedback_changed.connect(func(value: bool):
		tilt_feedback = value
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
	if running:
		simulation.step(delta, tilt)
		_render_tick += 1
		if _render_tick % 2 == 0:
			surface.rebuild(simulation.positions, LEVEL)
		hud.field.active = controls.use_touch or not controls.has_sensor
		if simulation.completed:
			running = false
			screen = Screen.WON
			hud.show_win(simulation.goal_fraction)
	var target := Vector3.ZERO
	if tilt_feedback and screen == Screen.PLAYING:
		target = Vector3(tilt.y * MAX_TILT, 0.0, -tilt.x * MAX_TILT)
	if screen != Screen.PAUSED:
		pivot.rotation = pivot.rotation.lerp(target, 1.0 - exp(-7.5 * delta))
	if _screenshot_frame > 0:
		_screenshot_frame -= 1
		if _screenshot_frame == 0:
			_capture.call_deferred()


func _start() -> void:
	controls.calibrate()
	_restart()


func _restart() -> void:
	simulation.reset()
	surface.rebuild(simulation.positions, LEVEL)
	controls.filtered = Vector2.ZERO
	controls.touch = Vector2.ZERO
	pivot.rotation = Vector3.ZERO
	running = true
	screen = Screen.PLAYING
	hud.show_game(controls.use_touch or not controls.has_sensor)


func _pause() -> void:
	if screen == Screen.PLAYING:
		running = false
		screen = Screen.PAUSED
		hud.show_pause()


func _resume() -> void:
	if screen != Screen.PAUSED:
		return
	controls.filtered = Vector2.ZERO
	controls.touch = Vector2.ZERO
	running = true
	screen = Screen.PLAYING
	hud.show_game(controls.use_touch or not controls.has_sensor)


func _menu() -> void:
	running = false
	screen = Screen.MENU
	controls.touch = Vector2.ZERO
	controls.filtered = Vector2.ZERO
	hud.show_menu(LEVEL.title)


func _settings() -> void:
	running = false
	screen = Screen.SETTINGS
	controls.sensor_vector()
	hud.show_settings(controls.sensitivity, controls.use_touch, tilt_feedback, controls.has_sensor)


func _levels() -> void:
	running = false
	screen = Screen.LEVELS
	hud.show_levels(LEVEL.title)


func _about() -> void:
	running = false
	screen = Screen.ABOUT
	hud.show_about()


func _calibrate() -> void:
	controls.calibrate()
	hud.calibration_done()


func _back() -> void:
	match screen:
		Screen.PLAYING: _pause()
		Screen.PAUSED: _resume()
		Screen.SETTINGS, Screen.LEVELS, Screen.ABOUT, Screen.WON: _menu()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_back()
		elif event.keycode == KEY_R and screen == Screen.PLAYING:
			_restart()
		elif event.keycode == KEY_C and screen == Screen.SETTINGS:
			_calibrate()


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
	environment.ambient_light_energy = 0.18
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -32, 0)
	sun.light_color = Color("fff5e6")
	sun.light_energy = 0.35
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	ground.position.y = -1.15
	ground.material_override = HydrologicBoard._material(Color("eaf0ef"), 1.0)
	add_child(ground)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = 6.95
	camera.position = Vector3(0, 18, 7)
	camera.far = 100.0
	add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("controls", "sensitivity", controls.sensitivity)
	config.set_value("controls", "use_touch", controls.use_touch)
	config.set_value("visual", "tilt_feedback", tilt_feedback)
	config.save("user://settings.cfg")


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load("user://settings.cfg") == OK:
		controls.sensitivity = clampf(float(config.get_value("controls", "sensitivity", 1.0)), 0.5, 1.8)
		controls.use_touch = bool(config.get_value("controls", "use_touch", false))
		tilt_feedback = bool(config.get_value("visual", "tilt_feedback", true))


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(_screenshot_path)
	print("Capture: ", _screenshot_path, " status=", error)
	get_tree().quit(error)
