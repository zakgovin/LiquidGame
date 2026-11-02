extends RefCounted
const LEVELS: Array[LevelDefinition] = [preload('res://resources/first_level.tres'), preload('res://resources/second_level.tres'), preload('res://resources/third_level.tres'), preload('res://resources/fourth_level.tres')]
const WATER = preload('res://resources/water.tres')
const COURSES = preload('res://tests/demo_courses.gd')

static func accounted(f: LiquidSimulation) -> bool:
	var living := 0
	for a: int in f.active: living += 1 if a != 0 else 0
	return living + f.lost_count == f.level.particle_count and f.delivered_count + f.remaining_count + f.lost_count == f.level.particle_count

static func advance(f: LiquidSimulation, frames: int, input: Vector2, settling: bool = false) -> void:
	for frame: int in range(frames):
		if settling: f.settle(1.0 / 60.0, input)
		else: f.step(1.0 / 60.0, input)

static func pair_distance(separation: float, enabled: bool) -> Vector2:
	var level := LEVELS[0].duplicate() as LevelDefinition
	level.particle_count = 2
	var profile := WATER.duplicate() as LiquidProfile
	profile.subgrid_capillarity = enabled
	var f := LiquidSimulation.new(level, profile)
	f.set_particle(0, Vector3(-separation * 0.5, 2.2, 0), Vector3(-0.025, 0, 0))
	f.set_particle(1, Vector3(separation * 0.5, 2.2, 0), Vector3(0.025, 0, 0))
	advance(f, 30, Vector2.ZERO)
	return Vector2(f.positions[0].distance_to(f.positions[1]), f.velocities[0].x + f.velocities[1].x)

