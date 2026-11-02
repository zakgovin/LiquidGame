extends RefCounted
const WATER = preload("res://resources/water.tres")
const LEVELS: Array[LevelDefinition] = [preload("res://resources/fifth_level.tres"), preload("res://resources/sixth_level.tres"), preload("res://resources/seventh_level.tres"), preload("res://resources/eighth_level.tres"), preload("res://resources/ninth_level.tres")]


static func advance(f: LiquidSimulation, frames: int, direction: Vector2 = Vector2.ZERO) -> void:
	for i: int in range(frames): f.settle(1.0 / 60.0, direction)


static func accounted(f: LiquidSimulation) -> bool:
	return f.water_count + f.ice_count + f.vapor_count + f.lost_count == f.level.particle_count and f.delivered_count + f.remaining_count + f.lost_count == f.level.particle_count


static func thermal_check(check: Callable) -> void:
	var level := LEVELS[2].duplicate() as LevelDefinition
	level.particle_count = 1
	var f := LiquidSimulation.new(level, WATER)
	var solver := f.native_solver()
	var mass := pow(WATER.particle_spacing, 3) * WATER.rest_density
	solver.call("set_particle_enthalpy", 0, 333000.0)
	f.step(0, Vector2.ZERO)
	check.call(f.phases[0] == 0 and absf(f.temperatures[0]) < 0.001, "Removing latent heat holds liquid at zero before solidification")
	solver.call("set_particle_enthalpy", 0, -21000.0)
	f.step(0, Vector2.ZERO)
	check.call(f.phases[0] == 1 and is_equal_approx(f.temperatures[0], -10) and f.ice_body_count == 1 and accounted(f), "A fully frozen parcel becomes a solid body at its physical temperature")
	solver.call("set_particle_enthalpy", 0, 167000.0)
	f.step(0, Vector2.ZERO)
	check.call(f.phases[0] == 1 and absf(f.temperatures[0]) < 0.001, "Melting consumes fusion energy while ice remains at zero")
	solver.call("set_particle_enthalpy", 0, 334000.0 + 4180.0 * 25.0)
	f.step(0, Vector2.ZERO)
	check.call(f.phases[0] == 0 and is_equal_approx(f.temperatures[0], 25) and accounted(f), "Melting returns the same mass to the liquid solver")
	solver.call("set_particle_enthalpy", 0, 752000.0 + 1128000.0)
	f.step(0, Vector2.ZERO)
	check.call(f.phases[0] == 0 and is_equal_approx(f.temperatures[0], 100), "Boiling consumes vaporization energy at one hundred degrees")
	solver.call("set_particle_enthalpy", 0, 3008000.0 + 2010.0 * 5.0)
	f.step(0, Vector2.ZERO)
	var state: Dictionary = solver.call("get_state")
	check.call(f.vapor_count == 1 and f.lost_count == 0 and is_equal_approx(f.temperatures[0], 105) and is_equal_approx(state.active_mass, mass), "Evaporation creates active vapor without deleting its mass")
	f.set_particle(0, Vector3(-1.6, 0.20, 1.0), Vector3.ZERO)
	var before := f.positions[0].y
	f.set_gate_opening(1)
	advance(f, 30)
	check.call(f.positions[0].y > before + 0.08 and f.lost_count == 0, "Hot vapor rises as a separate physical phase")
	advance(f, 240)
	check.call(f.lost_count == 1 and f.escaped_vapor == 1 and f.lost_without_rim == 0 and accounted(f), "Vapor becomes a loss only after escaping through the open upper boundary")
	f.reset()
	check.call(f.water_count == 1 and f.ice_count == 0 and f.vapor_count == 0 and f.lost_count == 0 and is_equal_approx(f.temperatures[0], 20), "Restart restores the original liquid and temperature")
	f.set_gate_opening(1)
	f.set_particle(0, Vector3(-1.6, 0.17, 1.0), Vector3.ZERO)
	var energy := f.thermal_enthalpy
	advance(f, 90)
	check.call(f.temperatures[0] > 99 and f.phases[0] == 0 and f.heat_input > 0, "The real heater raises temperature and supplies latent heat over time")
	check.call(absf((f.thermal_enthalpy - energy) - f.heat_input) < maxf(1.0, absf(f.heat_input) * 0.0001), "Accounted thermal energy changes by the supplied environmental heat")
	advance(f, 480)
	check.call(f.lost_count == 1 and f.escaped_vapor == 1 and accounted(f), "Lingering on the actual heater boils the original liquid and loses it through the vapor vent")


static func gate_case(speed: float, count: int) -> LiquidSimulation:
	var level := LEVELS[1].duplicate() as LevelDefinition
	level.particle_count = count
	var f := LiquidSimulation.new(level, WATER)
	f.set_gate_opening(1)
	var hinge: Vector3 = level.impact_gate.hinge
	for i: int in range(count):
		var x := hinge.x - 0.07 - (i % 8) * 0.037
		var y := 0.165 + ((i / 8) % 4) * 0.037
		var z := hinge.z - 0.50 + ((i / 32) % 32) * 0.032
		f.native_solver().call("set_particle_state", i, Vector3(x, y, z), Vector3(speed, 0, 0))
	advance(f, 150)
	return f


