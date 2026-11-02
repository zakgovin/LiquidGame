extends SceneTree

const LEVEL: LevelDefinition = preload("res://resources/first_level.tres")
const SECOND: LevelDefinition = preload("res://resources/second_level.tres")
const CURVED_COURSE = preload("res://tests/curved_course.gd")
const NEW_LESSONS = preload("res://tests/new_levels.gd")
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
	return remaining + fluid.lost_count == fluid.positions.size() and fluid.delivered_count + fluid.remaining_count + fluid.lost_count == fluid.positions.size()


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


func channels_visible(game: Node) -> bool:
	var toward: Vector3 = game.turntable.basis.inverse() * game.camera.global_basis.z
	var samples := PackedVector2Array()
	for region: Rect2 in game.level.floor_regions:
		if game.level.board_bounds.grow(-0.01).encloses(region): samples.append(region.get_center())
	for curve: Curve2D in game.level.channel_curves:
		for i: int in range(1, ceili(curve.get_baked_length() / 0.4)):
			var sample := curve.sample_baked(i * 0.4)
			if not game.level.goal.has_point(sample): samples.append(sample)
	for sample: Vector2 in samples:
		var point := Vector3(sample.x, game.level.floor_height(sample) + 0.01, sample.y)
		for wall: PackedFloat32Array in game.level.wall_segments():
			var a := Vector2(wall[0], wall[1])
			var edge := Vector2(wall[2], wall[3]) - a
			var normal := Vector2(-edge.y, edge.x)
			var denominator := normal.dot(Vector2(toward.x, toward.z))
			if absf(denominator) < 0.000001: continue
			var distance := normal.dot(a - sample) / denominator
			if distance <= 0.0001: continue
			var hit := point + toward * distance
			var along := (Vector2(hit.x, hit.z) - a).dot(edge) / edge.length_squared()
			if along >= 0.0 and along <= 1.0 and hit.y > wall[4] and hit.y < wall[5]: return false
	return true


