extends SceneTree
## Real-render and native input smoke tests; requires a display.
var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, description: String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ", description)
	if not ok: failures += 1


func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://build/" + name + ".png") == OK, "Rendered " + name)


func tap(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.position = point
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame
	await process_frame


func _run() -> void:
	root.size = Vector2i(720, 1280)
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	await capture("v02-menu")
	await tap(game.hud.buttons["levels"])
	check(game.screen == game.Screen.LEVELS, "Level navigation opens from the menu")
	await capture("v02-levels")
	await tap(game.hud.buttons["level_0"])
	check(game.screen == game.Screen.MENU, "Available level selection returns to the play menu")
	await tap(game.hud.buttons["settings"])
	check(game.screen == game.Screen.SETTINGS, "Settings opens through its button")
	game.hud.mode_picker.select(1)
	game.hud.mode_picker.item_selected.emit(1)
	game.hud.slider.value = 1.0
	game.tilt_feedback = true
	game.hud.feedback_toggle.button_pressed = true
	await capture("v02-settings")
	await tap(game.hud.buttons["back"])
	await tap(game.hud.buttons["about"])
	check(game.screen == game.Screen.ABOUT, "Description opens through its button")
	await capture("v02-about")
	await tap(game.hud.buttons["back"])
	await tap(game.hud.buttons["play"])
	check(game.running and game.hud.page == null and game.hud.buttons.size() == 1, "Play opens clean gameplay with only pause")
	await capture("v02-game")
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = Vector2(300, 700)
	touch.pressed = true
	Input.parse_input_event(touch)
	await process_frame
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(420, 820)
	Input.parse_input_event(drag)
	await process_frame
	check(game.controls.touch.x > 0.5 and game.controls.touch.y > 0.5, "Dragging the bare field controls tilt without a joystick")
	touch = InputEventScreenTouch.new()
	touch.index = 0
	touch.position = Vector2(710, 1260)
	touch.pressed = false
	Input.parse_input_event(touch)
	await process_frame
	check(game.controls.touch == Vector2.ZERO, "Releasing away from the initial touch clears input")
	await tap(game.hud.buttons["pause"])
	check(game.screen == game.Screen.PAUSED, "Pause remains clickable with field gestures enabled")
	await capture("v02-pause")
	await tap(game.hud.buttons["resume"])
	check(game.running, "Continue resumes gameplay")
	await tap(game.hud.buttons["pause"])
	await tap(game.hud.buttons["restart"])
	check(game.running and game.simulation.goal_fraction == 0.0, "Restart is accessible from pause")
	await tap(game.hud.buttons["pause"])
	await tap(game.hud.buttons["exit"])
	check(game.screen == game.Screen.MENU and root.is_inside_tree(), "Exit returns to the menu instead of quitting the application")
	root.size = Vector2i(720, 1600)
	await process_frame
	await process_frame
	check(game.hud.buttons["play"].get_global_rect().end.y < 1600, "Menu adapts to a tall phone without letterboxing or offscreen buttons")
	await capture("v02-menu-tall")
	root.size = Vector2i(720, 1280)
	await process_frame
	await tap(game.hud.buttons["play"])
	game.set_physics_process(false)
	game.controls.touch = Vector2(0.75, 0.4)
	for i: int in range(30): game._physics_process(1.0 / 60.0)
	check(game.pivot.rotation.z < -0.02 and game.pivot.rotation.x > 0.01, "Board visibly follows both axes of inclination")
	await capture("v02-tilt")
	game._restart()
	for direction: Vector2 in [Vector2.DOWN, Vector2(1, 0.5), Vector2(0.5, -1), Vector2(-1, -0.5), Vector2(-0.4, 1), Vector2.DOWN]:
		game.controls.touch = direction.normalized()
		for frame: int in range(600):
			game._physics_process(1.0 / 60.0)
			if frame % 120 == 0: await process_frame
	print("Controller delivered fraction: ", game.simulation.goal_fraction)
	check(game.simulation.completed and game.screen == game.Screen.WON, "Complete 360-degree route reaches the victory screen through the controller")
	await capture("v02-victory")
	if game.hud.buttons.has("win_menu"):
		await tap(game.hud.buttons["win_menu"])
		check(game.screen == game.Screen.MENU, "Victory returns to the main menu")
	game.free()
	print("VISUAL RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
