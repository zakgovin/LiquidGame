extends LevelDefinition
## One continuous course. Every channel and mechanism uses the same terrain
## for drawing, collisions and water; there are no scene or particle transfers.


func _init() -> void:
	title = "LEVEL_FULL_CYCLE"
	description = "FULL_CYCLE_ROUTE"
	reservoir_id = &"source_10_a"
	collection_source = &"source_10_bank"
	particle_count = 4096
	board_bounds = Rect2(-4.6, -4.8, 9.2, 24.0)
	board_top = 1.55
	base_height = -1.40
	camera_elevation = 73.0
	reservoir_bounds = Rect2(-1.3, -4.5, 1.2, 1.45)
	spawn = reservoir_bounds.grow(-0.1)
	goal = Rect2(1.0, 17.0, 1.6, 1.8)
	safe_goal = true
	goal_entry_direction = Vector2.RIGHT
	sources = [
		{"id": reservoir_id, "bounds": reservoir_bounds, "height": 0.6, "fill": 0.5},
		{"id": &"source_10_b", "bounds": Rect2(0.1, -4.5, 1.2, 1.45), "height": 0.6, "fill": 0.5},
		{"id": collection_source, "bounds": Rect2(-0.7, 6.8, 1.4, 1.6), "height": -0.14, "fill": 0.0}]
	_rect(reservoir_bounds, 0.6)
	_rect(sources[1].bounds, 0.6)
	# Precision branch: a wall opening leaves the main channel floor intact.
	# Full-width, gently tapered mouths avoid solid shoulders at the lids.
	_rect(Rect2(-1.3,-3.15,1.2,0.6),0.6)
	_curve([Vector2(-0.7,-3.15),Vector2(-0.7,-2.7),Vector2(-1.4,-2.35),Vector2(-2.0,-2.35)],1.2,0.6)
	channel_end_widths[-1] = 0.82
	_curve([Vector2(-2.0,-2.35),Vector2(-3.55,-1.3),Vector2(-2.8,-0.1),Vector2(-3.5,1.1),Vector2(-2.95,2.2)],0.82,0.6)
	_rect(Rect2(-4.6,0.42,1.25,0.38),0.6)
	_rect(Rect2(-3.4,1.85,1.3,0.7),0.6)
	# Two opposed turns require braking, rather than one hard downhill tilt.
	# A raised outer ribbon is the real low bank; the surrounding wells do
	# not cut the supported channel or its banks (terrain takes the minimum).
	var chicane: Array[Vector2] = [Vector2(-2.95,2.2),Vector2(-2.5,2.7),Vector2(-2.95,3.3),Vector2(-2.55,4.05)]
	_curve(chicane,0.56,0.74)
	_curve(chicane,0.32,0.6)
	spill_banks.append(Rect2(-3.4,2.5,1.4,1.25))
	for lip: Rect2 in [Rect2(-3.9,2.55,1.11,0.12),Rect2(-2.21,2.55,0.61,0.12)]:
		_rect(lip,0.74)
		spill_banks.append(lip)
	obstacles.append(AABB(Vector3(-2.77,0.78,2.64),Vector3(0.54,0.77,0.16)))
	void_regions.append(Rect2(-3.9,2.55,2.3,1.2))
	_rect(Rect2(-3.3,4.05,1.3,0.35),-0.14)
	_curve([Vector2(-2.55,4.15),Vector2(-3.25,4.6),Vector2(-2.8,5.5),Vector2(-0.4,6.35),Vector2(0,6.95)],1.0,-0.14)
	# A complete winding around the island, followed by a large down/up/down.
	_rect(Rect2(0.1,-3.15,1.2,0.6),0.6)
	_curve([Vector2(0.7,-3.15),Vector2(0.7,-2.65),Vector2(2.6,-2.65)],1.2,0.6)
	channel_end_widths[-1] = 0.56
	_curve([Vector2(2.6,-2.65),Vector2(3.85,-1.65),Vector2(4.0,0),Vector2(3.1,1.2),Vector2(1.5,1.2),Vector2(0.7,0.25),Vector2(0.9,-0.85),Vector2(1.8,-1.5)],0.56,0.6)
	# This straight return fits between the two spiral arms, without crossing.
	_rect(Rect2(-0.43,-1.78,2.23,0.56),0.6)
	_rect(Rect2(-0.43,-1.5,0.56,3.55),0.6)
	_rect(Rect2(-0.43,2.05,0.56,1.2),-0.9)
	_rect(Rect2(-0.43,3.25,4.58,0.85),-0.9)
	ramps.append({"bounds":Rect2(3.3,4.1,0.85,2.5),"axis":Vector2.DOWN,"start_height":-0.9,"end_height":0.35})
	_rect(Rect2(2.2,6.6,1.95,0.5),0.35)
	_curve([Vector2(2.35,6.85),Vector2(1.5,6.4),Vector2(0,6.95)],0.9,-0.14)
	_rect(sources[2].bounds,-0.14)
	# The common bank keeps the first portion while the second is being guided.
	# A direct feeder lets the entire collected portion reach the impact
	# run before its front freezes. A second parallel hairpin here stranded
	# the tail behind a wall while the leading ice needed opposite steering.
	_rect(Rect2(-0.7,8.4,1.4,0.4),-0.14)
	_rect(Rect2(-0.7,8.8,1.4,1.3),-0.64)
	_rect(Rect2(-2.5,9.55,5.95,1.1),-0.64)
	_curve([Vector2(3.45,10.1),Vector2(3.35,11.7)],1.1,-0.64)
	impact_gate = {"hinge":Vector3(2.0,0.06,10.1),"direction":Vector2.RIGHT,"width":1.1,"height":0.7,"thickness":0.07,"inertia":1.0,"spring":14.0,"damping":3.0,"detent":128.0}
	_rect(Rect2(2.6,11.5,1.5,1.4),-0.64)
	heat_regions.append({"bounds":AABB(Vector3(2.4,-0.66,11.5),Vector3(1.7,1.6,1.4)),"plate_bounds":Rect2(2.6,11.5,1.5,1.4),"temperature":-35.0,"conductance":2500.0})
	ramps.append({"bounds":Rect2(1.0,11.5,1.6,1.4),"axis":Vector2.LEFT,"start_height":-0.64,"end_height":0.06})
	# Only the grate has holes in the required route. Ice bridges its rails.
	# Each transverse rail is lower than the previous one. Ice can bridge
	# the openings and descend without catching a low corner on the next
	# vertical leading face; liquid still falls through the real slots.
	for i: int in range(4): _rect(Rect2(-0.6+i*0.42,11.5,0.14,1.4),-0.30+i*0.12)
	for x: float in [-0.46,-0.04,0.38]: void_regions.append(Rect2(x,11.5,0.28,1.4))
	void_regions.append(Rect2(0.8,11.5,0.2,1.4))
	# A safe landing separates the grate from heat. The whole block must be
	# able to arrive before its leading corner begins melting above a hole.
	_rect(Rect2(-3.4,11.3,2.8,2.4),-0.36)
	_rect(Rect2(-3.7,13.7,3.1,0.4),-0.36)
	# The unheated landing and a second perpendicular grate give time to
	# handle the ice before heat. Reuse the board's free lower-left area.
	for i: int in range(4): _rect(Rect2(-3.7,14.1+i*0.42,3.1,0.14),-0.36-i*0.14)
	for z: float in [14.24,14.66,15.08]: void_regions.append(Rect2(-3.7,z,3.1,0.28))
	_rect(Rect2(-3.7,15.5,3.1,2.8),-0.9)
	# Even a fast cold block needs about 0.45 s to absorb its latent heat.
	# Give it a long heated run while keeping the familiar heat-transfer
	# rule. The wider outlet lets meltwater leave before it starts boiling.
	_rect(Rect2(-1.7,15.8,2.4,2.6),-0.9)
	heat_regions.append({"bounds":AABB(Vector3(-1.7,-0.94,15.8),Vector3(2.4,1.6,2.6)),"plate_bounds":Rect2(-1.7,15.8,2.4,2.6),"temperature":200.0,"conductance":4500.0})
	# Match the whole heated edge with an unheated receiver apron. A narrow
	# corner here traps the trailing meltwater on heat while the front turns.
	_rect(Rect2(0.7,15.8,2.1,2.6),-0.9)
	_curve([Vector2(0.6,17.0),Vector2(1.3,16.8),Vector2(2.0,17.4),Vector2(1.8,18.0)],1.6,-0.9)
	_rect(goal,-0.9)
	camera_zones = [Rect2(-4.6,-4.7,9.2,11.6),Rect2(-4.3,6.4,8.6,7.0),Rect2(-4.3,11.1,8.8,8.0)]
	route = PackedVector2Array([Vector2(-0.7,-3.7),Vector2(-3.55,-1.3),Vector2(-2.5,2.7),Vector2(-2.95,3.3),Vector2(0,7.5),Vector2(0.7,-3.7),Vector2(4.0,0),Vector2(1.8,-1.5),Vector2(-0.15,2.7),Vector2(3.7,3.6),Vector2(3.7,6.85),Vector2(0,7.5),Vector2(0,10.1),Vector2(3.35,10.1),Vector2(3.3,12.2),Vector2(-2.7,12.2),Vector2(-2.7,16.85),Vector2(1.8,17.9)])


func _rect(rect: Rect2, height: float) -> void:
	floor_regions.append(rect)
	floor_elevations.append(height)


func _curve(points: Array[Vector2], width: float, height: float) -> void:
	var curve := Curve2D.new()
	curve.bake_interval = 0.08
	for i: int in range(points.size()):
		var tangent := (points[mini(i+1,points.size()-1)]-points[maxi(i-1,0)]) / 6.0
		curve.add_point(points[i],-tangent if i>0 else Vector2.ZERO,tangent if i+1<points.size() else Vector2.ZERO)
	channel_curves.append(curve)
	channel_widths.append(width)
	channel_end_widths.append(width)
	channel_elevations.append(height)
