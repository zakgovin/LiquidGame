class_name LiquidSimulation
extends RefCounted
## Volumetric position-based fluid: Vector3 parcels, density projection with
## weak surface tension, 3D gravity, finite walls and falling/splashing water.

var level: LevelDefinition
var material: LiquidProfile
var positions := PackedVector3Array()
var velocities := PackedVector3Array()
var active := PackedByteArray()
var lost_count: int = 0
var goal_fraction: float = 0.0
var held_seconds: float = 0.0
var completed: bool = false
var _previous := PackedVector3Array()
var _lambdas := PackedFloat32Array()
var _densities := PackedFloat32Array()
var _corrections := PackedVector3Array()
var _contacts := PackedVector3Array()
var _smoothed := PackedVector3Array()
var _inverse_density := PackedFloat32Array()
var _boundary_gradient := PackedVector3Array()
var _wall_table := PackedFloat32Array()
var _neighbors: Array[PackedInt32Array] = []
var _grid: Dictionary = {}
var _native: RefCounted


func _init(definition: LevelDefinition, profile: LiquidProfile, prefer_native: bool = true) -> void:
	level = definition
	material = profile
	if prefer_native and ClassDB.class_exists("NativeLiquidSolver"):
		_native = ClassDB.instantiate("NativeLiquidSolver") as RefCounted
	else:
		_build_wall_table()
	reset()


func reset() -> void:
	if _native != null:
		_native.call("configure", {
			"regions": level.floor_regions, "elevations": level.floor_elevations,
			"walls": level.wall_segments(), "tiles": level.terrain_tiles(), "bounds": level.board_bounds,
			"spawn": level.spawn, "goal": level.goal, "count": level.particle_count,
			"top": level.board_top, "base": level.base_height,
			"radius": material.particle_radius, "spacing": material.particle_spacing,
			"h": material.interaction_radius, "rho": material.rest_density,
			"drag": material.drag, "max_speed": material.max_speed,
			"viscosity": material.viscosity, "tension": material.surface_tension, "iterations": material.solver_iterations,
			"required": level.required_fraction, "hold": level.hold_seconds})
		_sync_native()
		return
	var count := level.particle_count
	positions.resize(count)
	velocities.resize(count)
	active.resize(count)
	active.fill(1)
	_previous.resize(count)
	_lambdas.resize(count)
	_densities.resize(count)
	_corrections.resize(count)
	_contacts.resize(count)
	_smoothed.resize(count)
	_inverse_density.resize(count)
	_boundary_gradient.resize(count)
	_neighbors.resize(count)
	var spacing := material.particle_spacing
	var columns := maxi(1, floori((level.spawn.size.x - 0.20) / spacing))
	var rows := maxi(1, floori((level.spawn.size.y - 0.20) / spacing))
	for i: int in range(count):
		var column := i % columns
		var row := (i / columns) % rows
		var layer := i / (columns * rows)
		var xz := level.spawn.position + Vector2(0.10 + column * spacing + (row % 2) * spacing * 0.25, 0.10 + row * spacing)
		positions[i] = Vector3(xz.x, level.floor_height(xz) + material.particle_radius + 0.02 + layer * spacing, xz.y)
		velocities[i] = Vector3.ZERO
	lost_count = 0
	goal_fraction = 0.0
	held_seconds = 0.0
	completed = false


func step(delta: float, tilt: Vector2) -> void:
	if _native != null:
		_native.call("step", delta, tilt)
		_sync_native()
		return
	if completed or delta <= 0.0: return
	var duration := minf(delta, 1.0 / 30.0)
	var steps := maxi(1, ceili(duration * 60.0))
	var dt := duration / steps
	var direction := tilt.limit_length(1.0) * 0.7
	var gravity := Vector3(direction.x, -1.0, direction.y).normalized() * 9.81
	for substep: int in range(steps): _substep(dt, gravity)
	var delivered := 0
	for i: int in range(positions.size()):
		if active[i] != 0 and level.is_in_goal(positions[i]): delivered += 1
	goal_fraction = float(delivered) / positions.size()
	held_seconds = held_seconds + duration if goal_fraction >= level.required_fraction else 0.0
	completed = held_seconds >= level.hold_seconds


