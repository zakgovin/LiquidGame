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


func center(points: PackedVector3Array) -> Vector3:
	var total := Vector3.ZERO
	for point: Vector3 in points: total += point
	return total / points.size()


func intact(fluid: LiquidSimulation) -> bool:
	if fluid.positions.size() != fluid.level.particle_count: return false
	var remaining := 0
	for i: int in range(fluid.positions.size()):
		if not fluid.positions[i].is_finite() or not fluid.velocities[i].is_finite(): return false
		if fluid.active[i] != 0: remaining += 1
	return remaining + fluid.lost_count == fluid.positions.size()


func advance(fluid: LiquidSimulation, frames: int, tilt: Vector2) -> bool:
	for frame: int in range(frames):
		fluid.step(1.0 / 60.0, tilt)
		if not intact(fluid): return false
	return true


func sensor_angle(degrees: float) -> void:
	var angle := deg_to_rad(degrees)
	Input.set_gravity(Vector3(sin(angle), 0, cos(angle)) * 9.81)


func _run() -> void:
	var begin := Time.get_ticks_msec()
	var fluid := LiquidSimulation.new(LEVEL, WATER)
	check(fluid.native_solver() != null, "Production uses the native 3D solver")
	check(intact(fluid) and fluid.goal_fraction == 0.0, "Water spawns with all parcels accounted for and no false victory")
	var low := INF
	var high := -INF
	for point: Vector3 in fluid.positions:
		low = minf(low, point.y)
		high = maxf(high, point.y)
	check(high - low > 0.09, "Source contains multiple vertical particle layers")
	check(LEVEL.elevation(0) - LEVEL.elevation(4) > 0.5 and LEVEL.board_top > LEVEL.elevation(0) + 0.3, "Level contains descending floors and finite-height walls")
	check(advance(fluid, 300, Vector2.ZERO) and fluid.lost_count == 0, "Resting water keeps its complete volume for five seconds")
	var before := center(fluid.positions)
	check(advance(fluid, 60, Vector2.DOWN), "One-second tilt stays finite and conserves accounted mass")
	check(center(fluid.positions).z > before.z + 0.8, "Low-viscosity flow moves promptly through the channel")
	before = center(fluid.positions)
	check(advance(fluid, 120, Vector2.UP), "Water tolerates a sharp reversal")
	check(center(fluid.positions).z < before.z - 0.3, "The flow reverses with gravity")
	fluid.reset()
	for direction: Vector2 in [Vector2.DOWN, Vector2.RIGHT, Vector2.DOWN]:
		advance(fluid, 360, direction)
	check(not fluid.completed and fluid.goal_fraction < 0.8, "Short down/right/down route cannot bypass the full spiral")
	fluid.reset()
	for direction: Vector2 in CIRCUIT:
		check(advance(fluid, 600, direction.normalized()), "Finite 3D state and conserved accounted mass through circuit phase " + str(direction))
	print("Full-circuit delivered fraction: ", fluid.goal_fraction, "; lost parcels: ", fluid.lost_count)
	check(fluid.completed and fluid.goal_fraction >= 0.8, "Full 360-degree circuit holds at least 80% in the central vessel")
	var old := fluid.positions.duplicate()
	fluid.step(1.0 / 60.0, Vector2.UP)
	check(old == fluid.positions, "Victory freezes the completed simulation")
	fluid.reset()
	check(not fluid.completed and fluid.held_seconds == 0.0 and fluid.lost_count == 0, "Restart restores all water and clears completion")
	check(advance(fluid, 120, Vector2(1000, -1000)), "Extreme input is clamped and leaves a finite simulation")
	var reference := LiquidSimulation.new(LEVEL, WATER, false)
	fluid.reset()
	advance(reference, 20, Vector2(0.2, 0.4))
	advance(fluid, 20, Vector2(0.2, 0.4))
	var difference := 0.0
	for i: int in range(fluid.positions.size()): difference = maxf(difference, fluid.positions[i].distance_to(reference.positions[i]))
	check(difference < 0.002, "Native solver matches the independent GDScript reference over the initial flow")
	var one := LEVEL.duplicate() as LevelDefinition
	one.particle_count = 1
	var drop := LiquidSimulation.new(one, WATER)
	drop.set_particle(0, Vector3(-1.9, 0.472, 2.95), Vector3(0, 0, 2))
	var flew := false
	var accelerated_at_join := false
	for frame: int in range(30):
		drop.step(1.0 / 60.0, Vector2.ZERO)
		var point := drop.positions[0]
		if point.z > 3.1 and point.y > 0.35 and drop.velocities[0].y < -0.05: flew = true
		if drop.velocities[0].z > 2.02: accelerated_at_join = true
	check(flew and absf(drop.positions[0].y - 0.332) < 0.003, "Water falls through real vertical space and lands on a lower floor")
	check(not accelerated_at_join, "Crossing connected floor sections adds no artificial forward impulse")
	drop.set_particle(0, Vector3(-1.9, 0.332, 3.3), Vector3(0, 0, -2))
	advance(drop, 30, Vector2.UP)
	check(drop.positions[0].z > 3.14 and drop.positions[0].y < 0.35, "A riser blocks water from teleporting onto a higher floor")
	drop.set_particle(0, Vector3(2.5, 0.192, 0), Vector3(3, 0, 1))
	advance(drop, 15, Vector2.ZERO)
	check(drop.positions[0].x <= 2.55 and drop.positions[0].z > 0.15, "Side-wall contact preserves tangential flow")
	drop.set_particle(0, Vector3(-1.3, 1.3, 0), Vector3(2, 0, 0))
	advance(drop, 10, Vector2.ZERO)
	check(drop.positions[0].x > -1.05 and drop.positions[0].y > 1.0, "Airborne water can cross above a finite wall")
	drop.set_particle(0, Vector3(0, 1.5, 1), Vector3.ZERO)
	drop.step(1.0 / 60.0, Vector2.ZERO)
	check(drop.goal_fraction == 0.0, "Flying above the vessel does not count as delivered water")
	drop.set_particle(0, Vector3(4.5, -1.8, 0), Vector3.ZERO)
	advance(drop, 30, Vector2.ZERO)
	check(drop.lost_count == 1 and drop.is_unwinnable(), "Water spilled off the board is counted and can make a level unwinnable")
	var mesh_data: Dictionary = fluid.native_solver().call("build_surface")
	var vertices: PackedVector3Array = mesh_data.vertices
	var normals: PackedVector3Array = mesh_data.normals
	low = INF
	high = -INF
	var finite_mesh := vertices.size() > 0 and normals.size() == vertices.size()
	for i: int in range(vertices.size()):
		finite_mesh = finite_mesh and vertices[i].is_finite() and normals[i].is_finite() and normals[i].length_squared() > 0.9
		low = minf(low, vertices[i].y)
		high = maxf(high, vertices[i].y)
	check(finite_mesh and high - low > 0.08, "Rendered implicit surface has finite normals and actual vertical volume")
	var input := TiltInput.new()
	Input.set_gravity(Vector3(0, 0, 9.81))
	input.calibrate()
	check(input.has_sensor and input.sample(1.0).length() < 0.001, "Flat device calibrates to zero")
	sensor_angle(5.0)
	check(input.sample(1.0).length() < 0.001, "Five-degree hand movement stays in the neutral zone")
	sensor_angle(15.0)
	var medium := input.sample(1.0).length()
	check(medium > 0.28 and medium < 0.32, "Fifteen degrees produces a deliberate partial tilt")
	sensor_angle(36.0)
	check(input.sample(1.0).x > 0.99, "Full tilt requires approximately thirty-six degrees")
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
	check(not game.pivot.visible and is_equal_approx((game.hud.page.get_child(0) as ColorRect).color.a, 1.0), "Main menu hides all level geometry behind an opaque background")
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
	var credits := ""
	for label: Node in game.hud.page.find_children("*", "Label", true, false): credits += label.text
	check("Zak Govin" in credits and "Codex (OpenAI)" in credits, "Description credits both game authors")
	game._menu()
	game._start()
	check(game.running and game.hud.page == null and game.hud.buttons.size() == 1, "Gameplay contains only the scene, invisible input and pause button")
	check(game.pivot.visible, "Play restores the visible 3D level")
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
	game._start()
	for i: int in range(52): game.simulation.set_particle(i, Vector3(4.5, -2, 0), Vector3.ZERO)
	game._physics_process(1.0 / 60.0)
	check(game.screen == game.Screen.FAILED and not game.running and game.hud.buttons.has_all(["retry", "fail_menu"]), "Losing too much water opens a recoverable failure dialog")
	game.hud.buttons["retry"].pressed.emit()
	check(game.running and game.simulation.lost_count == 0, "Retry restores the spilled water")
	game.free()
	print("RESULT: %d checks, %d failures; %.2f seconds" % [checks, failures, (Time.get_ticks_msec() - begin) / 1000.0])
	quit(1 if failures else 0)
