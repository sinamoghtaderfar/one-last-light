class_name RescueEconomy
extends Resource
## Balance settings are editable. Bank and purchases last for one game session.

const UNLOCK_LEVEL := {
	&"main_speed": 1,
	&"main_capacity": 2,
	&"lighthouse_range": 3,
	&"emergency_speed": 4,
	&"emergency_capacity": 5,
	&"emergency_cooldown": 6,
}

@export_range(0, 100) var stars_per_survivor: int = 3
@export_range(1, 100) var speed_base_cost: int = 18
@export_range(1, 100) var upgrade_cost_step: int = 9
@export_range(1, 10) var maximum_upgrade_level: int = 3

var stars: int = 0
var speed_level: int = 0


func _init() -> void:
	resource_local_to_scene = true


func credit_main_delivery(count: int) -> int:
	var earned := count * stars_per_survivor
	stars += earned
	return earned


func speed_cost() -> int:
	return speed_base_cost + speed_level * upgrade_cost_step


func buy_speed_upgrade(level: int) -> bool:
	if level < UNLOCK_LEVEL[&"main_speed"] or speed_level >= maximum_upgrade_level or stars < speed_cost():
		return false
	stars -= speed_cost()
	speed_level += 1
	return true
