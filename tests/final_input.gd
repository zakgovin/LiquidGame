extends SceneTree
var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, description: String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ",description)
	if not ok: failures += 1


func tap_source(game: Node, id: StringName) -> void:
	var point: Vector2 = game.camera.unproject_position(game.board.to_global(game.board.source_anchor(id)))
	game._tap_field(point)


func _run() -> void:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	await process_frame
	game._select_level(9)
	game._levels()
	check(game.hud.buttons.has("level_9") and game.LEVELS.size()==10,"The final level is selectable as the tenth course")
	game._start()
	var room_visible := true
	var room: Rect2 = game.level.camera_zones[0]
	for x: float in [room.position.x,room.end.x]:
		for z: float in [room.position.y,room.end.y]:
			room_visible = room_visible and root.get_visible_rect().has_point(game.camera.unproject_position(game.pivot.to_global(Vector3(x,1.55,z))))
	check(room_visible,"The ready camera shows both initial branches without clipping their outside bends")
	check(game.board.source_targets.size()==3 and game.board.source_lids.size()==3,"Both initial lids and the collector have separate touch targets and hardware")
	Input.set_gravity(Vector3(0,0,9.81))
	tap_source(game,&"source_10_b")
	check(game._opened_sources.has(&"source_10_b") and not game._opened_sources.has(&"source_10_a"),"Tapping the right compartment opens only that compartment")
	for frame: int in range(44): game._physics_process(1.0/60.0)
	check(not game.opening and game.hud.field.active,"Tilt gameplay continues accepting taps on remaining reservoirs")
	var calibration: Vector2 = game.controls.neutral
	Input.set_gravity(Vector3(0.3,0,0.9539392)*9.81)
	tap_source(game,&"source_10_a")
	check(game.opening and game.controls.neutral==calibration,"Opening the second half preserves the initial phone calibration")
	for frame: int in range(44): game._physics_process(1.0/60.0)
	tap_source(game,game.level.collection_source)
	check(not game._opened_sources.has(game.level.collection_source),"An empty collector stays locked until both portions supply enough water")
	# An isolated full-vessel fixture checks the tap and scoring rule. The
	# separate final_course test follows every original parcel end to end.
	var solver: RefCounted = game.simulation.native_solver()
	for i: int in range(game.level.particle_count):
		var p := Vector3(-0.62+(i%32)*0.038,-0.12+((i/32)%4)*0.038,6.9+(i/128)*0.038)
		solver.call("set_particle_state",i,p,Vector3.ZERO)
	game.simulation.step(0.0,Vector2.ZERO)
	check(game.simulation.source_fill[game.level.collection_source]==4096 and game.simulation.delivered_count==0 and not game.simulation.completed,"A full intermediate collector is visible water and never a victory")
	game._focus_rect=Rect2()
	game._update_course_camera(0)
	tap_source(game,game.level.collection_source)
	check(game._opened_sources.has(game.level.collection_source) and game.controls.neutral==calibration,"Tapping the full collector releases the same water without recalibration")
	var elapsed: float = game.simulation.elapsed_seconds
	game._pause()
	for frame: int in range(60): game._physics_process(1.0/60.0)
	check(game.simulation.elapsed_seconds==elapsed and game.opening,"Pause freezes the collector lid, heat and optical wave time together")
	game._resume()
	for frame: int in range(44): game._physics_process(1.0/60.0)
	check(not game.opening and game.screen==game.Screen.PLAYING,"Resume completes the pending collector opening")
	game.controls.use_rotation=true
	game.pivot.rotation=Vector3.ZERO
	game._focus_rect=Rect2(-0.9,13.8,5.4,8.0)
	game._focus_tick=1
	var stable_projection := true
	for angle: float in [0.0,PI*0.5,PI,-PI*0.5]:
		game.turntable.rotation.y=angle
		game._update_course_camera(0)
		var centre: Vector3 = game.pivot.to_global(game._focus_center)
		var a: Vector2 = game._rotation_vector(game.camera.unproject_position(centre+Vector3.RIGHT*1.3))
		var b: Vector2 = game._rotation_vector(game.camera.unproject_position(centre+Vector3.BACK*1.3))
		stable_projection = stable_projection and absf(a.angle_to(b)-PI*0.5)<0.0001
	check(stable_projection,"Rotation gestures retain their world-plane angle after the camera follows distant rooms")
	game._restart()
	check(game._opened_sources.is_empty() and game.simulation.source_fill[&"source_10_a"]==2048 and game.simulation.source_fill[&"source_10_b"]==2048 and game.simulation.source_fill[game.level.collection_source]==0,"Restart restores both halves, the empty collector and all three closed lids")
	game._next_level()
	check(game.level_index==9,"The final course has no unavailable next level")
	Input.set_gravity(Vector3.ZERO)
	game.free()
	await process_frame
	print("FINAL_INPUT_RESULT checks=",checks," failures=",failures)
	quit(failures)
