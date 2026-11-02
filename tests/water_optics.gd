extends SceneTree
const LEVEL = preload("res://resources/first_level.tres")
const WATER = preload("res://resources/water.tres")
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, description: String) -> void:
	print("PASS: " if ok else "FAIL: ",description)
	if not ok: failures += 1


func _run() -> void:
	var level := LEVEL.duplicate() as LevelDefinition
	level.particle_count = 768
	var f := LiquidSimulation.new(level,WATER)
	var solver := f.native_solver()
	solver.call("set_render_axes",Vector3.RIGHT,Vector3.BACK)
	for i: int in range(768):
		var p := Vector3(-2.3+(i%8)*0.038,1.2+((i/8)%12)*0.038,-1.8+(i/96)*0.038)
		solver.call("set_particle_state",i,p,Vector3(0.5,0,-1))
	var deep: Dictionary = solver.call("build_surface")
	var expected := 768*pow(WATER.particle_spacing,3)
	check(absf(deep.optical_volume-expected)<expected*0.00001,"Projected optical thickness integrates to the actual liquid volume")
	var deep_peak := 0.0
	var flow_valid := true
	for c: Color in deep.colors:
		deep_peak = maxf(deep_peak,c.r)
		if c.r>0.001: flow_valid = flow_valid and absf(c.g-(0.5+0.25/3.2))<0.0001 and absf(c.b-(0.5-0.5/3.2))<0.0001
	check(flow_valid,"Surface receives the physical velocity of its water, including signed flow direction")
	for i: int in range(768):
		var p := Vector3(-2.5+(i%16)*0.075,1.3,-2.4+(i/16)*0.075)
		solver.call("set_particle_state",i,p,Vector3.ZERO)
	var film: Dictionary = solver.call("build_surface")
	var film_peak := 0.0
	for c: Color in film.colors: film_peak=maxf(film_peak,c.r)
	check(deep_peak>film_peak*4 and film_peak>0,"Equal mass forms a clear thin film or an optically thicker deep pool according to its distribution")
	solver.call("set_render_axes",Vector3(0.8,0,0.6),Vector3(-0.3,0.8660254,0.4))
	var oblique: Dictionary = solver.call("build_surface")
	check(absf(oblique.optical_volume-expected)<expected*0.00001,"Optical volume is conserved when the camera changes angle")
	# Put one genuine spray parcel between reconstruction samples: it has no
	# isosurface support and must still be visible, rather than disappear.
	level = LEVEL.duplicate() as LevelDefinition
	level.particle_count=1
	f = LiquidSimulation.new(level,WATER)
	solver=f.native_solver()
	var drop := Vector3(-3.6+28.5*0.06,-1.4+70.5*0.035,-5.6+68.5*0.06)
	solver.call("set_particle_state",0,drop,Vector3.ZERO)
	var spray: Dictionary = solver.call("build_surface")
	check(spray.vertices.size()==96,"A real unsupported droplet remains visible as a smooth subdivided sphere")
	var drop_volume := 0.0
	var drop_vertices: PackedVector3Array = spray.vertices
	for i: int in range(0,drop_vertices.size(),3):
		drop_volume += (drop_vertices[i]-drop).dot((drop_vertices[i+1]-drop).cross(drop_vertices[i+2]-drop))/6.0
	check(absf(absf(drop_volume)-pow(WATER.particle_spacing,3))<pow(WATER.particle_spacing,3)*0.02,"A detached droplet's drawn volume equals the physical parcel it represents")
	var finite_normals := true
	for n: Vector3 in spray.normals: finite_normals=finite_normals and n.is_finite() and absf(n.length()-1)<0.0001
	check(finite_normals and absf(spray.optical_volume-pow(WATER.particle_spacing,3))<0.00000001,"Droplet normals and represented volume remain valid")
	# Regress the far-face contact that used to eject water through thin
	# transparent banks, even when its height was below the physical rim.
	f = null
	solver = null
	var final_level := (load("res://resources/tenth_level.tres") as LevelDefinition).duplicate() as LevelDefinition
	final_level.particle_count=1
	f = LiquidSimulation.new(final_level,WATER)
	f.set_gate_opening(1.0)
	f.set_particle(0,Vector3(-2.39,0.617,3.1),Vector3.ZERO)
	for frame: int in range(180): f.settle(1.0/60.0,Vector2.RIGHT)
	check(f.lost_count==0 and f.positions[0].x<=-2.38-WATER.particle_radius+0.0001,"The far face of a thin bank cannot pull water through the solid")
	f.reset()
	f.set_gate_opening(1.0)
	f.set_particle(0,Vector3(-2.4,1.35,3.1),Vector3(1.5,0,0))
	for frame: int in range(120): f.settle(1.0/60.0,Vector2.RIGHT)
	check(f.lost_count==1 and f.lost_in_void==1,"Water above the real low bank can still spill into the well behind it")
	f.reset()
	f.set_gate_opening(1.0)
	f.set_particle(0,Vector3(0,-0.123,7.0),Vector3.ZERO)
	for frame: int in range(20): f.settle(1.0/60.0,Vector2.ZERO)
	f.set_source_opening(final_level.collection_source,1.0)
	for frame: int in range(120): f.settle(1.0/60.0,Vector2.UP)
	check(f.lost_count==0 and f.positions[0].z>=6.8+WATER.particle_radius-0.0001,"Opening the collector outlet preserves its physical one-way inlet")
	f = null
	var bend := (load("res://resources/second_level.tres") as LevelDefinition).duplicate() as LevelDefinition
	bend.particle_count=32
	f=LiquidSimulation.new(bend,WATER)
	f.set_gate_opening(1.0)
	for i: int in range(32): f.set_particle(i,Vector3(-2.948,0.157,1.19),Vector3.ZERO)
	for frame: int in range(180): f.settle(1.0/60.0,Vector2.LEFT)
	check(f.lost_count==32 and f.lost_without_rim==0 and f.lost_in_void==0,"Subgrid redistribution across an open low rim records a physical spill, rather than an unexplained leak")
	f=null
	level = LEVEL.duplicate() as LevelDefinition
	level.particle_count=32
	f = LiquidSimulation.new(level,WATER)
	f.set_gate_opening(1.0)
	var centre := Vector3(-1.9,1.5,-1.8)
	for i: int in range(32): f.set_particle(i,centre,Vector3.ZERO)
	f.settle(1.0/60.0,Vector2.ZERO)
	var recovered := {}
	var mean := Vector3.ZERO
	var momentum := Vector3.ZERO
	for i: int in range(32):
		var p := f.positions[i]
		recovered[Vector3i(roundi(p.x*100000),roundi(p.y*100000),roundi(p.z*100000))]=true
		mean += p/32.0
		momentum += f.velocities[i]
	check(recovered.size()>=30,"Overcrowded coincident markers redistribute instead of remaining a zero-volume lump")
	check(absf(mean.x-centre.x)<0.00001 and absf(mean.z-centre.z)<0.00001 and absf(momentum.x)<0.00001 and absf(momentum.z)<0.00001,"Marker redistribution preserves free horizontal centre of mass and adds no horizontal momentum")
	f = null
	final_level = (load("res://resources/tenth_level.tres") as LevelDefinition).duplicate() as LevelDefinition
	final_level.particle_count=1024
	f = LiquidSimulation.new(final_level,WATER)
	f.set_gate_opening(0.0)
	for direction: Vector2 in [Vector2(0.7,0.7),Vector2(-0.7,0.7),Vector2(-0.7,-0.7),Vector2(0.7,-0.7)]:
		for frame: int in range(180): f.settle(1.0/60.0,direction)
	var cells := {}
	var unique := {}
	for p: Vector3 in f.positions:
		var key := Vector3i(floori(p.x/0.07),floori(p.y/0.07),floori(p.z/0.07))
		cells[key]=int(cells.get(key,0))+1
		unique[Vector3i(roundi(p.x*10000),roundi(p.y*10000),roundi(p.z*10000))]=true
	var maximum := 0
	for value: int in cells.values(): maximum=maxi(maximum,value)
	print("HELD_WATER cells=",cells.size()," maximum=",maximum," unique=",unique.size())
	check(f.lost_count==0 and unique.size()>=1014 and maximum<40,"Prolonged inclination of closed tanks retains mass and finite water volume without collapsing parcels onto a corner")
	var held_mesh: Dictionary = f.native_solver().call("build_surface")
	var held_volume := 0.0
	var held_vertices: PackedVector3Array = held_mesh.vertices
	for i: int in range(0,held_vertices.size(),3): held_volume += held_vertices[i].dot(held_vertices[i+1].cross(held_vertices[i+2]))/6.0
	print("HELD_MESH volume=",absf(held_volume)," physical=",f.liquid_volume)
	check(absf(held_volume)>f.liquid_volume*0.6 and absf(held_volume)<f.liquid_volume*1.6,"Long-held water also retains visible geometric volume, rather than only a particle counter")
	print("WATER_OPTICS_RESULT failures=",failures," deep=",deep_peak," film=",film_peak)
	quit(failures)
