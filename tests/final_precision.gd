extends SceneTree
const LEVEL = preload("res://resources/tenth_level.tres")
const WATER = preload("res://resources/water.tres")

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var level := LEVEL.duplicate() as LevelDefinition
	level.particle_count = 2048
	var samples: Array[Vector2] = []
	for z: int in range(27):
		for x: int in range(36):
			var p := Vector2(-3.4+x*0.038,1.50+z*0.038)
			if is_equal_approx(level.floor_height(p),0.6) and level.contains(p,0.025): samples.append(p)
	var losses: Array[int] = []
	var mass_valid := true
	var careful_total := 0
	for careful: bool in [true,false]:
		var fluid := LiquidSimulation.new(level,WATER)
		fluid.set_source_opening(&"source_10_a",1.0)
		fluid.set_source_opening(&"source_10_b",1.0)
		for i: int in range(2048):
			var p := samples[i%samples.size()]
			fluid.set_particle(i,Vector3(p.x,0.617+(i/samples.size())*0.038,p.y),Vector3.ZERO)
		for target: Vector2 in [Vector2(-2.5,2.7),Vector2(-2.95,3.3),Vector2(-2.55,4.3)]:
			for frame: int in range(600):
				var centre := Vector2.ZERO
				var velocity := Vector2.ZERO
				var n := 0
				for i: int in range(2048):
					if fluid.active[i]==0: continue
					centre+=Vector2(fluid.positions[i].x,fluid.positions[i].z)
					velocity+=Vector2(fluid.velocities[i].x,fluid.velocities[i].z)
					n+=1
				if n==0: break
				var tilt := ((target-centre/n)*1.7-velocity/n*0.7).limit_length(0.13 if careful else 1.0)
				if not careful: tilt = Vector2.DOWN
				fluid.settle(1.0/60.0,tilt)
		losses.append(fluid.lost_in_void)
		mass_valid = mass_valid and fluid.delivered_count+fluid.remaining_count+fluid.lost_count==2048 and fluid.lost_without_rim==0
		if careful: careful_total = fluid.lost_count
		print("CHICANE careful=",careful," well_losses=",fluid.lost_in_void," total_losses=",fluid.lost_count)
	var ok := mass_valid and careful_total<308 and losses[0]<205 and losses[1]>losses[0]+410
	print("FINAL_PRECISION_RESULT failures=",0 if ok else 1)
	quit(0 if ok else 1)
