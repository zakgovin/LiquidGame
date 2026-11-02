extends "res://tests/visual.gd"
const COURSES = preload("res://tests/advanced_courses.gd")
var rotation_mode := true
var screenshots := true

class PhysicsOnlySurface extends FluidSurface:
	func _init(profile: LiquidProfile = null) -> void: super(profile)
	func rebuild(_particles: PackedVector3Array, _level: LevelDefinition, _active: PackedByteArray = PackedByteArray(), _solver: RefCounted = null) -> void: pass


func _initialize() -> void: _advanced.call_deferred()


func drive(game: Node, direction: Vector2) -> void:
	if rotation_mode:
		steer(game, direction)
	else:
		var sensor: Vector2 = game.world_to_input(direction.limit_length()) * game.controls.FULL_ANGLE
		var gx := sin(sensor.x)
		var gy := -sin(sensor.y)
		Input.set_gravity(Vector3(gx, gy, sqrt(maxf(0, 1.0 - gx * gx - gy * gy))) * 9.81)


func snapshot(name: String) -> void:
	if screenshots: await capture(name)


func open_source(game: Node, direction: Vector2) -> void:
	Input.set_gravity(Vector3(0, 0, 9.81))
	if rotation_mode: drive(game, direction)
	var source: Vector3 = game.board.to_global(game.board.source_anchor(game.level.reservoir_id) - Vector3.UP * 0.10)
	var point: Vector2 = game.camera.unproject_position(source)
	await send_touch(point, true)
	await send_touch(point, false)
	if not rotation_mode: drive(game, direction)
	for frame: int in range(ceili(game.OPEN_SECONDS * 60.0) + 2): game._physics_process(1.0 / 60.0)
	check(game.running and not game.opening, "The actual source tap releases level %d in %s mode" % [game.level_index + 1, "rotation" if rotation_mode else "tilt"])