func is_unwinnable() -> bool:
	return float(positions.size() - lost_count) / positions.size() < level.required_fraction


func native_solver() -> RefCounted:
	return _native


func set_particle(index: int, position: Vector3, velocity: Vector3) -> void:
	if _native != null:
		_native.call("set_particle_state", index, position, velocity)
		_sync_native()
	else:
		positions[index] = position
		velocities[index] = velocity


func _sync_native() -> void:
	var state: Dictionary = _native.call("get_state")
	positions = state.positions
	velocities = state.velocities
	active = state.active
	lost_count = state.lost
	goal_fraction = state.fraction
	held_seconds = state.held
	completed = state.completed


func _build_neighbors() -> void:
	_grid.clear()
	var search := material.interaction_radius + material.particle_spacing * 0.6
	var search2 := search * search
	for i: int in range(positions.size()):
		if active[i] == 0: continue
		var p := positions[i]
		var cell := Vector3i(floori(p.x / search), floori(p.y / search), floori(p.z / search))
		if not _grid.has(cell): _grid[cell] = []
		_grid[cell].append(i)
	for i: int in range(positions.size()):
		var list := PackedInt32Array()
		if active[i] == 0:
			_neighbors[i] = list
			continue
		var p := positions[i]
		var cell := Vector3i(floori(p.x / search), floori(p.y / search), floori(p.z / search))
		for cy: int in range(-1, 2):
			for cz: int in range(-1, 2):
				for cx: int in range(-1, 2):
					var bucket: Array = _grid.get(cell + Vector3i(cx, cy, cz), [])
					for j: int in bucket:
						if i != j and p.distance_squared_to(positions[j]) < search2: list.append(j)
		_neighbors[i] = list


func _substep(dt: float, gravity: Vector3) -> void:
	var count := positions.size()
	var h2 := material.interaction_radius * material.interaction_radius
	var gradient_scale := -6.0 / h2
	_contacts.fill(Vector3.ZERO)
	for i: int in range(count):
		if active[i] == 0: continue
		_previous[i] = positions[i]
		velocities[i] = ((velocities[i] + gravity * dt) * exp(-material.drag * dt)).limit_length(material.max_speed)
		positions[i] += velocities[i] * dt
		_constrain(i)
	_build_neighbors()
	for iteration: int in range(material.solver_iterations):
		for i: int in range(count):
			if active[i] == 0: continue
			var wall := _wall_kernel(positions[i])
			var inverse := 1.0 / (material.rest_density * wall.x)
			_inverse_density[i] = inverse
			var density := 1.0
			var gradient_i := Vector3.ZERO
			var gradient_sum := 0.0
			for j: int in _neighbors[i]:
				var difference := positions[i] - positions[j]
				var q := 1.0 - difference.length_squared() / h2
				if q <= 0.0: continue
				density += q * q * q
				var gradient := difference * (gradient_scale * q * q * inverse)
				gradient_i += gradient
				gradient_sum += gradient.length_squared()
			# Missing kernel support is completed at solid floors and finite
			# walls, preventing the old collapsed film along channel edges.
			_boundary_gradient[i] = Vector3(wall.y, wall.z, wall.w) * (-density * inverse / wall.x)
			gradient_i += _boundary_gradient[i]
			_densities[i] = density / wall.x
			# A small tensile limit keeps a free surface connected without
			# adding bulk viscosity or restoring a rigid source shape.
			var compression := maxf(density * inverse - 1.0, -material.surface_tension)
			_lambdas[i] = -compression / (gradient_sum + gradient_i.length_squared() + 0.8)
		for i: int in range(count):
			if active[i] == 0: continue
			var correction := _boundary_gradient[i] * _lambdas[i]
			for j: int in _neighbors[i]:
				var difference := positions[i] - positions[j]
				var q := 1.0 - difference.length_squared() / h2
				if q <= 0.0: continue
				var gradient := difference * (gradient_scale * q * q)
				correction += gradient * (_lambdas[i] * _inverse_density[i] + _lambdas[j] * _inverse_density[j])
			_corrections[i] = correction.limit_length(material.particle_spacing * 0.45)
		for i: int in range(count):
			if active[i] == 0: continue
			positions[i] += _corrections[i]
			_constrain(i)
	for i: int in range(count):
		if active[i] == 0: continue
		var velocity := ((positions[i] - _previous[i]) / dt).limit_length(material.max_speed)
		var normal := _contacts[i]
		if velocity.x * normal.x > 0.0: velocity.x = 0.0
		if velocity.y * normal.y > 0.0: velocity.y = 0.0
		if velocity.z * normal.z > 0.0: velocity.z = 0.0
		velocities[i] = velocity
	var smoothing := 1.0 - exp(-material.viscosity * dt)
	for i: int in range(count):
		if active[i] == 0: continue
		var change := Vector3.ZERO
		for j: int in _neighbors[i]:
			var q := 1.0 - positions[i].distance_squared_to(positions[j]) / h2
			if q > 0.0: change += (velocities[j] - velocities[i]) * (q * q * q / maxf(_densities[j], 1.0))
		_smoothed[i] = velocities[i] + change * smoothing
	for i: int in range(count):
		if active[i] == 0: continue
		velocities[i] = _smoothed[i]
		var p := positions[i]
		if p.y < level.base_height - 1.3 or not level.board_bounds.grow(1.25).has_point(Vector2(p.x, p.z)):
			active[i] = 0
			lost_count += 1


