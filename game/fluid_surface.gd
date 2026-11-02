class_name FluidSurface
extends MeshInstance3D
## The surface is reconstructed from the same volumetric markers as the fluid.
var _mesh := ArrayMesh.new()
var _ice_mesh := ArrayMesh.new()
var _ice := MeshInstance3D.new()
var _vapor := MultiMeshInstance3D.new()
var _cloud := MultiMesh.new()


func _init(profile: LiquidProfile = null) -> void:
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var water := ShaderMaterial.new()
	water.shader = preload("res://assets/materials/water.gdshader")
	if profile != null: water.set_shader_parameter("water_color", profile.color)
	material_override = water
	_ice.mesh = _ice_mesh
	_ice.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var frost := ShaderMaterial.new()
	frost.shader = preload("res://assets/materials/ice.gdshader")
	_ice.material_override = frost
	add_child(_ice)
	_cloud.transform_format = MultiMesh.TRANSFORM_3D
	_cloud.use_custom_data = true
	var puff := QuadMesh.new()
	puff.size = Vector2.ONE
	_cloud.mesh = puff
	_vapor.multimesh = _cloud
	_vapor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var steam := ShaderMaterial.new()
	steam.shader = preload("res://assets/materials/vapor.gdshader")
	_vapor.material_override = steam
	add_child(_vapor)


func rebuild(_particles: PackedVector3Array, _level: LevelDefinition, _active: PackedByteArray = PackedByteArray(), solver: RefCounted = null) -> void:
	assert(solver != null)
	_fill_mesh(_mesh, solver.call("build_surface"))
	_ice.hide()
	_vapor.hide()
	if _level.heat_regions.is_empty() and _level.initial_phase == 0: return
	var state: Dictionary = solver.call("get_state")
	if state.ice_count > 0:
		_fill_mesh(_ice_mesh, solver.call("build_ice_surface"))
		_ice.show()
	if state.vapor_count > 0:
		if _cloud.instance_count != _particles.size(): _cloud.instance_count = _particles.size()
		var visible_puffs := 0
		for i: int in range(_particles.size()):
			if (i < _active.size() and _active[i] == 0) or state.phases[i] != 2 or i % 2 != 0: continue
			var p := _particles[i]
			var rise := clampf((p.y - 0.3) / (_level.board_top + 0.8), 0, 1)
			var size := 0.20 + rise * 0.24
			_cloud.set_instance_transform(visible_puffs, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), p))
			_cloud.set_instance_custom_data(visible_puffs, Color(0.34 * (1.0 - rise * 0.60), 0, 0, 1))
			visible_puffs += 1
		_cloud.visible_instance_count = visible_puffs
		_vapor.show()


func _fill_mesh(target: ArrayMesh, data: Dictionary) -> void:
	target.clear_surfaces()
	var vertices: PackedVector3Array = data.vertices
	if vertices.is_empty(): return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = data.normals
	arrays[Mesh.ARRAY_COLOR] = data.colors
	target.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
