extends SceneTree

const LEVEL: LevelDefinition = preload("res://resources/first_level.tres")
const WATER: LiquidProfile = preload("res://resources/water.tres")
const CIRCUIT: Array[Vector2] = [Vector2.DOWN, Vector2(1, 0.5), Vector2(0.5, -1), Vector2(-1, -0.5), Vector2(-0.4, 1), Vector2.DOWN]
var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func center(points: PackedVector2Array) -> Vector2:
	var total := Vector2.ZERO
	for point: Vector2 in points: total += point
	return total / points.size()


func intact(fluid: LiquidSimulation) -> bool:
	if fluid.positions.size() != LEVEL.particle_count: return false
	for point: Vector2 in fluid.positions:
		if not point.is_finite() or not LEVEL.contains(point): return false
	return true


func advance(fluid: LiquidSimulation, frames: int, tilt: Vector2) -> bool:
	for frame: int in range(frames):
		fluid.step(1.0 / 60.0, tilt)
		if not intact(fluid): return false
	return true


func _run() -> void:
	var begin := Time.get_ticks_msec()
	var fluid := LiquidSimulation.new(LEVEL, WATER)
	check(intact(fluid) and fluid.goal_fraction == 0.0, "Water spawns inside the channel with no false victory")
	check(advance(fluid, 120, Vector2.ZERO), "Resting water conserves mass and stays inside the channel")
	var before := center(fluid.positions)
	check(advance(fluid, 60, Vector2.DOWN), "Water responds to a one-second tilt without escaping")
	check(center(fluid.positions).y > before.y + 1.0, "Low-viscosity water transports promptly rather than acting as a rigid lump")
	check(advance(fluid, 120, Vector2.UP), "Water tolerates a sharp reversal")
	check(center(fluid.positions).y < before.y + 0.8, "The flow reverses when gravity reverses")
	fluid.reset()
	for direction: Vector2 in [Vector2.DOWN, Vector2.RIGHT, Vector2.DOWN]:
		advance(fluid, 360, direction)
	check(not fluid.completed and fluid.goal_fraction < 0.8, "Old down/right/down route cannot bypass the spiral")
	fluid.reset()
	var spread_checked := false
	for direction: Vector2 in CIRCUIT:
		check(advance(fluid, 600, direction.normalized()), "Mass and containment through circuit phase " + str(direction))
		if not spread_checked:
			var min_x := INF
			var max_x := -INF
			for point: Vector2 in fluid.positions:
				min_x = minf(min_x, point.x)
				max_x = maxf(max_x, point.x)
			check(max_x - min_x > 3.5, "Water spreads along the lower gutter instead of preserving the source shape")
			spread_checked = true
	print("Full-circuit delivered fraction: ", fluid.goal_fraction)
	check(fluid.completed and fluid.goal_fraction >= 0.8, "360-degree circuit is solvable with 80% held in the central vessel")
	var old := fluid.positions.duplicate()
	fluid.step(1.0 / 60.0, Vector2.UP)
	check(old == fluid.positions, "Victory freezes the completed simulation")
	fluid.reset()
	check(not fluid.completed and fluid.held_seconds == 0.0 and intact(fluid), "Restart restores volume and completion timer")
	check(advance(fluid, 120, Vector2(1000, -1000)), "Extreme input remains finite and bounded by walls")
	var input := TiltInput.new()
	Input.set_gravity(Vector3(0, 0, 9.81))
	input.calibrate()
	check(input.has_sensor and input.sample(1.0).length() < 0.001, "Flat device calibrates to zero")
	Input.set_gravity(Vector3(3, -3, 8.8))
	var tilt := input.sample(1.0)
	check(tilt.x > 0.0 and tilt.y > 0.0 and tilt.length() <= 1.0, "Device axes map to board right/down")
	input.calibrate()
	check(input.sample(1.0).length() < 0.001, "Calibration removes an existing inclination")
	Input.set_gravity(Vector3.ZERO)
	Input.set_accelerometer(Vector3.ZERO)
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	check(game.screen == game.Screen.MENU and not game.running, "Application opens in the main menu")
	check(game.hud.buttons.has_all(["play", "levels", "settings", "about"]), "Main menu exposes play, level navigation, settings and description")
	game._settings()
	game.hud.slider.value = 1.4
	game.hud.mode_picker.item_selected.emit(1)
	game.hud.feedback_toggle.button_pressed = false
	check(is_equal_approx(game.controls.sensitivity, 1.4) and game.controls.use_touch and not game.tilt_feedback, "Settings update controls and visual feedback")
	game.controls.sensitivity = 1.0
	game.controls.use_touch = true
	game.tilt_feedback = true
	game._save_settings()
	game.controls.sensitivity = 0.5
	game._load_settings()
	check(is_equal_approx(game.controls.sensitivity, 1.0) and game.controls.use_touch and game.tilt_feedback, "Settings survive a configuration reload")
	game._levels()
	check(game.hud.buttons.has("level_0"), "Level selection exposes the real available level")
	game.hud.buttons["level_0"].pressed.emit()
	check(game.screen == game.Screen.MENU, "Selecting the level returns to its Play action")
	game._about()
	check(not game.running and game.screen == game.Screen.ABOUT, "Description opens without running physics")
	game._menu()
	game._start()
	check(game.running and game.hud.page == null and game.hud.buttons.size() == 1, "Gameplay contains only the scene, invisible input and pause button")
	game.controls.touch = Vector2.RIGHT
	for frame: int in range(30): game._physics_process(1.0 / 60.0)
	check(game.pivot.rotation.z < -0.02 and absf(game.pivot.rotation.z) <= game.MAX_TILT, "Tilting right lowers the right side, smoothly bounded to four degrees")
	check(game.surface.get_parent() == game.pivot, "Water and geometry tilt together")
	game._pause()
	old = game.simulation.positions.duplicate()
	var frozen_rotation: Vector3 = game.pivot.rotation
	game._physics_process(1.0 / 60.0)
	check(not game.running and old == game.simulation.positions and game.pivot.rotation == frozen_rotation, "Pause freezes both water and visual board tilt")
	check(game.hud.buttons.has_all(["resume", "restart", "exit"]), "Pause offers Continue, Restart and Exit")
	game.hud.buttons["exit"].pressed.emit()
	check(game.screen == game.Screen.MENU and not game.running and not game.hud.field.active, "Exit leads to main menu and clears gesture control")
	old = game.simulation.positions.duplicate()
	game._back()
	check(not game.running and game.simulation.positions == old, "Back from menu never resumes a hidden game")
	game._start()
	game._pause()
	game._resume()
	check(game.running and game.controls.touch == Vector2.ZERO, "Resume clears stale touch input")
	game._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game.screen == game.Screen.PAUSED, "Backgrounding gameplay opens pause")
	game._restart()
	check(game.running and game.simulation.goal_fraction == 0.0, "Restart returns water to the source")
	game._pause()
	game._menu()
	game._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game.screen == game.Screen.MENU, "Backgrounding the main menu does not create a pause dialog")
	game.free()
	print("RESULT: %d checks, %d failures; %.2f seconds" % [checks, failures, (Time.get_ticks_msec() - begin) / 1000.0])
	quit(1 if failures else 0)
