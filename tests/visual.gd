extends SceneTree
## Real-render, mobile touch, menu animation, reservoir and audio smoke tests.
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


func swipe(from: Vector2, to: Vector2) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = from
	touch.pressed = true
	Input.parse_input_event(touch)
	await process_frame
	for step: int in range(1, 9):
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.position = from.lerp(to, float(step) / 8.0)
		drag.relative = (to - from) / 8.0
		Input.parse_input_event(drag)
		await process_frame
	touch = InputEventScreenTouch.new()
	touch.index = 0
	touch.position = to
	touch.pressed = false
	Input.parse_input_event(touch)
	await process_frame


func release_water(game: Node) -> void:
	await tap(game.hud.buttons["release"])
	for i: int in range(ceil(game.OPEN_SECONDS * 60) + 2): game._physics_process(1.0 / 60.0)
	await process_frame


func _run() -> void:
	Input.emulate_touch_from_mouse = true
	root.size = Vector2i(720, 1280)
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.language_code = "ru"
	TranslationServer.set_locale("ru")
	game._menu()
	game.sounds.set_enabled(true)
	var events: Array[StringName] = []
	game.sounds.played.connect(func(event: StringName): events.append(event))
	await process_frame
	check(not game.pivot.visible, "Menu contains no gameplay background")
	await capture("v06-menu")
	var phase: float = game.hud.brand.phase
	await process_frame
	await process_frame
	check(game.hud.brand.phase != phase, "Water animates inside the integrated title lockup")
	await capture("v06-menu-animated")
	await tap(game.hud.buttons["levels"])
	check(game.screen == game.Screen.LEVELS, "Level navigation opens through touch")
	check(game.hud.buttons["back"].get_global_rect().position.y > 1100, "Main-menu navigation is within the bottom thumb area")
	await capture("v06-levels")
	await tap(game.hud.buttons["level_0"])
	await tap(game.hud.buttons["settings"])
	check(game.screen == game.Screen.SETTINGS, "Settings opens through touch")
	await tap(game.hud.buttons["mode_tilt"])
	check(not game.controls.use_touch, "Segmented control selects phone tilt")
	await tap(game.hud.buttons["mode_touch"])
	check(game.controls.use_touch, "Segmented control selects field gestures")
	var slider: HSlider = game.hud.slider
	var initial: float = slider.value
	var rect := slider.get_global_rect()
	await swipe(rect.get_center(), rect.get_center() + Vector2(140, 0))
	check(not is_equal_approx(slider.value, initial), "Large slider responds to an actual touch drag")
	slider.value = 1.0
	game.hud.feedback_toggle.button_pressed = true
	game.hud.sound_toggle.button_pressed = true
	await capture("v06-settings")
	var sensitivity_card: Node = game.hud.slider.find_parent("SensitivityGroup")
	check(sensitivity_card != null and not sensitivity_card.is_ancestor_of(game.hud.buttons["mode_tilt"]), "Sensitivity is visually grouped apart from the control-mode switch")
	for label: Label in sensitivity_card.find_children("*", "Label", true, false):
		if label.text == tr("SENSITIVITY"): check(label.get_line_count() == 1, "Long Russian sensitivity title fits without splitting the word")
	await tap(game.hud.buttons["language_en"])
	check(game.language_code == "en" and game.hud.buttons["back"].text == "Main menu", "Touch selects English and translates settings")
	await capture("v06-settings-en")
	await tap(game.hud.buttons["language_ru"])
	check(game.hud.buttons["back"].text == "В главное меню", "Touch selects Russian again")
	await swipe(Vector2(400, 980), Vector2(400, 440))
	check(game.hud.settings_scroll.scroll_vertical > 0, "Settings content scrolls with a vertical phone gesture")
	check(game.hud.buttons["back"].get_global_rect().position.y > 1100, "Bottom navigation stays fixed while settings scroll")
	await capture("v06-settings-bottom")
	await tap(game.hud.buttons["back"])
	await tap(game.hud.buttons["about"])
	check(game.screen == game.Screen.ABOUT, "About screen opens")
	await capture("v06-about")
	game.hud.settings_scroll.scroll_vertical = 2000
	await process_frame
	await capture("v06-credits")
	await tap(game.hud.buttons["back"])
	root.size = Vector2i(720, 1600)
	await process_frame
	await tap(game.hud.buttons["settings"])
	await process_frame
	check(game.hud.buttons["back"].get_global_rect().position.y > 1400, "Bottom navigation follows the physical bottom on a tall screen")
	await capture("v06-settings-tall")
	await tap(game.hud.buttons["back"])
	await capture("v06-menu-tall")
	root.size = Vector2i(720, 1280)
	await process_frame
	await tap(game.hud.buttons["play"])
	check(game.screen == game.Screen.READY and not game.running, "Play opens the closed reservoir before physics starts")
	var held: PackedVector3Array = game.simulation.positions.duplicate()
	game.controls.touch = Vector2.DOWN
	for i: int in range(90): game._physics_process(1.0 / 60.0)
	check(held == game.simulation.positions and game.board.reservoir.visible, "Water stays enclosed until the player releases it")
	await capture("v06-reservoir")
	await tap(game.hud.buttons["pause"])
	await tap(game.hud.buttons["resume"])
	check(game.screen == game.Screen.READY and not game.running, "Continue during preparation keeps the reservoir closed")
	await release_water(game)
	check(game.running and game.hud.page == null and game.hud.buttons.size() == 1 and game.board.gate_open_amount >= 0.999, "Release opens the gate and leaves only pause in gameplay")
	check(events.has(&"click") and events.has(&"start"), "Touch interactions and releasing water trigger their audio cues")
	await capture("v06-game")
	await swipe(Vector2(300, 600), Vector2(430, 730))
	check(game.controls.touch == Vector2.ZERO, "Releasing the field gesture clears control input")
	game.controls.touch = game.world_to_input(Vector2(0.12, 0.75))
	for frame: int in range(120): game._physics_process(1.0 / 60.0)
	await capture("v06-flow-close")
	check(game.pivot.rotation.z < 0 and game.pivot.rotation.x > 0, "The complete 3D scene follows the inclination")
	check(game.board.hazard_edges.size() >= 4, "Four real height changes have hazard-marked edges")
	await tap(game.hud.buttons["pause"])
	check(game.screen == game.Screen.PAUSED, "Pause stays accessible over the field")
	await capture("v06-pause")
	await tap(game.hud.buttons["restart"])
	check(game.screen == game.Screen.READY and game.board.reservoir.visible, "Restart refills and closes the reservoir")
	await release_water(game)
	var circuit: Array[Vector2] = [Vector2.DOWN, Vector2(1, 0.5), Vector2(0.5, -1), Vector2(-1, -0.5), Vector2(-0.4, 1), Vector2.DOWN]
	var stage := 0
	var saw_finish := false
	for direction: Vector2 in circuit:
		game.controls.touch = game.world_to_input(direction.normalized())
		for frame: int in range(600):
			game._physics_process(1.0 / 60.0)
			if game.screen == game.Screen.FINISHING and not saw_finish:
				saw_finish = true
				check(game.hud.page == null and not game.hud.field.active, "Actual delivered water stays visible before the result modal")
				await capture("v06-filled-vessel")
			if frame % 120 == 0: await process_frame
		stage += 1
		await capture("v06-circuit-%d" % stage)
	print("Controller delivered fraction: ", game.simulation.goal_fraction)
	check(game.simulation.completed and game.screen == game.Screen.WON, "The full 360-degree circuit completes through the real game controller")
	check(saw_finish, "Full circuit passes through the half-second delivery presentation")
	check(events.count(&"complete") == 1, "Completion plays its cue exactly once")
	await capture("v06-victory")
	if game.hud.buttons.has("win_menu"):
		await tap(game.hud.buttons["win_menu"])
		check(game.screen == game.Screen.MENU, "Victory returns to the main menu")
	game.sounds.set_enabled(false)
	game.free()
	await process_frame
	await process_frame
	await create_timer(0.08).timeout
	print("VISUAL RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
