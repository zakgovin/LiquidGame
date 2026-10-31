extends SceneTree
## Optional real-render/UI smoke test; requires an X11/Wayland display.
## ./scripts/godot.sh --resolution 720x1280 --script res://tests/visual.gd

var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, description: String) -> void:
	print("PASS: " if ok else "FAIL: ", description)
	if not ok:
		failures += 1


func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://build/" + name + ".png") == OK, "Rendered " + name)


func tap(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	await process_frame
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame


func _run() -> void:
	root.size = Vector2i(720, 1280)
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	await capture("intro")
	await tap(Vector2(360, 790))
	check(game.running and game.hud._modal == null, "Start button receives pointer input")
	await process_frame
	# A real finger on the pad must work independently of emulated mouse events.
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.pressed = true
	touch.position = Vector2(598, 1140)
	Input.parse_input_event(touch)
	await process_frame
	check(game.controls.touch.y > 0.5, "Finger controls the tilt pad")
	# Releasing outside the pad must still clear its input.
	touch = InputEventScreenTouch.new()
	touch.index = 0
	touch.pressed = false
	touch.position = Vector2(200, 900)
	Input.parse_input_event(touch)
	await process_frame
	check(game.controls.touch == Vector2.ZERO, "Finger release outside pad does not stick")
	await tap(Vector2(648, 108))
	check(not game.running and game.hud._modal != null, "Pause button opens modal")
	await capture("pause")
	await tap(Vector2(360, 790))
	check(game.running and game.hud._modal == null, "Continue button resumes")
	game.set_physics_process(false)
	# Exercise actual game progression, including the controller's victory transition.
	for tilt: Vector2 in [Vector2.DOWN, Vector2.RIGHT, Vector2.DOWN]:
		game.controls.touch = tilt
		for frame: int in range(360):
			game._physics_process(1.0 / 60.0)
			if frame % 60 == 0:
				await process_frame
	check(game.simulation.completed and not game.running, "Real controller reaches victory")
	await capture("victory")
	await tap(Vector2(360, 790))
	check(game.running and game.simulation.goal_fraction == 0.0, "Victory replay button resets level")
	await capture("first-level")
	game.free()
	print("VISUAL RESULT: ", failures, " failures")
	quit(1 if failures else 0)
