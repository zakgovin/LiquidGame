class_name LiquidProfile
extends Resource
## One material in an incompressible grid. Density is kg/m³ and viscosity is
## kinematic m²/s; other materials and mixing remain a separate future feature.

@export var display_name: String = "Вода"
@export var symbol: String = "H₂O"
@export var color: Color = Color("2c9fc9")
@export var rest_density: float = 1000.0
@export var viscosity: float = 0.000001
@export var surface_tension: float = 0.072
@export var particle_spacing: float = 0.038
@export var particle_radius: float = 0.017
@export var drag: float = 0.015
@export var max_speed: float = 3.0
