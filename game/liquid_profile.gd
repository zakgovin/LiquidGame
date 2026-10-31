class_name LiquidProfile
extends Resource
## Volumetric fluid parameters, separate from level geometry. Density is the
## dimensionless kernel rest density, not a claim about physical kg/m³.

@export var display_name: String = "Вода"
@export var symbol: String = "H₂O"
@export var color: Color = Color("16b3df")
@export var rest_density: float = 6.8
@export var viscosity: float = 1.0
@export var interaction_radius: float = 0.22
@export var particle_spacing: float = 0.10
@export var particle_radius: float = 0.052
@export var drag: float = 0.04
@export var max_speed: float = 2.2
@export_range(2, 6) var solver_iterations: int = 3
