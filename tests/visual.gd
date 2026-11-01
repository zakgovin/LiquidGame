extends SceneTree
## Real rendering and native touch events, including scaled-window rotation.
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


func send_touch(point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = root.get_final_transform() * point
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame


func tap(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	await send_touch(point, true)
	await send_touch(point, false)
	await process_frame


func swipe(from: Vector2, to: Vector2) -> void:
	await send_touch(from, true)
	for step: int in range(1, 9):
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.position = root.get_final_transform() * from.lerp(to, float(step) / 8.0)
		drag.relative = root.get_final_transform().basis_xform((to - from) / 8.0)
		Input.parse_input_event(drag)
		await process_frame
	await send_touch(to, false)
	await process_frame


func arc(game: Node, radius: float, from_angle: float, turn: float) -> void:
	# A circle on an isometric board is an ellipse on the screen. Generate
	# real pointer events from world-plane points, including at scaled sizes.
	var vector := Vector2.from_angle(from_angle) * radius
	var point: Vector2 = game.camera.unproject_position(Vector3(vector.x, 0.35, vector.y))
	await send_touch(point, true)
	for step: int in range(1, 13):
		vector = Vector2.from_angle(from_angle + turn * float(step) / 12.0) * radius
		var next: Vector2 = game.camera.unproject_position(Vector3(vector.x, 0.35, vector.y))
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.position = root.get_final_transform() * next
		drag.relative = root.get_final_transform().basis_xform(next - point)
		Input.parse_input_event(drag)
		point = next
		await process_frame
	await send_touch(point, false)
	await process_frame


func release_water(game: Node) -> void:
	var source: Vector3 = game.board.to_global(game.board.source_anchor(game.LEVEL.reservoir_id) - Vector3.UP * 0.10)
	var point: Vector2 = game.camera.unproject_position(source)
	await send_touch(point, true)
	await send_touch(point, false)
	for i: int in range(ceil(game.OPEN_SECONDS * 60) + 2): game._physics_process(1.0 / 60.0)
	await process_frame


func steer(game: Node, direction: Vector2) -> void:
	var down_axis: Vector2 = game._rotation_vector(game.hud.field.centre + Vector2(0, 100)).normalized()
	var desired := down_axis.angle() - direction.angle()
	game.hud.field.rotation_changed.emit(wrapf(desired - game.rotation_angle, -PI, PI) / game.controls.sensitivity)


func board_fits(game: Node) -> bool:
	for x: float in [game.LEVEL.board_bounds.position.x, game.LEVEL.board_bounds.end.x]:
		for z: float in [game.LEVEL.board_bounds.position.y, game.LEVEL.board_bounds.end.y]:
			for y: float in [game.LEVEL.base_height - 0.08, game.LEVEL.board_top + 0.12]:
				var point: Vector2 = game.camera.unproject_position(game.pivot.to_global(Vector3(x, y, z)))
				if not root.get_visible_rect().has_point(point): return false
	return true


func check_water_visibility(game: Node) -> void:
	# Compare the same frozen scene with and without water. Limit how much
	# its visible body darkens the floor, while requiring a visible blue flow.
	game.surface.hide()
	for i: int in range(12): await process_frame
	await RenderingServer.frame_post_draw
	var dry := root.get_texture().get_image()
	game.surface.show()
	for i: int in range(12): await process_frame
	await RenderingServer.frame_post_draw
	var wet := root.get_texture().get_image()
	var count := 0
	var darkening := 0.0
	var blue_contrast := 0.0
	for y: int in range(0, wet.get_height(), 2):
		for x: int in range(0, wet.get_width(), 2):
			var bare := dry.get_pixel(x, y)
			var water := wet.get_pixel(x, y)
			var difference := bare.get_luminance() - water.get_luminance()
			if difference < 0.025: continue
			count += 1
			darkening += difference
			blue_contrast += water.b - water.r
	print("Water optical check: samples=", count, "; mean darkening=", darkening / maxf(1, count), "; blue contrast=", blue_contrast / maxf(1, count))
	check(count > 1000 and darkening / maxf(1, count) < 0.10 and blue_contrast / maxf(1, count) > 0.07, "Water remains blue and visible while its average dark footprint stays below ten percent")


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
	await capture("v09-menu")
	var phase: float = game.hud.brand.phase
	await process_frame
	await process_frame
	check(game.hud.brand.phase != phase, "Integrated title remains animated")
	await tap(game.hud.buttons["levels"])
	check(game.screen == game.Screen.LEVELS, "Level navigation opens through touch")
	check(game.hud.buttons["back"].get_global_rect().position.y > 1100, "Menu navigation is in the lower thumb area")
	await tap(game.hud.buttons["level_0"])
	await tap(game.hud.buttons["settings"])
	check(game.screen == game.Screen.SETTINGS, "Settings opens through touch")
	await tap(game.hud.buttons["mode_tilt"])
	check(not game.controls.use_rotation and not game.hud.feedback_toggle.disabled, "Tilt mode enables phone feedback")
	await capture("v09-settings-tilt")
	await tap(game.hud.buttons["mode_rotate"])
	check(game.controls.use_rotation and game.hud.feedback_toggle.disabled, "Rotate replaces touch steering and identifies phone-only feedback")
	var slider: HSlider = game.hud.slider
	var initial: float = slider.value
	var rect := slider.get_global_rect()
	await swipe(rect.get_center(), rect.get_center() + Vector2(140, 0))
	check(not is_equal_approx(slider.value, initial), "Sensitivity responds to a touch drag")
	slider.value = 1.0
	game.hud.sound_toggle.button_pressed = true
	await capture("v09-settings")
	var sensitivity_card: Node = game.hud.slider.find_parent("SensitivityGroup")
	check(sensitivity_card != null and not sensitivity_card.is_ancestor_of(game.hud.buttons["mode_tilt"]), "Sensitivity stays grouped apart from mode selection")
	for label: Label in sensitivity_card.find_children("*", "Label", true, false):
		if label.text == tr("SENSITIVITY"): check(label.get_line_count() == 1, "Russian sensitivity title fits on one line")
	await tap(game.hud.buttons["language_en"])
	check(game.language_code == "en" and "Rotate" in game.hud.buttons["mode_rotate"].text, "English includes the new rotation control")
	await capture("v09-settings-en")
	await tap(game.hud.buttons["language_ru"])
	await swipe(Vector2(400, 980), Vector2(400, 440))
	check(game.hud.settings_scroll.scroll_vertical > 0, "Settings scrolls with a finger while its scrollbar stays hidden")
	check(game.hud.buttons["back"].get_global_rect().position.y > 1100, "Bottom navigation stays fixed during scrolling")
	await capture("v09-settings-bottom")
	await tap(game.hud.buttons["back"])
	await tap(game.hud.buttons["about"])
	check(game.screen == game.Screen.ABOUT, "About screen opens")
	await capture("v09-about")
	await tap(game.hud.buttons["back"])
	await tap(game.hud.buttons["play"])
	check(game.screen == game.Screen.READY and not game.running, "Play starts with enclosed water")
	var held: PackedVector3Array = game.simulation.positions.duplicate()
	await capture("v09-reservoir")
	await send_touch(Vector2(48, 1100), true)
	await send_touch(Vector2(48, 1100), false)
	check(game.screen == game.Screen.READY and not game.hud.buttons.has("release"), "Tapping outside a reservoir does not release water; no global release button remains")
	var fixed_basis: Basis = game.camera.basis
	var fixed_size: float = game.camera.size
	await arc(game, 2.8, 0.0, PI / 2.0)
	check(absf(game.rotation_angle - PI / 2.0) < 0.01, "Clockwise circular drag rotates the board clockwise")
	check(game.camera.basis.is_equal_approx(fixed_basis) and is_equal_approx(game.camera.size, fixed_size), "Clockwise turn preserves camera orientation and scale")
	check(not game.hud.field.is_dragging(), "Lifting a finger ends the gesture without resetting the orientation")
	await capture("v09-clockwise")
	await arc(game, 2.8, 0.0, -PI / 4.0)
	check(absf(game.rotation_angle - PI / 4.0) < 0.01, "Counterclockwise drag rotates the board back")
	check(held == game.simulation.positions and board_fits(game), "Preparation rotates the complete glass volume without releasing water")
	var preserved: float = game.rotation_angle
	await tap(game.hud.buttons["pause"])
	check(game.screen == game.Screen.PAUSED, "Rotation input leaves the pause button usable")
	# Stay outside the modal's buttons: its lower half now overlaps the
	# larger projected circle of the raised camera.
	await swipe(Vector2(48, 180), Vector2(160, 280))
	check(game.screen == game.Screen.PAUSED and is_equal_approx(game.rotation_angle, preserved), "The pause modal blocks board rotation")
	await tap(game.hud.buttons["resume"])
	check(is_equal_approx(game.rotation_angle, preserved), "Continue preserves orientation")
	root.size = Vector2i(450, 1000)
	await process_frame
	await process_frame
	game._physics_process(1.0 / 60.0)
	preserved = game.rotation_angle
	await arc(game, 2.8, -PI / 2.0, PI / 4.0)
	check(absf(wrapf(game.rotation_angle - preserved - PI / 4.0, -PI, PI)) < 0.01, "Rotation tracks touch correctly at a scaled physical resolution")
	check(board_fits(game), "Fixed raised camera preserves every wall at the scaled resolution")
	await capture("v09-rotation-scaled")
	root.size = Vector2i(720, 1600)
	await process_frame
	await process_frame
	game._physics_process(1.0 / 60.0)
	await capture("v09-rotation-tall")
	await release_water(game)
	check(game.running and game.hud.page == null and game.hud.buttons.size() == 1, "Tapping the rotated reservoir opens it and leaves only pause over gameplay")
	check(events.has(&"click") and events.has(&"start"), "Button and individual reservoir-release sounds remain available")
	await tap(game.hud.buttons["pause"])
	await tap(game.hud.buttons["restart"])
	check(game.screen == game.Screen.READY and game.rotation_angle == 0.0, "Restart restores water, lid and board orientation")
	await release_water(game)
	steer(game, Vector2.DOWN)
	for frame: int in range(120): game._physics_process(1.0 / 60.0)
	await capture("v09-flow-close")
	check(game.world_to_input(game.input_to_world(Vector2.DOWN)).distance_to(Vector2.DOWN) < 0.0001, "Gravity stays at the physical bottom of the screen")
	check(game.board.hazard_edges.size() >= 4 and game.board.glass_faces > 20, "Glass has external, inner, top and bottom faces; steps have folded markings")
	await tap(game.hud.buttons["pause"])
	await capture("v09-pause")
	await tap(game.hud.buttons["exit"])
	await tap(game.hud.buttons["settings"])
	await tap(game.hud.buttons["mode_tilt"])
	game.hud.feedback_toggle.button_pressed = true
	await tap(game.hud.buttons["back"])
	await tap(game.hud.buttons["play"])
	Input.set_gravity(Vector3(0, 0, 9.81))
	await release_water(game)
	var angle := deg_to_rad(20.0)
	Input.set_gravity(Vector3(0, -sin(angle), cos(angle)) * 9.81)
	for frame: int in range(90): game._physics_process(1.0 / 60.0)
	check(game.pivot.rotation_degrees.length() > 4.0 and game.pivot.rotation_degrees.length() <= 9.1, "Moderate phone inclination gives visible, bounded feedback")
	check(board_fits(game), "Enhanced phone feedback keeps the full board visible")
	await capture("v09-tilt-feedback")
	await check_water_visibility(game)
	game.controls.use_rotation = true
	game.controls.sensitivity = 1.0
	game._restart()
	await release_water(game)
	var circuit: Array[Vector2] = [Vector2.DOWN, Vector2(1, 0.5), Vector2(0.5, -1), Vector2(-1, -0.5), Vector2(-0.4, 1), Vector2.DOWN]
	var stage := 0
	var saw_finish := false
	for direction: Vector2 in circuit:
		steer(game, direction)
		for frame: int in range(600):
			game._physics_process(1.0 / 60.0)
			if game.screen == game.Screen.FINISHING and not saw_finish:
				saw_finish = true
				check(game.hud.page == null and not game.hud.field.active, "Delivered water stays visible before the result")
				await capture("v09-filled-vessel")
			if frame % 120 == 0: await process_frame
		stage += 1
		await capture("v09-circuit-%d" % stage)
	print("Rotation-controller delivered fraction: ", game.simulation.goal_fraction)
	check(game.simulation.completed and game.screen == game.Screen.WON, "The full circuit completes using rotation with fixed downward gravity")
	check(saw_finish and events.count(&"complete") == 1, "Delivery delay and completion sound occur once")
	await capture("v09-victory")
	if game.hud.buttons.has("win_menu"):
		await tap(game.hud.buttons["win_menu"])
		check(game.screen == game.Screen.MENU, "Victory returns to the menu")
	game.sounds.set_enabled(false)
	game.free()
	await process_frame
	await process_frame
	await create_timer(0.08).timeout
	print("VISUAL RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
