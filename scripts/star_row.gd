class_name StarRow
extends Control
## Result screen: the level's 1-3 star rating. Stars earned for the first time pop in.

var stars: int = 0
var previous_best: int = 0
## Radius of one star and the distance between stars (the level map uses small ones).
var star_size: float = 26.0
var spacing: float = 62.0
var _time: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(200, 64)


func _process(delta: float) -> void:
	_time += delta
	if _time < 1.6:
		queue_redraw()


func _draw() -> void:
	var middle := size.x * 0.5
	for index in range(3):
		var center := Vector2(middle + (index - 1) * spacing, size.y * 0.5)
		var filled := index < stars
		var radius := star_size
		if filled and index >= previous_best:
			var t := clampf((_time - 0.25 * index) / 0.4, 0.0, 1.0)
			radius *= 1.0 + 0.35 * sin(t * PI) if t > 0.0 else 1.0
			filled = t > 0.0
		HudIcons.star(self, center, radius, filled)
