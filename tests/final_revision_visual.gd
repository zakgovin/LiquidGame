extends SceneTree

func _initialize() -> void:
	_run.call_deferred()


func capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/"+path+".png")


func _run() -> void:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game._select_level(9)
	game._start()
	game._physics_process(0.0)
	await capture("v016-final-ready")
	game._toggle_collector_camera()
	game._update_course_camera(0.0)
	await capture("v016-collector-camera")
	game.camera.position=Vector3(0,50,7)
	game.camera.look_at(Vector3(0,0,7),Vector3.FORWARD)
	game.camera.size=13.8
	game.camera.v_offset=0
	game.hud.hide()
	await capture("v016-final-map")
	game.hud.show()
	game._about()
	await capture("v016-about")
	game.free()
	await process_frame
	print("FINAL_REVISION_VISUAL_RESULT complete")
	quit()
