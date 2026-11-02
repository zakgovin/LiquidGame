extends SceneTree
## Reproduce the material study with one frozen physical state and camera.
## Run with a real OpenGL display; outputs are written to ignored build/.
var game: Node


func _initialize() -> void:
	_run.call_deferred()


func frame_image() -> Image:
	for i: int in range(12): await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func capture_variant(label: String) -> Dictionary:
	game.surface.hide()
	var dry := await frame_image()
	game.surface.show()
	var wet := await frame_image()
	wet.save_png("res://build/study-" + label + ".png")
	var count := 0
	var separation := 0.0
	var luminance := 0.0
	var blue := 0.0
	for y: int in range(0, wet.get_height(), 2):
		for x: int in range(0, wet.get_width(), 2):
			var a := dry.get_pixel(x, y)
			var b := wet.get_pixel(x, y)
			var distance := Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()
			if distance < 0.03: continue
			count += 1
			separation += distance
			luminance += b.get_luminance()
			blue += b.b - b.r
	return {"samples": count, "rgb_distance": separation / maxf(1, count), "luminance": luminance / maxf(1, count), "blue_minus_red": blue / maxf(1, count)}


func _run() -> void:
	root.size = Vector2i(720, 1600)
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.sounds.set_enabled(false)
	game.controls.use_rotation = false
	game._select_level(0)
	game._start()
	game.hud.show_game(false)
	game.board.set_reservoir_open_amount(1.0)
	game.simulation.set_gate_opening(1.0)
	for i: int in range(150): game.simulation.step(1.0 / 60.0, Vector2.DOWN * 0.7)
	game.surface.rebuild(game.simulation.positions, game.level, game.simulation.active, game.simulation.native_solver())
	game.pivot.rotation = Vector3(0.045, 0, -0.015)
	var results := {}
	if "marble" in OS.get_cmdline_user_args():
		for contrast: float in [0.0, 0.09, 0.18]:
			game.board.foundation.set_shader_parameter("vein_strength", contrast)
			for material: ShaderMaterial in game.board.floor_materials: material.set_shader_parameter("vein_strength", contrast)
			var label := "marble-%02d" % roundi(contrast * 100)
			results[label] = await capture_variant(label)
	else:
		results["warm_contact"] = await capture_variant("warm")
		for material: ShaderMaterial in game.board.floor_materials: material.set_shader_parameter("stone_color", Color("d5dde0"))
		game.board.foundation.set_shader_parameter("stone_color", Color("8c9da7"))
		game.board.contact_material.set_shader_parameter("strength", 0.0)
		var environment: Environment
		for child: Node in game.get_children():
			if child is WorldEnvironment: environment = child.environment
		environment.ssao_enabled = true
		environment.ssao_radius = 0.20
		environment.ssao_intensity = 0.50
		results["cool_ssao"] = await capture_variant("cool-ssao")
		environment.ssao_enabled = false
		for material: ShaderMaterial in game.board.floor_materials: material.set_shader_parameter("stone_color", Color("38444c"))
		game.board.foundation.set_shader_parameter("stone_color", Color("1f2d35"))
		game.board.contact_material.set_shader_parameter("strength", 1.0)
		results["dark_contact"] = await capture_variant("dark")
	var output := FileAccess.open("res://build/visual-study.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(results, "\t"))
	output.close()
	print("Visual study: ", results)
	game.free()
	await process_frame
	quit()
