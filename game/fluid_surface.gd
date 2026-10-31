class_name FluidSurface
extends MeshInstance3D
## Genuine volumetric surface: sparse active cells in a 3D scalar field,
## marching tetrahedra and smooth density-gradient normals. No fixed water plane.

const CELL: float = 0.075
const ORIGIN := Vector3(-3.6, -1.5, -5.5)
const NX: int = 98
const NZ: int = 148
const NY: int = 56
const SLICE: int = NX * NZ
const COUNT: int = SLICE * NY
const ISO: float = 0.65
const RADIUS: float = 0.18
const CORNERS := [0, 1, NX + 1, NX, SLICE, SLICE + 1, SLICE + NX + 1, SLICE + NX]
const CELL_OFFSETS := [0, -1, -NX, -NX - 1, -SLICE, -SLICE - 1, -SLICE - NX, -SLICE - NX - 1]
const TETS := [[0, 5, 1, 6], [0, 1, 2, 6], [0, 2, 3, 6], [0, 3, 7, 6], [0, 7, 4, 6], [0, 4, 5, 6]]
const EDGES := [[0, 1], [1, 2], [2, 0], [0, 3], [1, 3], [2, 3]]
const TRIANGLES := [[], [0, 3, 2], [0, 1, 4], [1, 4, 2, 2, 4, 3], [1, 2, 5], [0, 3, 5, 0, 5, 1], [0, 2, 5, 0, 5, 4], [5, 4, 3], [3, 4, 5], [4, 5, 0, 5, 2, 0], [1, 5, 0, 5, 3, 0], [5, 2, 1], [3, 4, 2, 2, 4, 1], [4, 1, 0], [2, 3, 0], []]

var _field := PackedFloat32Array()
var _gradients := PackedVector3Array()
var _flags := PackedByteArray()
var _touched := PackedInt32Array()
var _cells := PackedInt32Array()
var _floor := PackedFloat32Array()
var _cached_level: LevelDefinition
var _values := PackedFloat32Array()
var _points := PackedVector3Array()
var _point_normals := PackedVector3Array()
var _edge_points := PackedVector3Array()
var _edge_normals := PackedVector3Array()
var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _mesh := ArrayMesh.new()
var _mass_weight: float = 1.0


func _init(profile: LiquidProfile = null) -> void:
	if profile != null: _mass_weight = pow(profile.particle_spacing / 0.1, 3.0)
	_values.resize(8)
	_points.resize(8)
	_point_normals.resize(8)
	_edge_points.resize(6)
	_edge_normals.resize(6)
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var water := ShaderMaterial.new()
	water.shader = preload("res://assets/materials/water.gdshader")
	if profile != null: water.set_shader_parameter("water_color", profile.color)
	material_override = water


func rebuild(particles: PackedVector3Array, level: LevelDefinition, active: PackedByteArray = PackedByteArray(), solver: RefCounted = null) -> void:
	if solver != null:
		var data: Dictionary = solver.call("build_surface")
		_mesh.clear_surfaces()
		var vertices: PackedVector3Array = data.vertices
		if vertices.is_empty(): return
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = data.normals
		_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return
	if _field.is_empty():
		_field.resize(COUNT)
		_gradients.resize(COUNT)
		_flags.resize(COUNT)
		_floor.resize(SLICE)
	for index: int in _touched:
		_field[index] = 0.0
		_gradients[index] = Vector3.ZERO
	for index: int in _cells: _flags[index] = 0
	_touched.clear()
	_cells.clear()
	if _cached_level != level:
		_cached_level = level
		for iz: int in range(NZ):
			for ix: int in range(NX):
				_floor[iz * NX + ix] = level.floor_height(Vector2(ORIGIN.x + ix * CELL, ORIGIN.z + iz * CELL))
	var radius2 := RADIUS * RADIUS
	for i: int in range(particles.size()):
		if not active.is_empty() and active[i] == 0: continue
		var p := particles[i]
		var center := (p - ORIGIN) / CELL
		for iy: int in range(maxi(1, floori(center.y) - 2), mini(NY - 1, ceili(center.y) + 3)):
			var y := ORIGIN.y + iy * CELL
			var dy := y - p.y
			if dy * dy >= radius2: continue
			for iz: int in range(maxi(1, floori(center.z) - 2), mini(NZ - 1, ceili(center.z) + 3)):
				var dz := ORIGIN.z + iz * CELL - p.z
				var yz2 := dy * dy + dz * dz
				if yz2 >= radius2: continue
				for ix: int in range(maxi(1, floori(center.x) - 2), mini(NX - 1, ceili(center.x) + 3)):
					var plane_index := iz * NX + ix
					if y < _floor[plane_index] + 0.002: continue
					var dx := ORIGIN.x + ix * CELL - p.x
					var q := 1.0 - (dx * dx + yz2) / radius2
					if q <= 0.0: continue
					var index := iy * SLICE + plane_index
					if _field[index] == 0.0: _touched.append(index)
					_field[index] += q * q * q * _mass_weight
					_gradients[index] += Vector3(dx, dy, dz) * (-6.0 * q * q * _mass_weight / radius2)
					for offset: int in CELL_OFFSETS:
						var cell := index + offset
						if _flags[cell] == 0:
							_flags[cell] = 1
							_cells.append(cell)
	_vertices.clear()
	_normals.clear()
	for index: int in _cells:
		var mask := 0
		for corner: int in range(8):
			var node: int = index + CORNERS[corner]
			_values[corner] = _field[node]
			if _values[corner] >= ISO: mask |= 1 << corner
		if mask == 0 or mask == 255: continue
		for corner: int in range(8):
			var node: int = index + CORNERS[corner]
			var iy := node / SLICE
			var plane := node % SLICE
			_points[corner] = ORIGIN + Vector3(plane % NX, iy, plane / NX) * CELL
			_point_normals[corner] = -_gradients[node]
		for tet: Array in TETS:
			var tetra_mask := 0
			for vertex: int in range(4):
				if _values[tet[vertex]] >= ISO: tetra_mask |= 1 << vertex
			var triangles: Array = TRIANGLES[tetra_mask]
			if triangles.is_empty(): continue
			for edge: int in range(6):
				var a: int = tet[EDGES[edge][0]]
				var b: int = tet[EDGES[edge][1]]
				if (_values[a] >= ISO) == (_values[b] >= ISO): continue
				var t := clampf((ISO - _values[a]) / (_values[b] - _values[a]), 0.0, 1.0)
				_edge_points[edge] = _points[a].lerp(_points[b], t)
				var normal := _point_normals[a].lerp(_point_normals[b], t)
				_edge_normals[edge] = normal.normalized() if normal.length_squared() > 0.000001 else Vector3.UP
			for triangle: int in range(0, triangles.size(), 3):
				_triangle(triangles[triangle], triangles[triangle + 1], triangles[triangle + 2])
	_mesh.clear_surfaces()
	if _vertices.is_empty(): return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func _triangle(a: int, b: int, c: int) -> void:
	var face := (_edge_points[b] - _edge_points[a]).cross(_edge_points[c] - _edge_points[a])
	if face.dot(_edge_normals[a] + _edge_normals[b] + _edge_normals[c]) > 0.0:
		var swap := b
		b = c
		c = swap
	for vertex: int in [a, b, c]:
		_vertices.append(_edge_points[vertex])
		_normals.append(_edge_normals[vertex])
