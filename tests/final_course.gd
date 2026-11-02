extends SceneTree
## End-to-end steering of the original parcels, without moving or replacing
## particles. Also usable as a deterministic course replay for render review.
const LEVEL = preload("res://resources/tenth_level.tres")
const WATER = preload("res://resources/water.tres")
var fluid: LiquidSimulation
var failures: int = 0
var _bank_open: bool = false
var _waypoint_index: int = 0
var _crossing_grate: bool = false
var _filling_cold: bool = false
var _peak_impact: float = 0.0
var _followed_ids: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, description: String) -> void:
	print("PASS: " if ok else "FAIL: ",description)
	if not ok: failures += 1


func steer(target: Vector2, begin: int, end: int, seconds: float = 7.0, strength: float = 0.45) -> void:
	var reached := 0
	for frame: int in range(int(seconds*60)):
		if frame>0 and frame%180==0: print("STEERING ",target," frame=",frame," ice=",fluid.ice_count," bodies=",fluid.ice_body_count," gate=",fluid.impact_angle)
		var centre := Vector2.ZERO
		var velocity := Vector2.ZERO
		var amount := 0
		for i: int in range(begin,end):
			if fluid.active[i] == 0: continue
			if not _followed_ids.is_empty() and not _followed_ids.has(i): continue
			var p := fluid.positions[i]
			# Once the collector is released, observe its downstream room.
			# Averaging an abandoned upstream puddle with the active stream
			# makes the controller brake on the heater or miss the last turn.
			if _bank_open and p.z < (LEVEL.sources[2].bounds as Rect2).position.y: continue
			if _filling_cold and (fluid.phases[i]==1 or Rect2(2.4,11.5,1.7,1.4).has_point(Vector2(p.x,p.z))): continue
			if _crossing_grate:
				if fluid.phases[i]!=1 or p.x < -0.6 or p.z<11.0 or p.z>13.7: continue
			if not fluid.level.sources.is_empty() and fluid.source_fill.get(LEVEL.collection_source,0)>0 and fluid.level.sources[2].bounds.has_point(Vector2(p.x,p.z)) and not _bank_open: continue
			if LEVEL.goal.has_point(Vector2(p.x,p.z)): continue
			centre += Vector2(p.x,p.z)
			velocity += Vector2(fluid.velocities[i].x,fluid.velocities[i].z)
			amount += 1
		if amount == 0: return
		centre /= amount
		velocity /= amount
		var error := target-centre
		var feed := Vector2.ZERO
		for ramp: Dictionary in LEVEL.ramps:
			if (ramp.bounds as Rect2).has_point(centre):
				var r: Rect2 = ramp.bounds
				var axis: Vector2 = ramp.axis
				feed = axis * (float(ramp.end_height)-float(ramp.start_height))/(absf(axis.x*r.size.x)+absf(axis.y*r.size.y))/0.6
		var tilt := (error*1.7-velocity*0.70+feed).limit_length(strength)
		fluid.settle(1.0/60.0,tilt)
		_peak_impact=maxf(_peak_impact,fluid.impact_load)
		if error.length()<0.20 and velocity.length()<0.30: reached += 1
		else: reached = 0
		if reached>20: break
	print("WAYPOINT ",target," lost=",fluid.lost_count," void=",fluid.lost_in_void," leak=",fluid.lost_without_rim," bank=",fluid.source_fill.get(LEVEL.collection_source,0)," delivered=",fluid.delivered_count," ice=",fluid.ice_count," gate=",fluid.impact_angle)
	var directory := "res://build/final-checkpoints-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(directory+"/%02d.bin" % _waypoint_index,FileAccess.WRITE)
	file.store_var(fluid.native_solver().call("get_state"))
	_waypoint_index += 1


