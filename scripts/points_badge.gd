class_name PointsBadge
extends Control
## HUD: the Light Points icon and the current balance.

var points: int = 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(110, 40)
	size = custom_minimum_size


func set_points(value: int) -> void:
	points = value
	queue_redraw()


func _draw() -> void:
	HudIcons.light_point(self, Vector2(12, 20), 26.0)
	draw_string(ThemeDB.fallback_font, Vector2(30, 28), str(points), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, HudIcons.GOLD)