func _advanced() -> void:
	var args := OS.get_cmdline_user_args()
	rotation_mode = args.is_empty() or args[0] != "tilt"
	screenshots = DisplayServer.get_name() != "headless"
	var selected: Array[int] = [5, 6, 7, 8, 9]
	if args.size() > 1:
		selected.clear()
		for value: String in args[1].split(","): selected.append(int(value))
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game._settings()
	game._set_control_mode(rotation_mode)
	await process_frame
	game.controls.sensitivity = 1.0
	game.sounds.set_enabled(false)
	if not screenshots:
		game.surface.free()
		game.surface = PhysicsOnlySurface.new(game.WATER)
		game.pivot.add_child(game.surface)
	game._levels()
	var all_buttons := true
	for number: int in range(9): all_buttons = all_buttons and game.hud.buttons.has("level_%d" % number)
	check(all_buttons and game.LEVELS.size() == 9, "All nine playable levels are exposed in the selection menu")
	await snapshot("v0140-nine-levels")
	game._menu()
	for number: int in selected:
		game._select_level(number - 1)
		game._start()
		check(game.level.safe_goal == (number == 7), "Open or protected receiver matches the requested rule on level " + str(number))
		check(game.board._goal_flaps.size() == (2 if number == 7 else 0), "Receiver hardware matches its physical protection")
		if number == 9: check(game.simulation.ice_count == game.level.particle_count, "Thaw begins with actual frozen water")
		await snapshot("v0140-level-%d-ready" % number)
		var directions := COURSES.directions(number)
		var durations := COURSES.frames(number)
		await open_source(game, directions[0])
		var angle := directions[0].angle()
		var saw_vapor := false
		var saw_melt := false
		var saw_low := PackedByteArray()
		var climbed := PackedByteArray()
		saw_low.resize(game.level.particle_count)
		climbed.resize(game.level.particle_count)
		for stage: int in range(directions.size()):
			var duration := durations[stage] - (ceili(game.OPEN_SECONDS * 60.0) + 2 if stage == 0 else 0)
			for frame: int in range(duration):
				angle = rotate_toward(angle, directions[stage].angle(), COURSES.TURN_SPEED / 60.0)
				drive(game, Vector2.from_angle(angle) * minf(directions[stage].length(), 1.0))
				game._physics_process(1.0 / 60.0)
				if frame % 120 == 0: await process_frame
				if number == 5 and frame % 30 == 0:
					for i: int in range(game.simulation.positions.size()):
						var p: Vector3 = game.simulation.positions[i]
						if p.y < -0.90: saw_low[i] = 1
						if saw_low[i] and p.y > 1.25 and p.x > 1.1: climbed[i] = 1
				if number == 5 and stage == 2 and frame == 180: await snapshot("v0140-cascade-ascent")
				if number == 6 and game.simulation.impact_latched and stage == directions.size() - 2 and frame == 250: await snapshot("v0140-impulse-open")
				if number == 7 and not saw_vapor and game.simulation.vapor_count > 24:
					for i: int in range(game.simulation.positions.size()):
						if game.simulation.active[i] and game.simulation.phases[i] == 2 and game.simulation.positions[i].y > 0.8:
							saw_vapor = true
							await snapshot("v0140-vapor-plume")
							break
				if number == 9 and not saw_melt and game.simulation.water_count > 128 and game.simulation.ice_count > 128:
					saw_melt = true
					await snapshot("v0140-thaw-transition")
			var f: LiquidSimulation = game.simulation
			var finite := true
			for p: Vector3 in f.positions: finite = finite and p.is_finite()
			check(finite and f.lost_without_rim == 0 and f.water_count + f.ice_count + f.vapor_count + f.lost_count == game.level.particle_count, "Finite, accounted phases without terrain leaks: level %d stage %d" % [number, stage])
			print("INPUT STAGE ", "rotation" if rotation_mode else "tilt", " ", number, " ", stage, " delivered=", f.goal_fraction, " secured=", f.secured_count, " water=", f.water_count, " ice=", f.ice_count, " vapor=", f.vapor_count, " lost=", f.lost_count, " gate=", f.impact_latched)
			if number == 8 and stage == 1:
				check(f.ice_count >= game.level.particle_count * 0.8, "The cold chamber freezes enough water before crossing the grate")
				var mesh_data: Dictionary = f.native_solver().call("build_ice_surface")
				var vertices: PackedVector3Array = mesh_data.vertices
				var coherent := not vertices.is_empty()
				for i: int in range(0, vertices.size(), 3):
					coherent = coherent and vertices[i].x >= -2.405 and vertices[i + 1].x >= -2.405 and vertices[i + 2].x >= -2.405 and vertices[i].distance_to(vertices[i + 1]) < 0.20
				check(coherent, "The resting ice surface has no phantom slab extending through its wall")
				await snapshot("v0140-freeze-solid")
				var positions := f.positions.duplicate()
				var temperatures := f.temperatures.duplicate()
				game._pause()
				for tick: int in range(20): game._physics_process(1.0 / 60.0)
				check(f.positions == positions and f.temperatures == temperatures, "Pause freezes solid motion and thermal evolution together")
				game._resume()
		var f: LiquidSimulation = game.simulation
		check(game.screen == game.Screen.WON and f.goal_fraction >= 0.8, "Actual %s controls complete level %d" % ["rotation" if rotation_mode else "sensor", number])
		if number == 5:
			var climbed_count := 0
			for value: int in climbed: climbed_count += value
			check(climbed_count > game.level.particle_count * 0.6, "Most of the original water really descends and climbs the large ramp")
		if number == 6: check(f.impact_latched and f.impact_angle > 1.3, "The strong water impact opens the actual spring mechanism")
		if number == 7: check(saw_vapor and f.escaped_vapor > 0, "The hot route shows rising vapor and accounts for escaped steam")
		if number == 9: check(saw_melt and f.water_count > game.level.particle_count * 0.8, "Thaw visibly passes through solid and liquid phases before delivery")
		if number == 7: check(f.secured_count == f.delivered_count, "Delivered mass remains secured in the protected receiver")
		else: check(f.secured_count == 0, "The open receiver does not secretly capture delivered mass")
		check(game.hud.buttons.has("next") == (number < 9), "Only available next levels are offered")
		await snapshot("v0140-level-%d-victory" % number)
		game._menu()
	game._select_level(8)
	game._restart()
	check(game.simulation.ice_count == game.level.particle_count and game.board.gate_open_amount == 0, "Restart restores the frozen source behind its closed cover")
	game._save_settings()
	var restored := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(restored)
	restored.set_physics_process(false)
	await process_frame
	if screenshots: await RenderingServer.frame_post_draw
	check(restored.level_index == 8 and restored.level.reservoir_id == &"source_09" and restored.simulation.ice_count == restored.level.particle_count, "A fresh app restores the ninth level by stable identity")
	restored.free()
	game.free()
	Input.set_gravity(Vector3.ZERO)
	await process_frame
	await process_frame
	await create_timer(0.08).timeout
	print("ADVANCED ", "ROTATION" if rotation_mode else "SENSOR", " RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
