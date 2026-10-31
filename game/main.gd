extends Node3D

const LEVEL: LevelDefinition = preload("res://resources/first_level.tres")
const WATER: LiquidProfile = preload("res://resources/water.tres")

var simulation: LiquidSimulation
var controls := TiltInput.new()
var surface: FluidSurface
var hud: HydrologicHUD
var running: bool = false
var _render_tick: int = 0
var _screenshot_frame: int = -1
var _screenshot_path: String = ""


func _ready() -> void:
	get_tree().auto_accept_quit = false
	_setup_environment()
	var board := HydrologicBoard.new()
	add_child(board)
	board.build(LEVEL)
	simulation = LiquidSimulation.new(LEVEL, WATER)
	surface = FluidSurface.new(WATER)
	add_child(surface)
	surface.rebuild(simulation.positions, LEVEL)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = HydrologicHUD.new()
	canvas.add_child(hud)
	hud.start_requested.connect(_start)
	hud.restart_requested.connect(_restart)
	hud.pause_requested.connect(_pause)
	hud.resume_requested.connect(_resume)
	hud.calibrate_requested.connect(_calibrate)
	hud.sensitivity_changed.connect(func(value: float):
		controls.sensitivity = value
		_save_settings())
	hud.mode_changed.connect(func(value: bool): controls.use_touch = value)
	hud.touch_changed.connect(func(value: Vector2): controls.touch = value)
	_load_settings()
	controls.sensor_vector()
	# Opt-in desktop capture only. Normal gameplay never auto-starts or auto-solves.
	var args := OS.get_cmdline_user_args()
	for i: int in range(args.size()):
		if args[i] == "--capture" and i + 1 < args.size():
			_screenshot_path = args[i + 1]
			_screenshot_frame = 20
			_start()
	if DisplayServer.get_name() == "headless":
		print("Hydrologic scene initialized: %d fluid particles, level 01" % simulation.positions.size())


func _physics_process(delta: float) -> void:
	var tilt := controls.sample(delta)
	if running:
		simulation.step(delta, tilt)
		_render_tick += 1
		if _render_tick % 2 == 0:
			surface.rebuild(simulation.positions, LEVEL)
		if simulation.completed:
			running = false
			hud.show_win(simulation.goal_fraction)
	hud.update_state(simulation.goal_fraction, tilt, controls.has_sensor, running)
	if _screenshot_frame > 0:
		_screenshot_frame -= 1
		if _screenshot_frame == 0:
			_capture.call_deferred()


func _start() -> void:
	controls.calibrate()
	hud.hide_modal()
	running = true


func _restart() -> void:
	simulation.reset()
	surface.rebuild(simulation.positions, LEVEL)
	hud.hide_modal()
	hud.pad.reset()
	controls.filtered = Vector2.ZERO
	running = true


func _pause() -> void:
	if running:
		running = false
		hud.show_pause()


func _resume() -> void:
	hud.hide_modal()
	# Never continue a held touch gesture across the pause boundary.
	hud.pad.reset()
	controls.filtered = Vector2.ZERO
	running = true


func _calibrate() -> void:
	controls.calibrate()
	hud.toast("Нулевое положение сохранено")


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if running:
				_pause()
			elif not simulation.completed:
				_resume()
		elif event.keycode == KEY_R:
			_restart()
		elif event.keycode == KEY_C:
			_calibrate()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if is_instance_valid(hud):
			_pause()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_pause()
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
	sun.directional_shadow_max_distance = 32
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	ground.position.y = -0.60
	ground.material_override = HydrologicBoard._material(Color("eaf0ef"), 1.0)
	add_child(ground)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 14.2
	camera.position = Vector3(0, 16, 10)
	camera.far = 100.0
	add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("controls", "sensitivity", controls.sensitivity)
	config.save("user://settings.cfg")


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load("user://settings.cfg") == OK:
		controls.sensitivity = clampf(float(config.get_value("controls", "sensitivity", 1.0)), 0.5, 1.8)
		hud.slider.value = controls.sensitivity


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(_screenshot_path)
	print("Capture: ", _screenshot_path, " status=", error)
	get_tree().quit(error)
