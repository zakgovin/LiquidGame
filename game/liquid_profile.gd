class_name LiquidProfile
extends Resource
## Material parameters independent of levels. Only water is shipped in v0.1.
## A future multi-material solver must explicitly implement mixing/separation rules.

@export var display_name: String = "Вода"
@export var symbol: String = "H₂O"
@export var color: Color = Color("16b3df")
@export_range(0.1, 10.0) var rest_density: float = 2.5
@export var pressure_stiffness: float = 170.0
@export var near_pressure_stiffness: float = 230.0
@export_range(0.0, 5.0) var viscosity: float = 0.18
@export var interaction_radius: float = 0.25
@export var particle_radius: float = 0.052
