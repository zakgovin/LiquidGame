extends SceneTree
## Run: godot --headless --path . --script res://tests/run.gd
## Explicit failures determine process status (not disabled debug assertions).

const LEVEL: LevelDefinition = preload("res://resources/first_level.tres")
const WATER: LiquidProfile = preload("res://resources/water.tres")
var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: " + message)


func center(points: PackedVector2Array) -> Vector2:
	var result := Vector2.ZERO
	for point: Vector2 in points:
		result += point
	return result / points.size()


func intact(fluid: LiquidSimulation) -> bool:
	if fluid.positions.size() != LEVEL.particle_count:
		return false
	for point: Vector2 in fluid.positions:
		if not point.is_finite() or not LEVEL.contains(point):
			return false
	return true


func advance(fluid: LiquidSimulation, frames: int, tilt: Vector2) -> bool:
	for frame: int in range(frames):
		fluid.step(1.0 / 60.0, tilt)
		if not intact(fluid):
			return false
	return true


func _run() -> void:
	var begin := Time.get_ticks_msec()
	var fluid := LiquidSimulation.new(LEVEL, WATER)
	check(fluid.positions.size() == 288 and intact(fluid), "Level spawns 288 water particles inside the basin")
	check(fluid.goal_fraction == 0.0 and not fluid.completed, "No false victory at spawn")
	check(advance(fluid, 120, Vector2.ZERO), "Mass conserved and no wall escapes at rest (120 ticks)")
	var before := center(fluid.positions)
	check(advance(fluid, 300, Vector2.DOWN), "Water flows down first channel with containment at every tick")
	check(center(fluid.positions).y > before.y + 2.0, "Tilt causes actual transport, not a cosmetic animation")
	check(advance(fluid, 360, Vector2.RIGHT), "Water turns through the connecting channel")
	check(advance(fluid, 360, Vector2.DOWN), "Water reaches target basin with all particles conserved")
	print("Delivered fraction: ", fluid.goal_fraction)
	check(fluid.completed and fluid.goal_fraction >= LEVEL.required_fraction, "First level is solvable: 80% held for 0.75 seconds")
	var won := fluid.positions.duplicate()
	fluid.step(1.0 / 60.0, Vector2.UP)
	check(fluid.positions == won, "Completed simulation stops cleanly")
	fluid.reset()
	check(fluid.goal_fraction == 0.0 and not fluid.completed and intact(fluid), "Restart restores particle mass and victory state")
	check(advance(fluid, 120, Vector2(1000, -1000)), "Extreme input is bounded; no NaN or wall tunneling")
	var old := fluid.positions.duplicate()
	fluid.step(0.0, Vector2.ONE)
	check(old == fluid.positions, "Zero delta does not advance physics")
	# Check Android axis mapping, calibration, filtering and touch fallback independently.
	var input := TiltInput.new()
	Input.set_gravity(Vector3(0, 0, 9.81))
	input.calibrate()
	check(input.has_sensor and input.sample(1.0).length() < 0.001, "Flat device calibrates to zero")
	Input.set_gravity(Vector3(3, -3, 8.8))
	var tilt := input.sample(1.0)
	check(tilt.x > 0.0 and tilt.y > 0.0 and tilt.length() <= 1.0, "Portrait sensor axes map to board right/down")
	input.calibrate()
	check(input.sample(1.0).length() < 0.001, "Recalibration removes an existing device inclination")
	Input.set_gravity(Vector3.ZERO)
	Input.set_accelerometer(Vector3.ZERO)
	input.touch = Vector2.RIGHT
	check(input.sample(1.0).x > 0.9 and not input.has_sensor, "Touch fallback works without hardware sensors")
	# Instantiate the real scene: catches missing resources and UI/runtime errors.
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	check(not game.running and game.hud._modal != null, "Real scene opens on the level introduction")
	game._start()
	check(game.running and game.hud._modal == null, "Start dismisses intro and starts simulation")
	game._pause()
	old = game.simulation.positions.duplicate()
	game._physics_process(1.0 / 60.0)
	check(not game.running and old == game.simulation.positions, "Pause freezes the actual game state")
	game._resume()
	check(game.running and game.controls.touch == Vector2.ZERO, "Resume clears stale touch input")
	game._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not game.running, "Losing application focus pauses the game")
	game._restart()
	check(game.running and game.simulation.goal_fraction == 0.0, "Restart works through the scene controller")
	game.hud.show_win(0.85)
	check(game.hud._modal != null, "Victory overlay renders with the delivered amount")
	game.free()
	print("RESULT: %d checks, %d failures; %.2f seconds" % [checks, failures, (Time.get_ticks_msec() - begin) / 1000.0])
	quit(1 if failures > 0 else 0)
