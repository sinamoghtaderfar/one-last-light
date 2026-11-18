class_name SurvivorSpec
extends Resource
## One survivor of a level: a stable id, a spot on the chart and its own oxygen budget.

@export_range(1, 99) var survivor_id: int = 1
@export var position: Vector2 = Vector2.ZERO
## Seconds of oxygen from the moment the level starts, until the boat picks the survivor up.
@export_range(1.0, 600.0) var oxygen_seconds: float = 120.0
