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
	sources = [
		{"id": reservoir_id, "bounds": reservoir_bounds, "height": 0.6, "fill": 0.5},
		{"id": &"source_10_b", "bounds": Rect2(0.1, -4.5, 1.2, 1.45), "height": 0.6, "fill": 0.5},
		{"id": collection_source, "bounds": Rect2(-0.7, 6.8, 1.4, 1.6), "height": -0.14, "fill": 0.0}]
	_rect(reservoir_bounds, 0.6)
	_rect(sources[1].bounds, 0.6)
	# Precision branch: a wall opening leaves the main channel floor intact.
	_curve([Vector2(-0.7,-3.05),Vector2(-2.0,-2.35),Vector2(-3.55,-1.3),Vector2(-2.8,-0.1),Vector2(-3.5,1.1),Vector2(-2.9,2.0)], 0.82, 0.6)
	_rect(Rect2(-4.6,0.42,0.83,0.28),0.6)
	_curve([Vector2(-2.9,2.0),Vector2(-2.65,2.35)],0.82,0.6)
	_rect(Rect2(-3.1,2.3,0.9,0.3),0.6)
	_rect(Rect2(-2.92,2.6,0.54,0.95),0.6)
	for x: float in [-3.04,-2.38]:
		var bank := Rect2(x,2.6,0.12,0.95)
		_rect(bank,1.05)
		spill_banks.append(bank)
	for x: float in [-3.6,-2.38]:
		var lip := Rect2(x,2.6,0.68,0.15)
		_rect(lip,1.05)
		spill_banks.append(lip)
		# Close the downstream side of each well. Braking in the catch pool
		# must not drain water backwards through an unguarded hole.
		_rect(Rect2(x,3.4,0.68,0.15),1.05)
	void_regions.append(Rect2(-3.6,2.75,0.56,0.8))
	void_regions.append(Rect2(-2.26,2.75,0.56,0.8))
	# Keep the diagonal ribbon cap beyond the banks; overlapping a lower
	# ribbon here would cut an unintended opening through their geometry.
	_rect(Rect2(-3.3,3.55,1.3,0.55),-0.14)
	_curve([Vector2(-2.65,4.0),Vector2(-3.25,4.6),Vector2(-2.8,5.5),Vector2(-0.4,6.35),Vector2(0,6.95)],1.0,-0.14)
	# A complete winding around the island, followed by a large down/up/down.
	_curve([Vector2(0.7,-3.05),Vector2(0.7,-2.65),Vector2(2.6,-2.65),Vector2(3.85,-1.65),Vector2(4.0,0),Vector2(3.1,1.2),Vector2(1.5,1.2),Vector2(0.7,0.25),Vector2(0.9,-0.85),Vector2(1.8,-1.5)],0.56,0.6)
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
	_rect(Rect2(-0.7,8.4,1.4,1.7),-0.14)
	_rect(Rect2(-2.5,9.55,5.95,1.1),-0.14)
	_curve([Vector2(3.45,10.1),Vector2(3.35,11.7)],1.1,-0.14)
	impact_gate = {"hinge":Vector3(2.0,0.56,10.1),"direction":Vector2.RIGHT,"width":1.1,"height":0.7,"thickness":0.07,"inertia":1.0,"spring":14.0,"damping":3.0,"detent":128.0}
	_rect(Rect2(2.6,11.5,1.5,1.4),-0.14)
	heat_regions.append({"bounds":AABB(Vector3(2.4,-0.16,11.5),Vector3(1.7,1.6,1.4)),"plate_bounds":Rect2(2.6,11.5,1.5,1.4),"temperature":-35.0,"conductance":2500.0})
	ramps.append({"bounds":Rect2(1.0,11.5,1.6,1.4),"axis":Vector2.LEFT,"start_height":-0.14,"end_height":0.56})
	# Only the grate has holes in the required route. Ice bridges its rails.
	# Each transverse rail is lower than the previous one. Ice can bridge
	# the openings and descend without catching a low corner on the next
	# vertical leading face; liquid still falls through the real slots.
	for i: int in range(4): _rect(Rect2(-0.6+i*0.42,11.5,0.14,1.4),0.20+i*0.12)
	for x: float in [-0.46,-0.04,0.38]: void_regions.append(Rect2(x,11.5,0.28,1.4))
	void_regions.append(Rect2(0.8,11.5,0.2,1.4))
	# A safe landing separates the grate from heat. The whole block must be
	# able to arrive before its leading corner begins melting above a hole.
	_rect(Rect2(-3.4,11.3,2.8,2.4),0.14)
	# Even a fast cold block needs about 0.45 s to absorb its latent heat.
	# Give it a long heated run while keeping the familiar heat-transfer
	# rule. The wider outlet lets meltwater leave before it starts boiling.
	_rect(Rect2(-3.4,13.7,2.8,2.4),0.14)
	heat_regions.append({"bounds":AABB(Vector3(-3.4,0.1,13.7),Vector3(2.8,1.6,2.4)),"plate_bounds":Rect2(-3.4,13.7,2.8,2.4),"temperature":200.0,"conductance":4500.0})
	_curve([Vector2(-1.6,14.3),Vector2(-1.6,16.0),Vector2(0.5,16.2),Vector2(1.8,17.3),Vector2(1.8,18.3)],2.0,0.14)
	channel_end_widths[channel_end_widths.size()-1]=1.6
	_rect(goal,-0.14)
	camera_zones = [Rect2(-4.6,-4.7,9.2,11.6),Rect2(-4.3,6.4,8.6,7.0),Rect2(-2.7,11.1,7.2,8.0)]
	route = PackedVector2Array([Vector2(-0.7,-3.7),Vector2(-3.55,-1.3),Vector2(-2.65,3.0),Vector2(0,7.5),Vector2(0.7,-3.7),Vector2(4.15,0),Vector2(1.8,-1.5),Vector2(-0.15,2.7),Vector2(3.7,3.6),Vector2(3.7,6.85),Vector2(0,7.5),Vector2(0,10.1),Vector2(3.35,10.1),Vector2(3.3,12.2),Vector2(-1.6,12.2),Vector2(-1.6,14),Vector2(1.8,17.9)])


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
