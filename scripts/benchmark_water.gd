extends SceneTree
## CPU component timings; these are not GPU or physical-phone FPS.
## Run with --headless --script res://scripts/benchmark_water.gd.
const WATER = preload("res://resources/water.tres")


func _initialize() -> void: _run.call_deferred()


func summarize(samples: Array[float]) -> Dictionary:
	samples.sort()
	var total := 0.0
	for value: float in samples: total += value
	return {"mean_ms":total/samples.size(),"median_ms":samples[samples.size()/2],"max_ms":samples[-1]}


func _run() -> void:
	for resource: String in ["first_level","tenth_level"]:
		var begin := Time.get_ticks_usec()
		var fluid := LiquidSimulation.new(load("res://resources/"+resource+".tres"),WATER)
		var solver := fluid.native_solver()
		var configure_ms := (Time.get_ticks_usec()-begin)/1000.0
		solver.call("set_render_axes",Vector3.RIGHT,Vector3(0,0.866,-0.5))
		fluid.set_gate_opening(0.0)
		for stage: int in range(3):
			if stage>0: fluid.set_gate_opening(1.0)
			if stage==2 and resource=="tenth_level": fluid.set_source_opening(&"source_10_b",1.0)
			var physics: Array[float] = []
			var state: Array[float] = []
			var surface: Array[float] = []
			var vertices := 0
			for frame: int in range(60):
				begin = Time.get_ticks_usec()
				solver.call("settle",1.0/60.0,Vector2(0.3,0.5))
				physics.append((Time.get_ticks_usec()-begin)/1000.0)
				begin = Time.get_ticks_usec()
				solver.call("get_state")
				state.append((Time.get_ticks_usec()-begin)/1000.0)
				if frame%10==0:
					begin = Time.get_ticks_usec()
					var mesh_data: Dictionary = solver.call("build_surface")
					vertices = mesh_data.vertices.size()
					surface.append((Time.get_ticks_usec()-begin)/1000.0)
			print("WATER_BENCHMARK ",JSON.stringify({"level":resource,"stage":stage,"configure_ms":configure_ms,"physics":summarize(physics),"state":summarize(state),"mesh":summarize(surface),"vertices":vertices}))
	quit()
