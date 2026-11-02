extends "res://tests/visual.gd"

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game._select_level(0)
	game._start()
	game._release()
	for i: int in range(44): game._physics_process(1.0/60.0)
	for i: int in range(360):
		game.simulation.step(1.0/60.0,Vector2.DOWN)
	game.surface.rebuild(game.simulation.positions,game.level,game.simulation.active,game.simulation.native_solver())
	game.surface.set_flow_time(game.simulation.elapsed_seconds)
	await check_water_visibility(game)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/v015-water-step.png")
	game._change_level(9)
	game._restart()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/v015-final-ready.png")
	game.camera.position=Vector3(0,50,7)
	game.camera.look_at(Vector3(0,0,7),Vector3.FORWARD)
	game.camera.size=11.0
	game.camera.v_offset=0
	game.surface.rebuild(game.simulation.positions,game.level,game.simulation.active,game.simulation.native_solver())
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/v015-final-map.png")
	print("ITERATION15_RENDER_RESULT failures=",failures)
	game.free()
	await process_frame
	quit(failures)
