class_name LiquidSimulation
extends RefCounted
## Position-based particle fluid: double-density relaxation (Clavet et al.).
## A shallow, planar liquid on a 3D board, not a full volumetric water solver.
## Fixed substeps, spatial hashing, union-of-rectangles containment; no rigid balls.

var level: LevelDefinition
var material: LiquidProfile
var positions := PackedVector2Array()
var velocities := PackedVector2Array()
var _previous := PackedVector2Array()
var _grid: Dictionary = {}
var _neighbors := PackedInt32Array()
var _distances := PackedFloat32Array()
var goal_fraction: float = 0.0
var held_seconds: float = 0.0
var completed: bool = false


func _init(definition: LevelDefinition, profile: LiquidProfile) -> void:
	level = definition
	material = profile
	reset()


func reset() -> void:
	positions.resize(level.particle_count)
	velocities.resize(level.particle_count)
	_previous.resize(level.particle_count)
	var columns := maxi(1, floori((level.spawn.size.x - 0.12) / 0.106))
	for i: int in range(level.particle_count):
		var column := i % columns
		var row := i / columns
		positions[i] = level.spawn.position + Vector2(0.13 + column * 0.106, 0.12 + row * 0.106)
		velocities[i] = Vector2.ZERO
	goal_fraction = 0.0
	held_seconds = 0.0
	completed = false


func step(delta: float, tilt: Vector2) -> void:
	if completed or delta <= 0.0:
		return
	# Clamp interruptions; the caller uses Godot's fixed 60 Hz physics clock.
	var dt := minf(delta, 1.0 / 30.0) * 0.5
	for substep: int in range(2):
		_substep(dt, tilt.limit_length(1.0) * 8.5)
	var count := 0
	for point: Vector2 in positions:
		if level.goal.has_point(point):
			count += 1
	goal_fraction = float(count) / positions.size()
	if goal_fraction >= level.required_fraction:
		held_seconds += dt * 2.0
	else:
		held_seconds = 0.0
	completed = held_seconds >= level.hold_seconds


func _rebuild_grid() -> void:
	_grid.clear()
	var h := material.interaction_radius
	for i: int in range(positions.size()):
		var cell := Vector2i(floori(positions[i].x / h), floori(positions[i].y / h))
		if not _grid.has(cell):
			_grid[cell] = []
		_grid[cell].append(i)


func _substep(dt: float, acceleration: Vector2) -> void:
	var h := material.interaction_radius
	var h_squared := h * h
	var count := positions.size()
	for i: int in range(count):
		_previous[i] = positions[i]
		velocities[i] = (velocities[i] + acceleration * dt) * exp(-material.drag * dt)
		positions[i] += velocities[i].limit_length(material.max_speed) * dt
	for iteration: int in range(2):
		_rebuild_grid()
		for i: int in range(count):
			var point := positions[i]
			var cell := Vector2i(floori(point.x / h), floori(point.y / h))
			var density := 0.0
			var near_density := 0.0
			_neighbors.clear()
			_distances.clear()
			for cy: int in range(-1, 2):
				for cx: int in range(-1, 2):
					var bucket: Array = _grid.get(cell + Vector2i(cx, cy), [])
					for j: int in bucket:
						if j == i:
							continue
						var d_squared := point.distance_squared_to(positions[j])
						if d_squared >= h_squared or d_squared < 0.0000001:
							continue
						var distance := sqrt(d_squared)
						var q := 1.0 - distance / h
						density += q * q
						near_density += q * q * q
						_neighbors.append(j)
						_distances.append(distance)
			# Negative pressure supplies limited cohesion / surface tension.
			var pressure := material.pressure_stiffness * (density - material.rest_density)
			pressure = maxf(pressure, -material.cohesion_pressure)
			var near_pressure := material.near_pressure_stiffness * near_density
			var correction := Vector2.ZERO
			for n: int in range(_neighbors.size()):
				var j := _neighbors[n]
				var distance := _distances[n]
				var direction := (positions[j] - point) / distance
				var q := 1.0 - distance / h
				var displacement := direction * (dt * dt * (pressure * q + near_pressure * q * q) * 0.5)
				positions[j] += displacement
				correction -= displacement
			positions[i] += correction
		for i: int in range(count):
			positions[i] = level.constrain(positions[i], material.particle_radius)
	for i: int in range(count):
		velocities[i] = ((positions[i] - _previous[i]) / dt).limit_length(material.max_speed)
	# Pairwise viscosity transfers momentum without an order-dependent global drag.
	for i: int in range(count):
		var point := positions[i]
		var cell := Vector2i(floori(point.x / h), floori(point.y / h))
		for cy: int in range(-1, 2):
			for cx: int in range(-1, 2):
				var bucket: Array = _grid.get(cell + Vector2i(cx, cy), [])
				for j: int in bucket:
					if j <= i:
						continue
					var d := point.distance_to(positions[j])
					if d >= h:
						continue
					var impulse := (velocities[j] - velocities[i]) * (material.viscosity * dt * (1.0 - d / h))
					velocities[i] += impulse
					velocities[j] -= impulse