func check_curved_terrain() -> void:
	var fluid := LiquidSimulation.new(SECOND, WATER)
	var mismatches := 0
	for iz: int in range(70):
		for ix: int in range(45):
			var sample := Vector2(-2.91 + ix * 0.131, -4.85 + iz * 0.139)
			var rendered := SECOND.floor_height(sample)
			var physical := float(fluid.native_solver().call("sample_floor", sample))
			if is_finite(rendered) != is_finite(physical) or (is_finite(rendered) and absf(rendered - physical) > 0.0001): mismatches += 1
	check(mismatches == 0, "Native curved terrain matches the continuous floor and open bank at 3150 points")
	var oblique := 0
	for wall: PackedFloat32Array in SECOND.wall_segments():
		if absf(wall[0] - wall[2]) > 0.001 and absf(wall[1] - wall[3]) > 0.001: oblique += 1
	check(SECOND.channel_curves.size() == 4 and oblique > 200, "The second level has genuine curved walls instead of a rectangular approximation")
	var mismatched_area := 0.0
	for face: Dictionary in SECOND.floor_faces():
		var indices := Geometry2D.triangulate_polygon(face.polygon)
		for i: int in range(0, indices.size(), 3):
			var centre: Vector2 = (face.polygon[indices[i]] + face.polygon[indices[i + 1]] + face.polygon[indices[i + 2]]) / 3.0
			if absf(SECOND.floor_height(centre) - float(face.height)) >= 0.001:
				mismatched_area += absf((face.polygon[indices[i + 1]] - face.polygon[indices[i]]).cross(face.polygon[indices[i + 2]] - face.polygon[indices[i]])) * 0.5
	check(mismatched_area < 0.00001, "Visible curved floors match their physical height within polygon-clipping precision")
	check(SECOND.void_regions.is_empty() and SECOND.opening_polygons().is_empty(), "The second level has no holes through its floor")
	var continuous := true
	for i: int in range(41):
		var sample := Vector2(-0.3 + i * 0.01, 2.25)
		continuous = continuous and SECOND.floor_height(sample) < 0.141
	check(continuous, "The former floor gap is now a continuous stepped connection")
	var bank := Vector2(-2.8, 1.19)
	var physical_gap := false
	var closed_adjacent := false
	var old_opening_closed := false
	for wall: PackedFloat32Array in SECOND.wall_segments():
		if absf(wall[0] - SECOND.board_bounds.position.x) > 0.001 or absf(wall[2] - SECOND.board_bounds.position.x) > 0.001: continue
		var low_z := minf(wall[1], wall[3])
		var high_z := maxf(wall[1], wall[3])
		if bank.y > low_z and bank.y < high_z: physical_gap = wall[5] < 0.141
		if 0.6 > low_z and 0.6 < high_z: closed_adjacent = wall[5] > 1.25
		if 2.05 > low_z and 2.05 < high_z: old_opening_closed = wall[5] > 1.25
	check(physical_gap and closed_adjacent and old_opening_closed and is_equal_approx(SECOND.floor_height(bank), 0.14), "The opening is upstream; its old position, adjacent bank and floor are intact")
	fluid.set_gate_opening(0.0)
	check(advance(fluid, 180, Vector2.ZERO) and fluid.lost_count == 0, "The curved level retains all water in its closed source")
	fluid = null
	var one := SECOND.duplicate() as LevelDefinition
	one.particle_count = 1
	var drop := LiquidSimulation.new(one, WATER)
	drop.set_gate_opening(1.0)
	drop.set_particle(0, Vector3(-0.06, 0.16, 2.25), Vector3.ZERO)
	advance(drop, 90, Vector2.ZERO)
	check(drop.lost_count == 0 and drop.positions[0].y >= -0.141 and intact(drop), "Stationary water rests on the repaired floor instead of falling through it")
	drop.reset()
	drop.set_particle(0, Vector3(bank.x, 0.157, bank.y), Vector3.ZERO)
	advance(drop, 90, Vector2.ZERO)
	check(drop.lost_count == 0 and is_equal_approx(drop.positions[0].y, 0.157), "The floor at the wall opening supports water without any jumping")
	drop.reset()
	drop.set_particle(0, Vector3(bank.x, 0.157, bank.y), Vector3.ZERO)
	advance(drop, 90, Vector2.LEFT)
	check(drop.lost_count == 1 and drop.lost_in_void == 0 and drop.lost_without_rim == 0 and intact(drop), "Outward gravity spills water through the wall opening and accounts for that legitimate loss")
	drop.reset()
	drop.set_particle(0, Vector3(-2.4, 0.157, 0.6), Vector3.ZERO)
	advance(drop, 90, Vector2.LEFT)
	check(drop.lost_count == 0 and drop.positions[0].x > SECOND.board_bounds.position.x, "The neighboring intact bank blocks the same outward input")


func check_curved_tilt(game: Node) -> void:
	for index: int in range(game.LEVELS.size()):
		if game.LEVELS[index] == SECOND:
			game._select_level(index)
			break
	game.controls.use_rotation = false
	game.controls.sensitivity = 1.0
	game._restart()
	Input.set_gravity(Vector3(0, 0, 9.81))
	game._release()
	var angle := PI / 2.0
	for stage: int in range(CURVED_COURSE.DIRECTIONS.size()):
		for frame: int in range(CURVED_COURSE.FRAMES[stage]):
			angle = rotate_toward(angle, CURVED_COURSE.DIRECTIONS[stage].angle(), CURVED_COURSE.TURN_SPEED / 60.0)
			var sensor: Vector2 = game.world_to_input(Vector2.from_angle(angle)) * game.controls.FULL_ANGLE
			var gx := sin(sensor.x)
			var gy := -sin(sensor.y)
			Input.set_gravity(Vector3(gx, gy, sqrt(maxf(0, 1.0 - gx * gx - gy * gy))) * 9.81)
			game._physics_process(1.0 / 60.0)
	# A fuller stream can still be settling when the fixed input recording
	# ends. Honour the same foreground result delay as the application.
	for frame: int in range(ceili(game.MAX_FINISH_SECONDS*60)+2):
		if game.screen != game.Screen.FINISHING: break
		game._physics_process(1.0/60.0)
	print("Curved phone-tilt delivered fraction: ", game.simulation.goal_fraction, "; side losses: ", game.simulation.lost_count)
	check(game.level == SECOND and game.screen == game.Screen.WON and game.simulation.goal_fraction >= 0.8 and game.simulation.lost_without_rim == 0 and intact(game.simulation), "Sensor input, filtering and visual feedback can complete the curved level with conserved mass")
	Input.set_gravity(Vector3.ZERO)