static func run(check: Callable) -> void:
	for index: int in range(5):
		check.call(LEVELS[index].safe_goal == (index >= 2), "Receiver protection matches the requested rule on level %d" % (index + 5))
	thermal_check(check)
	var weak := gate_case(0.3, 1024)
	check.call(not weak.impact_latched and weak.impact_angle < 0.05, "A weak jet leaves the spring gate closed")
	weak = null
	var drop := gate_case(3.2, 1)
	check.call(not drop.impact_latched, "One fast droplet lacks the impulse to open the gate")
	drop = null
	var strong := gate_case(2.2, 1024)
	check.call(strong.impact_latched and strong.impact_angle > 1.3, "A dense, fast jet physically opens and latches the gate")
	strong.reset()
	check.call(not strong.impact_latched and strong.impact_angle == 0, "Restart closes and rearms the spring mechanism")
	strong = null
	for level: LevelDefinition in [LEVELS[0], LEVELS[1]]:
		var one := level.duplicate() as LevelDefinition
		one.particle_count = 1
		var f := LiquidSimulation.new(one, WATER)
		f.set_gate_opening(1)
		var g := level.goal
		f.set_particle(0, Vector3(g.get_center().x, level.floor_height(g.get_center()) + 0.6, g.position.y + 0.15), Vector3(0, 0, -2.2))
		advance(f, 12, Vector2.UP)
		check.call(f.secured_count == 0 and f.goal_fraction == 0 and f.active[0], "An open final vessel really allows water to flow back out: " + level.title)
	var frozen := LiquidSimulation.new(LEVELS[4], WATER)
	frozen.set_gate_opening(0)
	var distance := frozen.positions[0].distance_to(frozen.positions[-1])
	advance(frozen, 90, Vector2(1, 1).normalized())
	check.call(frozen.ice_count == frozen.level.particle_count and frozen.ice_body_count == 1 and frozen.lost_count == 0, "Frozen source water is one retained solid body")
	check.call(absf(frozen.positions[0].distance_to(frozen.positions[-1]) - distance) < 0.0002, "Ice preserves rigid distances while colliding with the source walls")
	frozen.reset()
	check.call(frozen.ice_count == frozen.level.particle_count and is_equal_approx(frozen.temperatures[0], -12), "Thaw restarts with the original frozen state")
	frozen = null
	var grate := LEVELS[3].duplicate() as LevelDefinition
	grate.heat_regions = []
	grate.particle_count = 1
	var liquid := LiquidSimulation.new(grate, WATER)
	liquid.set_gate_opening(1)
	liquid.set_particle(0, Vector3(0.7, 0.64, -0.42), Vector3.ZERO)
	advance(liquid, 90)
	check.call(liquid.lost_count == 1 and liquid.lost_in_void == 1, "Liquid really falls between the grate rails")
	liquid = null
	grate.particle_count = 512
	grate.initial_phase = 1
	grate.initial_temperature = -10
	var solid := LiquidSimulation.new(grate, WATER)
	solid.set_gate_opening(1)
	for i: int in range(512):
		var p := Vector3(0.40 + (i % 16) * 0.036, 0.578 + ((i / 16) % 4) * 0.030, -0.63 + (i / 64) * 0.065)
		solid.native_solver().call("set_particle_state", i, p, Vector3.ZERO)
	advance(solid, 90)
	check.call(solid.ice_count == 512 and solid.ice_body_count == 1 and solid.lost_count == 0, "A rigid ice block spans the same grate openings without leaking through")
	solid = null
	var receiver := LEVELS[3].duplicate() as LevelDefinition
	receiver.heat_regions = []
	receiver.initial_phase = 1
	receiver.initial_temperature = -10
	receiver.particle_count = 512
	var retained := LiquidSimulation.new(receiver, WATER)
	retained.set_gate_opening(1)
	for i: int in range(512):
		var p := Vector3(receiver.goal.get_center().x + ((i % 16) - 7.5) * 0.035, 0.30 + ((i / 16) % 4) * 0.035, receiver.goal.position.y - 0.02 + (i / 64) * 0.04)
		retained.native_solver().call("set_particle_state", i, p, Vector3.ZERO)
	advance(retained, 1)
	check.call(retained.delivered_count == 0 and retained.secured_count == 0 and not retained.completed, "A rigid block straddling the receiver does not count as safely delivered")
	for i: int in range(512):
		var p := Vector3(receiver.goal.get_center().x + ((i % 16) - 7.5) * 0.035, -0.10 + ((i / 16) % 4) * 0.035, receiver.goal.position.y + 0.40 + (i / 64) * 0.04)
		retained.native_solver().call("set_particle_state", i, p, Vector3.ZERO)
	advance(retained, 90)
	check.call(retained.completed and retained.delivered_count == 512 and retained.secured_count == 512, "A fully admitted ice body engages the protected receiver")
	var rigid_distance := retained.positions[0].distance_to(retained.positions[-1])
	for direction: Vector2 in [Vector2.UP, Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN]: advance(retained, 60, direction)
	var inside := true
	for p: Vector3 in retained.positions: inside = inside and receiver.goal.has_point(Vector2(p.x, p.z)) and p.y >= receiver.floor_height(Vector2(p.x, p.z)) and p.y < receiver.board_top
	check.call(inside and retained.secured_count == 512 and retained.delivered_count == 512 and accounted(retained) and absf(retained.positions[0].distance_to(retained.positions[-1]) - rigid_distance) < 0.0002, "Reverse gravity retains visible ice inside the vessel without deforming or deleting it")