func _constrain(i: int) -> void:
	var bounded := level.constrain_world(positions[i], _previous[i], material.particle_radius)
	var outward := positions[i] - bounded
	var contacts := _contacts[i]
	if absf(outward.x) > 0.0000001: contacts.x = signf(outward.x)
	if absf(outward.y) > 0.0000001: contacts.y = signf(outward.y)
	if absf(outward.z) > 0.0000001: contacts.z = signf(outward.z)
	_contacts[i] = contacts
	positions[i] = bounded


func _build_wall_table() -> void:
	# 3D poly6 kernel half-space CDF: cross-sections are (1-u²)^4.
	_wall_table.resize(65)
	_wall_table[0] = 0.0
	var integral := 0.0
	for i: int in range(1, 65):
		var a := float(i - 1) / 64.0
		var b := float(i) / 64.0
		integral += (pow(1.0 - a * a, 4.0) + pow(1.0 - b * b, 4.0)) / 128.0
		_wall_table[i] = integral
	for i: int in range(65): _wall_table[i] = 0.5 + _wall_table[i] / integral * 0.5


func _wall_fraction(distance: float) -> Vector2:
	if distance >= material.interaction_radius: return Vector2(1.0, 0.0)
	var index := clampf(distance / material.interaction_radius * 64.0, 0.0, 63.9999)
	var lower := floori(index)
	var delta := _wall_table[lower + 1] - _wall_table[lower]
	return Vector2(_wall_table[lower] + delta * (index - lower), delta * 64.0 / material.interaction_radius)


func _wall_kernel(point: Vector3) -> Vector4:
	var dx := material.interaction_radius
	var dz := dx
	var nx := 0.0
	var nz := 0.0
	for wall: PackedFloat32Array in level.wall_segments():
		if point.y > wall[5] or point.y < wall[4] - material.interaction_radius: continue
		if absf(wall[0] - wall[2]) < 0.0001 and point.z >= wall[1] and point.z <= wall[3]:
			var distance := absf(point.x - wall[0])
			if distance < dx:
				dx = distance
				nx = signf(point.x - wall[0])
		elif absf(wall[1] - wall[3]) < 0.0001 and point.x >= wall[0] and point.x <= wall[2]:
			var distance := absf(point.z - wall[1])
			if distance < dz:
				dz = distance
				nz = signf(point.z - wall[1])
	var floor_y := level.floor_height(Vector2(point.x, point.z))
	var fx := _wall_fraction(dx)
	var fy := _wall_fraction(point.y - floor_y) if is_finite(floor_y) else Vector2(1.0, 0.0)
	var fz := _wall_fraction(dz)
	return Vector4(fx.x * fy.x * fz.x, fx.y * nx * fy.x * fz.x, fy.y * fx.x * fz.x, fz.y * nz * fx.x * fy.x)