func _run() -> void:
	var begin := Time.get_ticks_msec()
	check_curved_terrain()
	NEW_LESSONS.run(check)
	preload("res://tests/phase_physics.gd").run(check)
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
	var previous_pace := LEVEL.duplicate() as LevelDefinition
	previous_pace.flow_speed = 1.0
	var slower := LiquidSimulation.new(previous_pace, WATER)
	advance(slower, 60, Vector2.DOWN)
	check(center(fluid.positions).z > center(slower.positions).z + 0.12, "The faster flow advances farther in equal real time without increasing gravity")
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
	check(old == fluid.positions, "Normal steps freeze a completed simulation until its explicit settling phase")
	fluid.settle(1.0 / 60.0, Vector2.ZERO)
	check(fluid.positions != old and intact(fluid), "Explicit settling keeps the stream moving and every parcel accounted for after the threshold")
	check(fluid.lost_without_rim == 0, "Full-circuit losses have crossed a physical rim; no water leaks through the terrain")
	var second_fluid := LiquidSimulation.new(SECOND, WATER)
	for direction: Vector2 in [Vector2.DOWN, Vector2.RIGHT, Vector2.DOWN]: advance(second_fluid, 360, direction)
	print("Second-level short-route delivered fraction: ", second_fluid.goal_fraction)
	check(not second_fluid.completed and second_fluid.goal_fraction < SECOND.required_fraction, "The short down/right/down route cannot complete the second level")
	second_fluid.reset()
	var course_angle := PI / 2.0
	var course_frame := 0
	for stage: int in range(CURVED_COURSE.DIRECTIONS.size()):
		for frame: int in range(CURVED_COURSE.FRAMES[stage]):
			course_angle = rotate_toward(course_angle, CURVED_COURSE.DIRECTIONS[stage].angle(), CURVED_COURSE.TURN_SPEED / 60.0)
			second_fluid.set_gate_opening(minf(float(course_frame) / 12.0, 1.0))
			second_fluid.step(1.0 / 60.0, Vector2.from_angle(course_angle))
			course_frame += 1
		check(intact(second_fluid), "Curved course preserves accounted mass through phase " + str(stage))
	print("Curved-course delivered fraction: ", second_fluid.goal_fraction, "; side losses: ", second_fluid.lost_count)
	check(second_fluid.completed and second_fluid.goal_fraction >= 0.8 and second_fluid.lost_count < SECOND.particle_count * 0.20 and second_fluid.lost_without_rim == 0, "Recorded full-strength steering completes the curved course within its twenty-percent loss allowance, without terrain leaks")
	# A fixed timing from the former collapsing-volume solver no longer
	# guarantees that the stream is at the opening. Exercise the real bank
	# with a finite-volume packet on its supported sill instead.
	var bank_fixture := SECOND.duplicate() as LevelDefinition
	bank_fixture.particle_count = 128
	second_fluid = LiquidSimulation.new(bank_fixture,WATER)
	for i: int in range(128):
		second_fluid.native_solver().call("set_particle_state",i,Vector3(-2.82+(i%8)*0.045,0.157+(i/32)*0.038,1.135+((i/8)%4)*0.035),Vector3.ZERO)
	advance(second_fluid,120,Vector2.LEFT)
	check(not second_fluid.completed and second_fluid.is_unwinnable() and second_fluid.lost_count>26 and second_fluid.lost_in_void==0 and second_fluid.lost_without_rim==0 and intact(second_fluid), "Outward gravity spills an actual water packet through the bank opening and makes that attempt unwinnable")
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
	var corners_sealed := true
	for corner: Vector2 in [Vector2(2.575, 4.475), Vector2(-2.575, 4.475), Vector2(-2.575, -4.475), Vector2(2.575, -4.475)]:
		drop.reset()
		var direction := Vector2(signf(corner.x), signf(corner.y)).normalized()
		drop.set_particle(0, Vector3(corner.x, LEVEL.floor_height(corner) + WATER.particle_radius, corner.y), Vector3(direction.x, 0, direction.y) * WATER.max_speed)
		for frame: int in range(20):
			drop.step(1.0 / 60.0, direction)
			var point := drop.positions[0]
			corners_sealed = corners_sealed and drop.lost_count == 0 and point.y >= LEVEL.floor_height(Vector2(point.x, point.z)) - 0.001
	check(corners_sealed, "Fast diagonal contacts at all four outer corners cannot push water through tile seams")
	drop.set_particle(0, Vector3(-1.3, 1.3, 0), Vector3(2, 0, 0))
	advance(drop, 10, Vector2.ZERO)
	check(drop.positions[0].x > -1.05 and drop.positions[0].y > 1.0, "Airborne water can cross above a finite wall")
	drop.set_particle(0, Vector3(0, 1.5, 1), Vector3.ZERO)
	drop.step(1.0 / 60.0, Vector2.ZERO)
	check(drop.goal_fraction == 0.0, "Flying above the vessel does not count as delivered water")
	drop.set_particle(0, Vector3(0.682, 0.45, 2.075), Vector3.ZERO)
	drop.step(1.0 / 60.0, Vector2.ZERO)
	check(drop.delivered_count == 1 and drop.goal_fraction == 1.0 and LEVEL.is_in_goal(drop.positions[0]), "Water above the former 34 cm cutoff and against the receiver wall is fully delivered")
	check(drop.delivered_count + drop.remaining_count + drop.lost_count == 1, "Delivered, on-board and lost counts partition the original volume")
	drop.set_particle(0, Vector3(4.5, -1.8, 0), Vector3.ZERO)
	advance(drop, 30, Vector2.ZERO)
	check(drop.lost_count == 1 and drop.is_unwinnable(), "Water spilled off the board is counted and can make a level unwinnable")
	fluid.reset()
	var mesh_data: Dictionary = fluid.native_solver().call("build_surface")
	var vertices: PackedVector3Array = mesh_data.vertices
	var normals: PackedVector3Array = mesh_data.normals
	var depths: PackedColorArray = mesh_data.colors
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
	# Keep the detached-volume budget from the original 8192-marker test.
	# Reducing starting water changes its fraction, not the permitted droplet volume.
	var detached_volume_budget := 8192.0 * pow(WATER.particle_spacing, 3) * 0.01
	check(spray_fraction * fluid.liquid_volume < detached_volume_budget and intact(fluid) and fluid.lost_count < LEVEL.particle_count * 0.01, "Gentle flow stays within the established detached-water volume budget and retains over 99% of its volume")
	var depths_valid := depths.size() == vertices.size()
	var depth_max := 0.0
	for depth: Color in depths:
		depths_valid = depths_valid and is_finite(depth.r) and depth.r >= 0.0 and depth.r <= 1.0
		depth_max = maxf(depth_max, depth.r)
	check(depths_valid and depth_max > 0.10, "Water carries finite local depth without requiring a scene-depth texture")
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
	game._select_level(0)
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
	game.hud.buttons["mode_rotate"].button_pressed = true
	game.hud.buttons["mode_rotate"].pressed.emit()
	game.hud.feedback_toggle.button_pressed = false
	check(is_equal_approx(game.controls.sensitivity, 1.4) and game.controls.use_rotation and not game.tilt_feedback, "Settings update controls and visual feedback")
	game.controls.sensitivity = 1.0
	game.controls.use_rotation = true
	game.tilt_feedback = true
	game._save_settings()
	game.controls.sensitivity = 0.5
	game._load_settings()
	check(is_equal_approx(game.controls.sensitivity, 1.0) and game.controls.use_rotation and game.tilt_feedback, "Settings survive a configuration reload")
	var legacy := ConfigFile.new()
	legacy.set_value("controls", "use_touch", true)
	legacy.set_value("controls", "sensitivity", 1.0)
	legacy.set_value("locale", "language", "ru")
	legacy.save("user://settings.cfg")
	game.controls.use_rotation = false
	game._load_settings()
	check(game.controls.use_rotation, "An existing Touch preference migrates to Rotate mode")
	game._save_settings()
	legacy.load("user://settings.cfg")
	check(legacy.get_value("controls", "mode", "") == "rotation", "New settings persist the explicit rotation mode")
	check(game.LEVELS[0].reservoir_id == &"source_01" and game.LEVELS[1].reservoir_id == &"source_04" and game.LEVELS[2].reservoir_id == &"source_02" and game.LEVELS[3].reservoir_id == &"source_03", "Display order is First Loop, Fork, Turns, Bottleneck")
	for old_index: int in range(4):
		var old_settings := ConfigFile.new()
		old_settings.set_value("progress", "selected_level", old_index)
		old_settings.save("user://settings.cfg")
		game._load_settings()
		check(game.level.reservoir_id == [&"source_01", &"source_02", &"source_03", &"source_04"][old_index], "An old saved index retains the same level after reordering: " + str(old_index))
	game.controls.use_rotation = true
	game._save_settings()
	game._levels()
	check(game.hud.buttons.has_all(["level_0", "level_1", "level_2", "level_3", "level_4", "level_5", "level_6", "level_7", "level_8"]), "Level selection exposes all nine available levels")
	game.hud.buttons["level_2"].pressed.emit()
	check(game.screen == game.Screen.MENU and game.level_index == 2 and game.level == SECOND, "Selecting level three loads the winding channels and receiver")
	var restored: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(restored)
	restored.set_physics_process(false)
	check(restored.level_index == 2 and restored.level == SECOND and restored.board.source_targets.has(SECOND.reservoir_id), "A fresh application restores the selected winding level by its stable identity")
	restored.free()
	game.camera.make_current()
	game._start()
	check(game.board.bank_jambs == 2 and game.board.open_edges > 0, "Both ends of the outer-bank opening are marked without a false lower landing")
	var second_channels_clear := true
	for i: int in range(36):
		game._rotate_field(TAU / 36.0)
		second_channels_clear = second_channels_clear and channels_visible(game)
	check(second_channels_clear and not game.running, "The second level has visible channel centres throughout a full turn while its reservoir remains closed")
	game._menu()
	game._levels()
	game.hud.buttons["level_0"].pressed.emit()
	check(game.screen == game.Screen.MENU and game.level_index == 0 and game.level == LEVEL, "Returning to level one restores its own geometry and Play action")
	game._about()
	check(not game.running and game.screen == game.Screen.ABOUT, "Description opens without running physics")
	var credits := ""
	for label: Node in game.hud.page.find_children("*", "Label", true, false): credits += label.text
	check("Zakhar Govin" in credits and "Codex (OpenAI)" in credits, "Description credits both game authors")
	game._menu()
	game.controls.use_rotation = false
	game._start()
	var waiting: PackedVector3Array = game.simulation.positions.duplicate()
	game.controls.use_rotation = false
	Input.set_gravity(Vector3(3, -3, 8.8))
	for frame: int in range(120): game._physics_process(1.0 / 60.0)
	check(game.screen == game.Screen.READY and not game.running and waiting == game.simulation.positions, "Closed reservoir holds all water regardless of phone input before release")
	check(game.board.reservoir.visible and game.hud.field.active and not game.hud.field.rotation_enabled, "Closed reservoir accepts object taps while phone steering cannot release it")
	game._pause()
	game._resume()
	check(game.screen == game.Screen.READY and not game.running, "Pausing preparation returns to the closed reservoir")
	game._release(&"other_source")
	check(game.screen == game.Screen.READY and not game.opening, "Opening is addressed to an individual source; unrelated reservoir IDs do not release this one")
	var reservoir_point: Vector3 = game.board.to_global(game.board.source_anchor(LEVEL.reservoir_id))
	var reservoir_screen: Vector2 = game.camera.unproject_position(reservoir_point)
	check(game.board.pick_source(game.camera.project_ray_origin(reservoir_screen), game.camera.project_ray_normal(reservoir_screen)) == LEVEL.reservoir_id, "Camera ray picking selects the closed reservoir geometry")
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
	Input.set_gravity(Vector3(8, 0, 5))
	for frame: int in range(30): game._physics_process(1.0 / 60.0)
	check(game.pivot.rotation.z < -0.06 and game.pivot.rotation.length() <= game.MAX_TILT + 0.001, "Phone inclination visibly lowers the correct side within nine degrees")
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
	check(game.running and not game.hud.field.is_dragging(), "Resume clears a stale rotation gesture")
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
	game.controls.use_rotation = true
	game.controls.sensitivity = 1.0
	game._restart()
	var enclosed: PackedVector3Array = game.simulation.positions.duplicate()
	var down_consistent := true
	var rotation_fits := true
	var fixed_size: float = game.camera.size
	var fixed_basis: Basis = game.camera.basis
	var upright := true
	for turn: float in [PI / 2.0, -PI, PI / 4.0, PI]:
		game.hud.field.rotation_changed.emit(turn)
		var bottom: Vector2 = game.camera.unproject_position(game.pivot.to_global(Vector3.ZERO))
		var above: Vector2 = game.camera.unproject_position(game.pivot.to_global(Vector3.UP))
		upright = upright and absf(above.x - bottom.x) < 0.001 and above.y < bottom.y
		upright = upright and game.camera.basis.is_equal_approx(fixed_basis) and is_equal_approx(game.camera.size, fixed_size)
		var gravity_screen: Vector2 = game.world_to_input(game.input_to_world(Vector2.DOWN))
		down_consistent = down_consistent and gravity_screen.distance_to(Vector2.DOWN) < 0.0001
		for x: float in [LEVEL.board_bounds.position.x, LEVEL.board_bounds.end.x]:
			for z: float in [LEVEL.board_bounds.position.y, LEVEL.board_bounds.end.y]:
				for y: float in [LEVEL.base_height - 0.08, LEVEL.board_top + 0.12]:
					rotation_fits = rotation_fits and root.get_visible_rect().has_point(game.camera.unproject_position(game.pivot.to_global(Vector3(x, y, z))))
	check(down_consistent and absf(game.rotation_angle) > 0.1, "Rotating the board changes its orientation while screen gravity stays down")
	check(upright, "The board turns in 3D beneath a fixed raised camera; verticals remain upright and zoom is constant")
	check(rotation_fits, "The complete glass volume fits at both clockwise and counterclockwise orientations")
	var all_channels_clear := true
	for i: int in range(36):
		game._rotate_field(TAU / 36.0)
		all_channels_clear = all_channels_clear and channels_visible(game)
	check(all_channels_clear, "At every ten-degree rotation, walls leave a clear line of sight to each channel centre")
	check(enclosed == game.simulation.positions and game.hud.field.active, "Preparing the board allows rotation while all water remains enclosed")
	var retained_angle: float = game.rotation_angle
	game._pause()
	game.hud.field.rotation_changed.emit(PI / 2.0)
	check(is_equal_approx(game.rotation_angle, retained_angle), "Paused gameplay rejects rotation gestures")
	game._resume()
	check(is_equal_approx(game.rotation_angle, retained_angle), "Continue preserves the board orientation")
	var phone_independent: PackedVector3Array
	for trial: int in range(2):
		Input.set_gravity(Vector3(0, 0, 9.81) if trial == 0 else Vector3(6, -5, 5))
		game._restart()
		game._rotate_field(0.6)
		release_water(game)
		for frame: int in range(90): game._physics_process(1.0 / 60.0)
		if trial == 0: phone_independent = game.simulation.positions.duplicate()
		else: check(phone_independent == game.simulation.positions, "Rotate mode produces the same flow regardless of phone inclination")
	game._restart()
	check(game.rotation_angle == 0.0, "Restart restores the original board orientation")
	release_water(game)
	# Place a real, stationary parcel volume in the physical receiver. The
	# native delivery counter must measure it before the result-delay checks.
	for i: int in range(LEVEL.particle_count):
		var point := Vector3(-0.64 + (i % 34 + 0.5) * 1.28 / 34.0, LEVEL.elevation(4) + (i / (34 * 50) + 0.5) * WATER.particle_spacing, 0.12 + ((i / 34) % 50 + 0.5) * 1.84 / 50.0)
		game.simulation.native_solver().call("set_particle_state", i, point, Vector3.ZERO)
	game.simulation.settle(1.0 / 60.0, Vector2.ZERO)
	game._begin_finish()
	check(game.screen == game.Screen.FINISHING and game.hud.page == null and not game.hud.field.active, "Delivery leaves the vessel visible before showing completion")
	for frame: int in range(15): game._physics_process(1.0 / 60.0)
	check(game.screen == game.Screen.FINISHING, "Completion modal stays hidden for the first quarter second")
	game._pause()
	var finish_wait: float = game.finish_remaining
	game._physics_process(1.0)
	check(is_equal_approx(game.finish_remaining, finish_wait), "Pausing freezes the completion delay")
	game._resume()
	check(game.screen == game.Screen.FINISHING and not game.running, "Continue restores the pending result and its explicit settling phase")
	for frame: int in range(14): game._physics_process(1.0 / 60.0)
	check(game.screen == game.Screen.FINISHING, "Result remains visible until the full half second has elapsed")
	for frame: int in range(2): game._physics_process(1.0 / 60.0)
	check(game.screen == game.Screen.WON and game.hud.buttons.has("win_menu"), "Completion modal opens after the full quiet half second")
	check(game.hud.buttons.has("next"), "First-level victory offers the next level")
	game.hud.buttons["next"].pressed.emit()
	check(game.level_index == 1 and game.level.reservoir_id == &"source_04" and game.level.safe_goal and game.screen == game.Screen.READY and game.simulation.goal_fraction == 0.0, "Next level starts Fork second with its own sealed source and fresh water")
	game._next_level()
	check(game.level_index == 2 and game.level == SECOND and game.screen == game.Screen.READY, "Next level opens Turns third")
	game._next_level()
	check(game.level_index == 3 and game.level.safe_goal and game.screen == game.Screen.READY, "Next level opens Bottleneck fourth with a protected receiver")
	game._next_level()
	check(game.level_index == 4 and not game.level.safe_goal and game.screen == game.Screen.READY, "The fifth level follows Bottleneck with an open final vessel")
	for index: int in range(5, 9):
		game._next_level()
		check(game.level_index == index and game.level.safe_goal == (index == 6), "Next-level receiver protection is correct on level " + str(index + 1))
	game._next_level()
	check(game.level_index == 9 and game.level.safe_goal and game.level.sources.size() == 3, "The tenth level combines independent sources with a protected final vessel")
	game._next_level()
	check(game.level_index == 9, "The tenth level cannot advance beyond the available list")
	game._select_level(0)
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
	check_curved_tilt(game)
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