func _run() -> void:
	fluid = LiquidSimulation.new(LEVEL,WATER)
	check(fluid.positions.size()==4096 and fluid.source_fill[&"source_10_a"]==2048 and fluid.source_fill[&"source_10_b"]==2048,"The divided source contains the original mass in two equal compartments")
	check(LEVEL.safe_goal and LEVEL.heat_regions.size()==2 and not LEVEL.impact_gate.is_empty(),"Final course has the protected water goal, cold and hot plates and a momentum gate")
	check(LEVEL.floor_height(Vector2(-2.65,3.0))<0.61 and is_inf(LEVEL.floor_height(Vector2(-3.2,3.0))),"Bottleneck floor is continuous; spill wells lie behind low side banks")
	check(is_equal_approx(LEVEL.floor_height(Vector2(-4.1,0.55)),0.6),"The S-bend opening is in the outside wall and has a supporting sill")
	check(LEVEL.floor_height(Vector2(0.4,11.7)) == -INF,"Grate has physical openings for liquid to fall through")
	fluid.set_gate_opening(0.0)
	for frame: int in range(120): fluid.settle(1.0/60.0,Vector2(0.8,0.6))
	check(fluid.lost_count==0 and fluid.source_fill[&"source_10_a"]==2048 and fluid.source_fill[&"source_10_b"]==2048,"Both closed compartments retain their water under strong inclination")
	fluid.reset()
	if "--mechanisms" in OS.get_cmdline_user_args():
		fluid.set_source_opening(&"source_10_a",1.0)
		fluid.set_source_opening(&"source_10_b",1.0)
		var solver := fluid.native_solver()
		for i: int in range(4096):
			solver.call("set_particle_state",i,Vector3(-0.62+(i%32)*0.038,-0.12+((i/32)%4)*0.038,6.9+(i/128)*0.038),Vector3.ZERO)
		for frame: int in range(30): fluid.settle(1.0/60.0,Vector2.ZERO)
		print("MECHANISM_FIXTURE starting bank=",fluid.source_fill[LEVEL.collection_source])
		_downstream()
		return
	fluid.set_source_opening(&"source_10_a",1.0)
	for target: Vector2 in [Vector2(-0.7,-2.85),Vector2(-2,-2.35),Vector2(-3.55,-1.3),Vector2(-2.8,-0.1),Vector2(-3.5,1.1),Vector2(-2.9,2.0),Vector2(-2.65,2.25)]: steer(target,0,2048,10.0,0.23)
	for target: Vector2 in [Vector2(-2.65,2.65),Vector2(-2.65,3.5),Vector2(-2.65,3.8)]: steer(target,0,2048,12.0,0.13)
	for target: Vector2 in [Vector2(-3.25,4.6),Vector2(-2.8,5.5),Vector2(-0.4,6.35),Vector2(0,7.5)]: steer(target,0,2048,10.0,0.3)
	check(fluid.source_fill[&"source_10_b"]==2048,"Opening and steering the first half keeps the second compartment sealed")
	check(fluid.source_fill[LEVEL.collection_source]>=1639 and fluid.delivered_count==0,"At least eighty percent of the first half reaches the collector before switching branches; its tail may keep arriving")
	if "--precision" in OS.get_cmdline_user_args():
		quit(failures)
		return
	fluid.set_source_opening(&"source_10_b",1.0)
	for target: Vector2 in [Vector2(0.7,-2.65),Vector2(2.6,-2.65),Vector2(3.85,-1.65),Vector2(4.0,0),Vector2(3.1,1.2),Vector2(1.5,1.2),Vector2(0.7,0.25),Vector2(0.9,-0.85),Vector2(1.8,-1.5),Vector2(-0.15,-1.5),Vector2(-0.15,1.8),Vector2(-0.15,2.8),Vector2(-0.15,3.65),Vector2(3.7,3.65)]: steer(target,2048,4096)
	# Hold beyond the crest until the back of the stream has climbed too.
	# Braking at the centre of a full landing leaves the rear on the slope;
	# the following lateral turn then cannot supply its uphill acceleration.
	steer(Vector2(3.7,7.6),2048,4096,14.0,1.0)
	for frame: int in range(480): fluid.settle(1.0/60.0,Vector2.DOWN)
	for target: Vector2 in [Vector2(2.35,6.85),Vector2(1.5,6.4),Vector2(0,7.5)]: steer(target,2048,4096)
	# A long curved stream can have its front safely stored while its tail
	# is still in the spiral. Follow that real remaining portion again;
	# the collector is deliberately protected so the first arrival stays.
	for attempt: int in range(2):
		if fluid.source_fill[LEVEL.collection_source]>=3686: break
		_return_branch_tail()
	check(fluid.source_fill[LEVEL.collection_source]>=3686,"Both branches can supply at least ninety percent to the common collector")
	print("BRANCH_REPLAY_COMPLETE lost=",fluid.lost_count," bank=",fluid.source_fill[LEVEL.collection_source])
	if "--branches" in OS.get_cmdline_user_args():
		quit(failures)
		return
	_downstream()


func _return_branch_tail() -> void:
	# Like a player following the largest remaining pool, observe one
	# connected portion at a time. All original parcels still receive the
	# same global gravity; feedback must not average two different rooms.
	_followed_ids = _largest_unstored_pool(2048,4096)
	print("FOLLOWING_POOL parcels=",_followed_ids.size())
	for target: Vector2 in [Vector2(1.5,1.2),Vector2(0.7,0.25),Vector2(0.9,-0.85),Vector2(1.8,-1.5),Vector2(-0.15,-1.5),Vector2(-0.15,1.8),Vector2(-0.15,2.8),Vector2(-0.15,3.65),Vector2(3.7,3.65)]: steer(target,2048,4096)
	steer(Vector2(3.7,7.6),2048,4096,14.0,1.0)
	for frame: int in range(480): fluid.settle(1.0/60.0,Vector2.DOWN)
	for target: Vector2 in [Vector2(2.35,6.85),Vector2(1.5,6.4),Vector2(0,7.5)]: steer(target,2048,4096)
	_followed_ids.clear()


