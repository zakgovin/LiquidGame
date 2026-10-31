class_name FluidSurface
extends MeshInstance3D
## An implicit surface joins neighboring particles into continuous water.
## Marching squares at 30 Hz. No per-particle Nodes or draw calls.

const CELL: float = 0.095
const ORIGIN := Vector2(-3.25, -4.85)
const WIDTH: int = 72
const HEIGHT: int = 104
const ISO: float = 0.50
const RADIUS: float = 0.195
const POLYGONS: Array = [
	[], [[0, 4, 7]], [[1, 5, 4]], [[0, 1, 5, 7]],
	[[2, 6, 5]], [[0, 4, 7], [2, 6, 5]], [[1, 2, 6, 4]], [[0, 1, 2, 6, 7]],
	[[3, 7, 6]], [[0, 4, 6, 3]], [[1, 5, 4], [3, 7, 6]], [[0, 1, 5, 6, 3]],
	[[2, 3, 7, 5]], [[0, 4, 5, 2, 3]], [[4, 1, 2, 3, 7]], [[0, 1, 2, 3]]
]

var _field := PackedFloat32Array()
var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _points := PackedVector3Array()
var _mesh := ArrayMesh.new()


func _init(profile: LiquidProfile = null) -> void:
	_field.resize(WIDTH * HEIGHT)
	_points.resize(8)
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shader_material := ShaderMaterial.new()
	shader_material.shader = preload("res://assets/materials/water.gdshader")
	if profile != null:
		shader_material.set_shader_parameter("water_color", profile.color)
	material_override = shader_material


func rebuild(particles: PackedVector2Array, level: LevelDefinition) -> void:
	_field.fill(0.0)
	for point: Vector2 in particles:
		var center := (point - ORIGIN) / CELL
		for gy: int in range(maxi(0, floori(center.y) - 2), mini(HEIGHT, ceili(center.y) + 3)):
			for gx: int in range(maxi(0, floori(center.x) - 2), mini(WIDTH, ceili(center.x) + 3)):
				var sample_point := ORIGIN + Vector2(gx, gy) * CELL
				var d := sample_point.distance_squared_to(point) / (RADIUS * RADIUS)
				if d < 1.0:
					_field[gy * WIDTH + gx] += (1.0 - d) * (1.0 - d)
	# Keep the visual meniscus within the same walls as the physical particles.
	for gy: int in range(HEIGHT):
		for gx: int in range(WIDTH):
			if _field[gy * WIDTH + gx] > 0.0 and not level.contains(ORIGIN + Vector2(gx, gy) * CELL, 0.01):
				_field[gy * WIDTH + gx] = 0.0
	_vertices.clear()
	_normals.clear()
	for gy: int in range(HEIGHT - 1):
		for gx: int in range(WIDTH - 1):
			var index := gy * WIDTH + gx
			var values := [_field[index], _field[index + 1], _field[index + WIDTH + 1], _field[index + WIDTH]]
			var mask := 0
			for corner: int in range(4):
				if values[corner] >= ISO:
					mask |= 1 << corner
			if mask == 0:
				continue
			var x := ORIGIN.x + gx * CELL
			var z := ORIGIN.y + gy * CELL
			_points[0] = Vector3(x, 0.06, z)
			_points[1] = Vector3(x + CELL, 0.06, z)
			_points[2] = Vector3(x + CELL, 0.06, z + CELL)
			_points[3] = Vector3(x, 0.06, z + CELL)
			for edge: int in range(4):
				var next := (edge + 1) % 4
				var denominator: float = values[next] - values[edge]
				var t := 0.5 if absf(denominator) < 0.0001 else clampf((ISO - values[edge]) / denominator, 0.0, 1.0)
				_points[4 + edge] = _points[edge].lerp(_points[next], t)
			for polygon: Array in POLYGONS[mask]:
				for triangle: int in range(1, polygon.size() - 1):
					for vertex: int in [polygon[0], polygon[triangle], polygon[triangle + 1]]:
						_vertices.append(_points[vertex])
						_normals.append(Vector3.UP)
				# Vertical meniscus closes the surface down to the channel floor.
				for edge: int in range(polygon.size()):
					var a: int = polygon[edge]
					var b: int = polygon[(edge + 1) % polygon.size()]
					if a >= 4 and b >= 4:
						var top_a := _points[a]
						var top_b := _points[b]
						var bottom_a := Vector3(top_a.x, 0.02, top_a.z)
						var bottom_b := Vector3(top_b.x, 0.02, top_b.z)
						var normal := (top_b - top_a).cross(Vector3.UP).normalized()
						for vertex: Vector3 in [top_a, bottom_a, bottom_b, top_a, bottom_b, top_b]:
							_vertices.append(vertex)
							_normals.append(normal)
	_mesh.clear_surfaces()
	if _vertices.is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
