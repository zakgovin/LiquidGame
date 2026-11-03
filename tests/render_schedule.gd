extends SceneTree
var failures := 0
var checks := 0

class CountingSurface extends FluidSurface:
	var builds := 0
	var last_positions := PackedVector3Array()
	func rebuild(particles: PackedVector3Array, _level: LevelDefinition, _active: PackedByteArray = PackedByteArray(), _solver: RefCounted = null) -> void:
		builds += 1
		last_positions = particles


func _initialize() -> void: _run.call_deferred()


func check(ok: bool, description: String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ",description)
	if not ok: failures += 1


func _run() -> void:
	assert(DisplayServer.get_name() != "headless", "Run this test with OpenGL under Xvfb")
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.set_process(false)
	game.surface.free()
	var counter := CountingSurface.new(game.WATER)
	game.surface = counter
	game.pivot.add_child(counter)
	game._select_level(9)
	game._start()
	game._release()
	counter.builds = 0
	for frame: int in range(4): game._physics_process(1.0/60.0)
	check(counter.builds==0,"Catch-up physics creates no intermediate meshes that will never be displayed")
	game._process(0.10)
	check(counter.builds==1 and counter.last_positions==game.simulation.positions,"One displayed frame reconstructs exactly the latest physical state")
	game._physics_process(1.0/60.0)
	game._process(1.0/120.0)
	game._process(1.0/120.0)
	check(counter.builds==1,"A high-refresh display cannot force reconstruction above its thirty-Hz budget")
	game._process(1.0/60.0+0.000001)
	check(counter.builds==2,"Pending water is reconstructed when its next display update is due")
	game._process(0.1)
	check(counter.builds==2,"An unchanged state does not rebuild just because another render frame arrived")
	game._physics_process(1.0/60.0)
	game._pause()
	var paused: PackedVector3Array = game.simulation.positions.duplicate()
	game._process(0.1)
	check(counter.builds==3 and counter.last_positions==paused,"Pause still displays the last physical state")
	for frame: int in range(4): game._physics_process(1.0/60.0)
	game._process(0.1)
	check(counter.builds==3 and game.simulation.positions==paused,"Pause neither advances water nor schedules redundant meshes")
	game._resume()
	game._physics_process(1.0/60.0)
	game._menu()
	game._process(0.1)
	check(counter.builds==3,"The hidden gameplay scene does no water reconstruction in the menu")
	game._start()
	var ready_builds := counter.builds
	game._process(0.1)
	check(counter.builds==ready_builds and counter.last_positions==game.simulation.positions,"Restart shows fresh sealed water and discards the previous pending render")
	game._begin_finish()
	check(counter.builds==ready_builds,"Completion schedules its final image without blocking a physics tick")
	game._process(0.1)
	check(counter.builds==ready_builds+1,"The completion phase displays its final water state")
	game.free()
	await process_frame
	await process_frame
	await create_timer(0.1).timeout
	print("RENDER_SCHEDULE_RESULT checks=",checks," failures=",failures)
	quit(failures)
