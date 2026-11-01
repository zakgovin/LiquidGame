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


func isolated_fraction(fluid: LiquidSimulation) -> float:
	var bins := {}
	for i: int in range(fluid.positions.size()):
		if fluid.active[i] == 0: continue
		var p := fluid.positions[i] / 0.07
		var cell := Vector3i(floori(p.x), floori(p.y), floori(p.z))
		bins[cell] = int(bins.get(cell, 0)) + 1
	var isolated := 0
	for cell: Vector3i in bins:
		var nearby := 0
		for offset: Vector3i in [Vector3i.ZERO, Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]: nearby += int(bins.get(cell + offset, 0))
		if nearby < 4: isolated += int(bins[cell])
	return float(isolated) / fluid.positions.size()


func advance(fluid: LiquidSimulation, frames: int, tilt: Vector2) -> bool:
	for frame: int in range(frames):
		fluid.step(1.0 / 60.0, tilt)
		if not intact(fluid): return false
	return true


func sensor_angle(degrees: float) -> void:
	var angle := deg_to_rad(degrees)
	Input.set_gravity(Vector3(sin(angle), 0, cos(angle)) * 9.81)


func release_water(game: Node) -> void:
	game._release()
	for frame: int in range(ceil(game.OPEN_SECONDS * 60) + 2): game._physics_process(1.0 / 60.0)


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
	check(high - low > WATER.particle_spacing * 0.9, "Source contains multiple vertical particle layers")
	check(LEVEL.elevation(0) - LEVEL.elevation(4) > 0.5 and LEVEL.board_top > LEVEL.elevation(0) + 0.3, "Level contains descending floors and finite-height walls")
	fluid.set_gate_opening(0.0)
	var resting := center(fluid.positions)
	check(advance(fluid, 300, Vector2.ZERO) and fluid.lost_count == 0, "Closed reservoir keeps all water for five seconds")
	check(center(fluid.positions).distance_to(resting) < WATER.particle_spacing, "Hydrostatic water stays in the tank without creeping or collapsing")
	check(fluid.maximum_divergence < 0.02 and fluid.pressure_iterations > 0, "Pressure projection enforces incompressibility at rest")
	check(is_equal_approx(fluid.liquid_volume, LEVEL.particle_count * pow(WATER.particle_spacing, 3)), "Markers account for their physical water volume")
	fluid.set_gate_opening(1.0)
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
	fluid.reset()
	advance(fluid, 20, Vector2(0.2, 0.4))
	var repeatable := fluid.positions.duplicate()
	fluid.reset()
	advance(fluid, 20, Vector2(0.2, 0.4))
	check(repeatable == fluid.positions, "Reset reproduces the same initial flow without stale pressure or velocity")
	check(fluid.maximum_divergence < 0.02 and fluid.liquid_cell_count > 100, "Moving water remains nearly divergence-free across many volume cells")
	var one := LEVEL.duplicate() as LevelDefinition
	one.particle_count = 1
	var drop := LiquidSimulation.new(one, WATER)
	drop.set_particle(0, Vector3(-1.9, LEVEL.elevation(0) + WATER.particle_radius, 2.95), Vector3(0, 0, 2))
	var flew := false
	var accelerated_at_join := false
	for frame: int in range(30):
		drop.step(1.0 / 60.0, Vector2.ZERO)
		var point := drop.positions[0]
		if point.z > 3.1 and point.y > 0.35 and drop.velocities[0].y < -0.05: flew = true
		if drop.velocities[0].z > 2.02: accelerated_at_join = true
	check(flew and absf(drop.positions[0].y - (LEVEL.elevation(1) + WATER.particle_radius)) < 0.003, "Water falls through real vertical space and lands on a lower floor")
	check(not accelerated_at_join, "Crossing connected floor sections adds no artificial forward impulse")
	drop.set_particle(0, Vector3(-1.9, LEVEL.elevation(1) + WATER.particle_radius, 3.3), Vector3(0, 0, -2))
	advance(drop, 30, Vector2.UP)
	check(drop.positions[0].z > 3.1 + WATER.particle_radius - 0.002 and drop.positions[0].y < 0.35, "A riser blocks water from teleporting onto a higher floor")
	drop.set_particle(0, Vector3(2.5, LEVEL.elevation(2) + WATER.particle_radius, 0), Vector3(3, 0, 1))
	advance(drop, 15, Vector2.ZERO)
	check(drop.positions[0].x <= 2.601 - WATER.particle_radius and drop.positions[0].z > 0.14, "Side-wall contact preserves tangential flow")
	drop.set_particle(0, Vector3(-1.3, 1.3, 0), Vector3(2, 0, 0))
	advance(drop, 10, Vector2.ZERO)
	check(drop.positions[0].x > -1.05 and drop.positions[0].y > 1.0, "Airborne water can cross above a finite wall")
	drop.set_particle(0, Vector3(0, 1.5, 1), Vector3.ZERO)
	drop.step(1.0 / 60.0, Vector2.ZERO)
	check(drop.goal_fraction == 0.0, "Flying above the vessel does not count as delivered water")
	drop.set_particle(0, Vector3(4.5, -1.8, 0), Vector3.ZERO)
	advance(drop, 30, Vector2.ZERO)
	check(drop.lost_count == 1 and drop.is_unwinnable(), "Water spilled off the board is counted and can make a level unwinnable")
	fluid.reset()
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
	var mesh_volume := 0.0
	for i: int in range(0, vertices.size(), 3): mesh_volume += vertices[i].dot(vertices[i + 1].cross(vertices[i + 2])) / 6.0
	check(absf(absf(mesh_volume) - fluid.liquid_volume) < fluid.liquid_volume * 0.22, "Reconstructed resting surface approximates the represented physical volume")
	var sheet_level := LEVEL.duplicate() as LevelDefinition
	sheet_level.particle_count = 17 * 65
	var sheet := LiquidSimulation.new(sheet_level, WATER)
	for iz: int in range(65):
		for ix: int in range(17): sheet.native_solver().call("set_particle_state", iz * 17 + ix, Vector3(-2.5 + ix * 0.075, LEVEL.elevation(0) + WATER.particle_radius, -2.4 + iz * 0.075), Vector3.ZERO)
	var sheet_data: Dictionary = sheet.native_solver().call("build_surface")
	var sheet_vertices: PackedVector3Array = sheet_data.vertices
	var sheet_normals: PackedVector3Array = sheet_data.normals
	var top_area := 0.0
	for i: int in range(0, sheet_vertices.size(), 3):
		if (sheet_normals[i] + sheet_normals[i + 1] + sheet_normals[i + 2]).y < 1.5: continue
		top_area += absf((sheet_vertices[i + 1] - sheet_vertices[i]).cross(sheet_vertices[i + 2] - sheet_vertices[i]).y) * 0.5
	print("Thin-sheet reconstructed top area: ", top_area, "; resting mesh volume: ", absf(mesh_volume))
	check(top_area > 1.2 * 4.8 * 0.90, "A shallow stretched water sheet keeps at least 90% surface coverage instead of turning into dots")
	fluid.reset()
	var spray_fraction := 0.0
	for phase: int in range(4):
		advance(fluid, 120, Vector2.DOWN * 0.65)
		spray_fraction = maxf(spray_fraction, isolated_fraction(fluid))
	print("Gentle-flow maximum isolated fraction: ", spray_fraction)
	check(spray_fraction < 0.01 and intact(fluid) and fluid.lost_count < LEVEL.particle_count * 0.01, "Gentle flow keeps over 99% of markers in connected neighborhoods and retains over 99% of its volume")
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
	check(not game.hud.buttons.has("calibrate"), "Calibration is automatic at release; settings has no redundant action")
	check(game.hud.settings_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_SHOW_NEVER, "Settings allows touch scrolling without drawing a scrollbar")
	game.hud.buttons["language_en"].pressed.emit()
	check(game.language_code == "en" and game.hud.buttons["back"].text == "Main menu", "Language switch immediately translates the interface to English")
	game._load_settings()
	check(game.language_code == "en" and TranslationServer.get_locale() == "en", "Language choice survives a settings reload")
	game.hud.buttons["language_ru"].pressed.emit()
	check(game.hud.buttons["back"].text == "В главное меню", "Russian remains fully selectable")
	check(game.hud.slider.find_parent("SensitivityGroup") != null and not game.hud.slider.find_parent("SensitivityGroup").is_ancestor_of(game.hud.buttons["mode_tilt"]), "Sensitivity and control mode belong to separate settings cards")
	check(game.hud.slider.custom_minimum_size.y >= 96 and game.hud.feedback_toggle.custom_minimum_size.y >= 96, "Settings controls meet the 48 dp minimum touch target")
	check(game.hud.buttons["back"].position.y == 32 and game.hud.buttons["back"].get_parent().offset_top == -168, "Main-menu navigation is anchored in the bottom bar")
	game.hud.sound_toggle.button_pressed = false
	check(not game.sounds.enabled, "Sound switch mutes feedback")
	game.hud.sound_toggle.button_pressed = true
	check(game.sounds.enabled, "Sound switch restores feedback")
	game.hud.slider.value = 1.4
	game.hud.buttons["mode_touch"].button_pressed = true
	game.hud.buttons["mode_touch"].pressed.emit()
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
	check("Zakhar Govin" in credits and "Codex (OpenAI)" in credits, "Description credits both game authors")
	game._menu()
	game._start()
	var waiting: PackedVector3Array = game.simulation.positions.duplicate()
	game.controls.touch = Vector2(1, 1)
	for frame: int in range(120): game._physics_process(1.0 / 60.0)
	check(game.screen == game.Screen.READY and not game.running and waiting == game.simulation.positions, "Closed reservoir holds all water regardless of phone input before release")
	check(game.board.reservoir.visible and not game.hud.field.active, "Reservoir is visibly closed and gameplay gestures wait for release")
	game._pause()
	game._resume()
	check(game.screen == game.Screen.READY and not game.running, "Pausing preparation returns to the closed reservoir")
	sensor_angle(18.0)
	game._release()
	check(game.controls.neutral.distance_to(game.controls.sensor_vector()) < 0.00001, "Opening calibrates the phone position at the actual moment of release")
	Input.set_gravity(Vector3.ZERO)
	game._physics_process(0.1)
	var gate_position: Vector3 = game.board.reservoir.get_child(0).position
	var opening_water: PackedVector3Array = game.simulation.positions.duplicate()
	game._pause()
	game._physics_process(0.5)
	check(game.board.reservoir.get_child(0).position == gate_position and game.simulation.positions == opening_water, "Pause freezes both moving gate and water")
	game._resume()
	for frame: int in range(10): game._physics_process(1.0 / 60.0)
	check(game.board.reservoir.get_child(0).position.distance_to(gate_position) > 0.3 and game.board.reservoir.get_child(0).rotation.length() > 0.1, "Outlet cover translates and tumbles away after release")
	for frame: int in range(ceil(game.OPEN_SECONDS * 60) + 2): game._physics_process(1.0 / 60.0)
	check(game.board.gate_open_amount >= 0.999 and game.running and not game.opening, "Released lid leaves the field while its collar remains")
	check(game.running and game.hud.page == null and game.hud.buttons.size() == 1, "Gameplay contains only the scene, invisible input and pause button")
	check(game.pivot.visible, "Play restores the visible 3D level")
	game.controls.touch = Vector2.RIGHT
	for frame: int in range(30): game._physics_process(1.0 / 60.0)
	check(game.pivot.rotation.z < -0.02 and game.pivot.rotation.length() <= game.MAX_TILT + 0.001, "Screen-right inclination lowers the correct side with bounded visual feedback")
	check(game.world_to_input(game.input_to_world(Vector2(0.7, -0.3))).distance_to(Vector2(0.7, -0.3)) < 0.0001, "Camera projection maps screen input and world gravity consistently")
	var corners_fit := true
	for point: Vector2 in [LEVEL.board_bounds.position, Vector2(LEVEL.board_bounds.end.x, LEVEL.board_bounds.position.y), LEVEL.board_bounds.end, Vector2(LEVEL.board_bounds.position.x, LEVEL.board_bounds.end.y)]:
		var projected: Vector2 = game.camera.unproject_position(Vector3(point.x, LEVEL.board_top, point.y))
		corners_fit = corners_fit and root.get_visible_rect().has_point(projected)
	check(corners_fit, "Camera keeps every board corner inside the phone viewport")
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
	release_water(game)
	game._pause()
	game._resume()
	check(game.running and game.controls.touch == Vector2.ZERO, "Resume clears stale touch input")
	game._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game.screen == game.Screen.PAUSED, "Backgrounding gameplay opens pause")
	game._restart()
	check(game.screen == game.Screen.READY and not game.running, "Restart closes the reservoir and waits for the player")
	release_water(game)
	check(game.running and game.simulation.goal_fraction == 0.0, "Restart returns water to the source")
	game._pause()
	game._menu()
	game._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game.screen == game.Screen.MENU, "Backgrounding the main menu does not create a pause dialog")
	game._start()
	release_water(game)
	game._begin_finish()
	check(game.screen == game.Screen.FINISHING and game.hud.page == null and not game.hud.field.active, "Delivery leaves the vessel visible before showing completion")
	for frame: int in range(15): game._physics_process(1.0 / 60.0)
	check(game.screen == game.Screen.FINISHING, "Completion modal stays hidden for the first quarter second")
	game._pause()
	var finish_wait: float = game.finish_remaining
	game._physics_process(1.0)
	check(is_equal_approx(game.finish_remaining, finish_wait), "Pausing freezes the completion delay")
	game._resume()
	check(game.screen == game.Screen.FINISHING and not game.running, "Continue restores the pending result without restarting physics")
	for frame: int in range(14): game._physics_process(1.0 / 60.0)
	check(game.screen == game.Screen.FINISHING, "Result remains visible until the full half second has elapsed")
	for frame: int in range(2): game._physics_process(1.0 / 60.0)
	check(game.screen == game.Screen.WON and game.hud.buttons.has("win_menu"), "Completion modal opens after half a second of foreground time")
	game._restart()
	check(game.finish_remaining == 0 and game.board.gate_open_amount == 0, "Restart clears a pending result and returns the cover")
	release_water(game)
	for i: int in range(floori(LEVEL.particle_count * (1.0 - LEVEL.required_fraction)) + 1): game.simulation.set_particle(i, Vector3(4.5, -2, 0), Vector3.ZERO)
	game._physics_process(1.0 / 60.0)
	check(game.screen == game.Screen.FAILED and not game.running and game.hud.buttons.has_all(["retry", "fail_menu"]), "Losing too much water opens a recoverable failure dialog")
	game.hud.buttons["retry"].pressed.emit()
	check(game.screen == game.Screen.READY and not game.running and game.simulation.lost_count == 0, "Retry restores water inside the closed reservoir")
	var heard: Array[StringName] = []
	game.sounds.played.connect(func(event: StringName): heard.append(event))
	check(game.sounds.players[&"click"].volume_db <= -9.0, "Button clicks are quieter than level cues")
	game.sounds.play_event(&"click")
	game._release()
	check(heard.has(&"click") and heard.has(&"start"), "Button and release actions trigger distinct sound feedback")
	game.sounds.set_enabled(false)
	var event_count := heard.size()
	game.sounds.play_event(&"complete")
	check(heard.size() == event_count, "Muted feedback stays silent")
	game.sounds.set_enabled(true)
	game._save_settings()
	# Flush audio requests produced by synchronous lifecycle checks before
	# stopping the mixer voices and destroying their players.
	await process_frame
	await create_timer(0.12).timeout
	game.sounds.set_enabled(false)
	await process_frame
	await create_timer(0.12).timeout
	game.free()
	await process_frame
	await process_frame
	await create_timer(0.08).timeout # Let the audio mixer release stopped voices.
	print("RESULT: %d checks, %d failures; %.2f seconds" % [checks, failures, (Time.get_ticks_msec() - begin) / 1000.0])
	quit(1 if failures else 0)