func _largest_unstored_pool(begin: int, end: int) -> Dictionary:
	var bins := {}
	var vessel: Rect2 = LEVEL.sources[2].bounds
	for i: int in range(begin,end):
		if not fluid.active[i]: continue
		var p := fluid.positions[i]
		if vessel.has_point(Vector2(p.x,p.z)): continue
		var cell := Vector2i(floori(p.x/0.25),floori(p.z/0.25))
		if not bins.has(cell): bins[cell]=[]
		bins[cell].append(i)
	var visited := {}
	var largest := {}
	for seed: Vector2i in bins:
		if visited.has(seed): continue
		var pool := {}
		var queue: Array[Vector2i] = [seed]
		visited[seed]=true
		while not queue.is_empty():
			var cell: Vector2i = queue.pop_back()
			for i: int in bins[cell]: pool[i]=true
			for x: int in range(-1,2):
				for z: int in range(-1,2):
					var neighbour := cell+Vector2i(x,z)
					if bins.has(neighbour) and not visited.has(neighbour):
						visited[neighbour]=true
						queue.append(neighbour)
		if pool.size()>largest.size(): largest=pool
	return largest


func _downstream() -> void:
	fluid.set_source_opening(LEVEL.collection_source,1.0)
	_bank_open = true
	steer(Vector2(0,10.1),0,4096,12,0.15)
	for frame: int in range(300): fluid.settle(1.0/60.0,Vector2.DOWN*0.45)
	steer(Vector2(1.3,10.1),0,4096,6,0.10)
	check(not fluid.impact_latched,"A slow collected stream cannot open the impact gate")
	print("WEAK_PEAK ",_peak_impact)
	_peak_impact=0
	# Gather against the actual end of the run, then reverse into the leaf.
	# Stopping a centre-of-mass controller at an arbitrary point leaves the
	# water spread along the whole channel and is not a strong water impact.
	for frame: int in range(240):
		fluid.settle(1.0/60.0,Vector2(-1,0.35).normalized())
		_peak_impact=maxf(_peak_impact,fluid.impact_load)
	for frame: int in range(480):
		fluid.settle(1.0/60.0,Vector2(1,0.35).normalized())
		_peak_impact=maxf(_peak_impact,fluid.impact_load)
	print("IMPACT_PULSE latched=",fluid.impact_latched," peak=",_peak_impact," ice=",fluid.ice_count)
	check(fluid.impact_latched,"A collected strong stream opens and latches the impact gate")
	if "--impact" in OS.get_cmdline_user_args() or not fluid.impact_latched:
		quit(failures)
		return
	_filling_cold=true
	steer(Vector2(3.35,12.2),0,4096,16,0.5)
	_filling_cold=false
	for frame: int in range(900):
		fluid.settle(1.0/60.0,Vector2(0.2,0.2))
		if fluid.ice_count>=int(4096*0.96): break
	check(fluid.ice_count>=int(4096*0.9),"The cooling form freezes the supplied water before the grate")
	_crossing_grate=true
	steer(Vector2(-1.8,12.2),0,4096,18,1.0)
	_crossing_grate=false
	steer(Vector2(-1.6,12.2),0,4096,8,0.45)
	check(fluid.lost_count<=int(4096*0.1),"Solid water bridges the grate with at least ninety percent remaining")
	# Keep driving until the whole stream is beyond the hot plate. Braking
	# at its outlet holds the back of a long stream on heat; turning back
	# towards the centreline can then send that tail over the heater again.
	for target: Vector2 in [Vector2(-1.6,17.6),Vector2(0.5,17.0),Vector2(1.8,17.3),Vector2(1.8,17.9)]: steer(target,0,4096,7,1.0)
	for frame: int in range(90): fluid.settle(1.0/60.0,Vector2.DOWN*0.2)
	check(fluid.completed and fluid.goal_fraction>=0.9,"The uninterrupted final course delivers at least ninety percent of the original water")
	check(fluid.delivered_count+fluid.remaining_count+fluid.lost_count==4096,"Final course accounts for every original parcel")
	print("FINAL_COURSE_COMPLETE failures=",failures," delivered=",fluid.delivered_count," lost=",fluid.lost_count)
	quit(failures)