static func run(check: Callable) -> void:
	for level: LevelDefinition in LEVELS:
		var f := LiquidSimulation.new(level, WATER)
		check.call(level.particle_count == 6144 and is_equal_approx(f.liquid_volume, 8192 * pow(WATER.particle_spacing, 3) * 0.75), 'Each level starts with exactly 25 percent less physical water: ' + level.title)
		f.set_gate_opening(0)
		advance(f, 180, Vector2.ZERO)
		check.call(f.lost_count == 0 and f.secured_count == 0 and accounted(f), 'The sealed source retains all reduced water: ' + level.title)
	check.call(is_equal_approx(WATER.viscosity, 0.000001) and is_equal_approx(WATER.surface_tension, 0.072), 'Water keeps its original viscosity and surface-tension coefficient')
	var plain := pair_distance(0.052, false)
	var cohesive := pair_distance(0.052, true)
	check.call(cohesive.x < plain.x * 0.65 and absf(cohesive.y) < 0.00001, 'Local capillary support keeps close droplets together and conserves horizontal momentum')
	var far_plain := pair_distance(0.2, false)
	var far_cohesive := pair_distance(0.2, true)
	check.call(absf(far_plain.x - far_cohesive.x) < 0.00001, 'Separated spray remains ballistic outside the finite cohesion radius')
	var neck := LEVELS[2]
	check.call(neck.safe_goal and neck.void_regions.size() == 2 and neck.spill_banks.size() == 2 and neck.obstacles.size() == 1, 'Bottleneck has a supported route, two low banks with spill wells and a protected receiver')
	check.call(neck.floor_height(Vector2(-2.8, -1.14)) == neck.board_top and neck.floor_height(Vector2(2.8, -1.14)) == neck.board_top, 'Former exterior side outlets are sealed')
	check.call(is_equal_approx(neck.floor_height(Vector2(0, 0.8)), 0.42) and neck.floor_height(Vector2(0.3, 0.8)) == neck.board_top, 'The narrow passage keeps its floor and retaining rails beside the wells')
	var single := neck.duplicate() as LevelDefinition
	single.particle_count = 1
	var drop := LiquidSimulation.new(single, WATER)
	drop.set_particle(0, Vector3(0, 0.46, -0.12), Vector3(0, 0, 1.8))
	advance(drop, 30, Vector2.ZERO)
	check.call(drop.positions[0].z > 0.31 and drop.lost_count == 0, 'Water passes through the low opening beneath the lintel')
	drop.reset()
	drop.set_particle(0, Vector3(0, 0.84, -0.08), Vector3(0, 0, 1.8))
	advance(drop, 8, Vector2.ZERO)
	check.call(drop.positions[0].z < 0 and drop.positions[0].y > 0.64, 'The same passage blocks a parcel above its actual opening')
	for side: float in [-1.0, 1.0]:
		drop.reset()
		drop.set_particle(0, Vector3(side * 0.9, 0.45, -0.08), Vector3(0, 0, 1.2))
		advance(drop, 8, Vector2.ZERO)
		check.call(drop.lost_count == 0 and drop.positions[0].z < 0, 'Each low bank retains a parcel below its lip: ' + str(side))
		drop.reset()
		drop.set_particle(0, Vector3(side * 0.9, 0.78, -0.05), Vector3(0, 0, 1.8))
		advance(drop, 90, Vector2.DOWN)
		check.call(drop.lost_count == 1 and drop.lost_without_rim == 0 and drop.lost_in_void == 1, 'Overtopping each bank really loses the parcel in the well behind it: ' + str(side))
	var wrong := LiquidSimulation.new(neck, WATER)
	for frame: int in range(480):
		wrong.set_gate_opening(minf(float(frame) / 12.6, 1.0))
		wrong.step(1.0 / 60.0, Vector2.DOWN)
	check.call(wrong.is_unwinnable() and wrong.lost_count > neck.particle_count * 0.2 and wrong.lost_in_void == wrong.lost_count and wrong.lost_without_rim == 0 and accounted(wrong), 'Full forward tilt overtops the low banks and fails instead of collecting water safely at the neck')
	wrong = null
	for level_index: int in [2, 3]:
		var level := LEVELS[level_index]
		var f := LiquidSimulation.new(level, WATER)
		var directions: Array[Vector2] = COURSES.BOTTLENECK_DIRECTIONS if level_index == 2 else COURSES.FORK_DIRECTIONS
		var frames: Array[int] = COURSES.BOTTLENECK_FRAMES if level_index == 2 else COURSES.FORK_FRAMES
		var left_seen := PackedByteArray()
		var right_seen := PackedByteArray()
		left_seen.resize(level.particle_count)
		right_seen.resize(level.particle_count)
		var angle := PI / 2.0
		var elapsed := 0
		for phase: int in range(directions.size()):
			for frame: int in range(frames[phase]):
				angle = rotate_toward(angle, directions[phase].angle(), COURSES.TURN_SPEED / 60.0)
				f.set_gate_opening(minf(float(elapsed) / (12.6 if level_index == 2 else 12.0), 1.0))
				f.step(1.0 / 60.0, Vector2.from_angle(angle) * (directions[phase].length() if level_index == 2 else 1.0))
				elapsed += 1
				if level_index == 3 and frame % 6 == 0:
					for i: int in range(f.positions.size()):
						var p := f.positions[i]
						if p.x < -1.2 and p.z > -1.7 and p.z < 0.8: left_seen[i] = 1
						if p.x > 1.2 and p.z > -1.7 and p.z < 1.4: right_seen[i] = 1
			if level_index == 3 and phase == 0:
				check.call(f.secured_count > level.particle_count * 0.25 and f.secured_count < level.particle_count * 0.70 and not f.completed, 'The short branch arrives first while the long branch still needs control')
			check.call(accounted(f) and f.lost_without_rim == 0, 'Accounted mass and sealed terrain throughout lesson %d phase %d' % [level_index + 1, phase])
		print('Lesson ', level_index + 1, ' delivered=', f.goal_fraction, ' secured=', f.secured_count, ' lost=', f.lost_count, ' elapsed=', elapsed / 60.0)
		check.call(f.completed and f.goal_fraction >= 0.8, 'The new lesson completes through physical flow: ' + level.title)
		if level_index == 2: check.call(f.lost_count < level.particle_count * 0.10 and f.lost_in_void == f.lost_count, 'Gentle forward tilt completes the neck while retaining over 90 percent of the initial water')
		if level_index == 3:
			var left := 0
			var right := 0
			for a: int in left_seen: left += a
			for a: int in right_seen: right += a
			check.call(left > level.particle_count * 0.25 and right > level.particle_count * 0.25, 'The fork sends substantial real water through both separate branches')
		var secured := f.secured_count
		advance(f, 180, Vector2.UP, true)
		check.call(f.secured_count >= secured and f.delivered_count >= secured and accounted(f), 'Reversing gravity cannot drain the volume already secured: ' + level.title)
		f.reset()
		check.call(f.secured_count == 0 and f.lost_count == 0 and f.goal_fraction == 0, 'Restart clears check-valve capture and restores the source: ' + level.title)
		var retained_level := level.duplicate() as LevelDefinition
		retained_level.particle_count = 256
		var retained := LiquidSimulation.new(retained_level, WATER)
		var g := level.goal
		for i: int in range(256):
			var x := g.get_center().x + ((i % 16) - 7.5) * 0.06
			var z := g.get_center().y + ((i / 16) - 7.5) * 0.06
			retained.native_solver().call('set_particle_state', i, Vector3(x, -0.12, z), Vector3.ZERO)
		retained.step(1.0 / 60.0, Vector2.ZERO)
		for direction: Vector2 in [Vector2.UP, Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN]: advance(retained, 60, direction, true)
		var contained := true
		for point: Vector3 in retained.positions: contained = contained and g.has_point(Vector2(point.x, point.z)) and point.y < level.board_top
		check.call(retained.secured_count == 256 and retained.delivered_count == 256 and retained.lost_count == 0 and contained, 'Every retained parcel stays visible and physically inside the receiver during a full reversal sequence')
		var surface: Dictionary = retained.native_solver().call('build_surface')
		var surface_contained: bool = not surface.vertices.is_empty()
		for point: Vector3 in surface.vertices: surface_contained = surface_contained and g.grow(0.005).has_point(Vector2(point.x, point.z)) and point.y <= level.board_top + 0.002
		check.call(surface_contained, 'The retained free surface stays inside the covered receiver')
	for level: LevelDefinition in [LEVELS[2], LEVELS[3]]:
		var board := HydrologicBoard.new()
		board.build(level)
		var supported := not board.step_patches.is_empty()
		for patch: Dictionary in board.step_patches:
			var points: PackedVector2Array = patch.polygon
			var triangles := Geometry2D.triangulate_polygon(points)
			for i: int in range(0, triangles.size(), 3):
				var centre := (points[triangles[i]] + points[triangles[i+1]] + points[triangles[i+2]]) / 3.0
				supported = supported and absf(level.floor_height(centre) - float(patch.height)) < 0.001
		check.call(supported, 'Every clipped marking triangle rests on its real landing: ' + level.title)
		board.free()
