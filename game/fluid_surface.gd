class_name FluidSurface
extends MeshInstance3D
## The surface is reconstructed from the same volumetric markers as the fluid.
var _mesh := ArrayMesh.new()


func _init(profile: LiquidProfile = null) -> void:
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var water := ShaderMaterial.new()
	water.shader = preload("res://assets/materials/water.gdshader")
	if profile != null: water.set_shader_parameter("water_color", profile.color)
	material_override = water


func rebuild(_particles: PackedVector3Array, _level: LevelDefinition, _active: PackedByteArray = PackedByteArray(), solver: RefCounted = null) -> void:
	assert(solver != null)
	var data: Dictionary = solver.call("build_surface")
	_mesh.clear_surfaces()
	var vertices: PackedVector3Array = data.vertices
	if vertices.is_empty(): return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = data.normals
	arrays[Mesh.ARRAY_COLOR] = data.colors
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
