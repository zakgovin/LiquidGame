class_name LiquidSimulation
extends RefCounted
## Volumetric incompressible MAC / FLIP water. Native and renderer state share
## the same particles, solid terrain, pressure projection and physical volume.

var level: LevelDefinition
var material: LiquidProfile
var positions := PackedVector3Array()
var velocities := PackedVector3Array()
var active := PackedByteArray()
var lost_count: int = 0
var delivered_count: int = 0
var remaining_count: int = 0
var lost_without_rim: int = 0
var spill_points := PackedVector3Array()
var goal_fraction: float = 0.0
var held_seconds: float = 0.0
var completed: bool = false
var maximum_divergence: float = 0.0
var liquid_volume: float = 0.0
var liquid_cell_count: int = 0
var pressure_iterations: int = 0
var _native: RefCounted


func _init(definition: LevelDefinition, profile: LiquidProfile) -> void:
	level = definition
	material = profile
	assert(ClassDB.class_exists("NativeLiquidSolver"), "Build the native water module with scripts/setup.py before opening this project.")
	_native = ClassDB.instantiate("NativeLiquidSolver") as RefCounted
	_native.call("configure", {
		"regions": level.floor_regions, "elevations": level.floor_elevations,
		"walls": level.wall_segments(), "tiles": level.terrain_tiles(), "bounds": level.board_bounds,
		"reservoir": level.reservoir_bounds, "spawn": level.spawn, "goal": level.goal,
		"count": level.particle_count, "top": level.board_top, "base": level.base_height, "flow_speed": level.flow_speed,
		"radius": material.particle_radius, "spacing": material.particle_spacing,
		"rho": material.rest_density, "drag": material.drag, "max_speed": material.max_speed,
		"viscosity": material.viscosity, "surface_tension": material.surface_tension, "required": level.required_fraction, "hold": level.hold_seconds})
	_sync_native()


func reset() -> void:
	_native.call("reset")
	_sync_native()


func step(delta: float, tilt: Vector2) -> void:
	_native.call("step", delta, tilt)
	_sync_native()


func settle(delta: float, tilt: Vector2) -> void:
	_native.call("settle", delta, tilt)
	_sync_native()


func set_gate_opening(amount: float) -> void:
	_native.call("set_gate_opening", amount)


func is_unwinnable() -> bool:
	return float(positions.size() - lost_count) / positions.size() < level.required_fraction


func native_solver() -> RefCounted:
	return _native


func set_particle(index: int, position: Vector3, velocity: Vector3) -> void:
	_native.call("set_particle_state", index, position, velocity)
	_sync_native()


func _sync_native() -> void:
	var state: Dictionary = _native.call("get_state")
	positions = state.positions
	velocities = state.velocities
	active = state.active
	lost_count = state.lost
	delivered_count = state.delivered
	remaining_count = state.remaining
	lost_without_rim = state.lost_without_rim
	spill_points = state.spills
	goal_fraction = state.fraction
	held_seconds = state.held
	completed = state.completed
	maximum_divergence = state.divergence
	liquid_volume = state.volume
	liquid_cell_count = state.cells
	pressure_iterations = state.pressure_steps
