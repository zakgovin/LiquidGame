extends SceneTree
const LEVELS = preload("res://game/main.gd").LEVELS
const WATER = preload("res://resources/water.tres")
var failures := 0
var samples := 0


func _initialize() -> void: _run.call_deferred()


func _run() -> void:
	for original: LevelDefinition in LEVELS:
		var level := original.duplicate() as LevelDefinition
		level.particle_count = 1
		var fluid := LiquidSimulation.new(level,WATER)
		var native := fluid.native_solver()
		var points: Array[Vector2] = []
		var bounds := level.board_bounds
		for z: int in range(43):
			for x: int in range(27):
				points.append(bounds.position+Vector2((x+0.37)/27.0,(z+0.41)/43.0)*bounds.size)
		# Exercise exact bin seams and both sides of the epsilon used at
		# real floor edges. The GDScript terrain is the independent reference.
		for rect: Rect2 in level.floor_regions:
			for x: float in [rect.position.x,rect.end.x]:
				for z: float in [rect.position.y,rect.end.y]:
					for offset: Vector2 in [Vector2.ZERO,Vector2(0.00002,0.00002),Vector2(-0.00002,-0.00002)]:
						points.append(Vector2(x,z)+offset)
		for x: int in range(ceili(bounds.size.x/0.28)):
			points.append(bounds.position+Vector2(x*0.28,bounds.size.y*0.51))
		var mismatches := 0
		for p: Vector2 in points:
			var expected := level.floor_height(p)
			var actual: float = native.call("sample_floor",p)
			if (is_inf(expected) and not is_inf(actual)) or (not is_inf(expected) and (not is_finite(actual) or absf(expected-actual)>0.00003)):
				mismatches += 1
				if mismatches<4: print("MISMATCH ",original.title," ",p," expected=",expected," actual=",actual)
		failures += mismatches
		samples += points.size()
		print("PASS: " if mismatches==0 else "FAIL: ",original.title," exact terrain samples=",points.size()," mismatches=",mismatches)
	print("GEOMETRY_INDEX_RESULT samples=",samples," failures=",failures)
	quit(1 if failures else 0)
