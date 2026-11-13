class_name Harbor
extends Node2D
## Boats may enter this nonblocking safe zone to deliver all passengers.

@export var safe_radius: float = 62.0

var boat_present: bool = false


func contains_point(point: Vector2) -> bool:
	return global_position.distance_to(point) <= safe_radius


func set_boat_present(present: bool) -> void:
	if boat_present != present:
		boat_present = present
		queue_redraw()


func _draw() -> void:
	var safe_color := Color("68d6b0")
	var fill_alpha: float = 0.13 if boat_present else 0.065
	draw_circle(Vector2.ZERO, safe_radius, Color(safe_color, fill_alpha))
	for segment in range(16):
		var start: float = segment * TAU / 16.0
		draw_arc(Vector2.ZERO, safe_radius, start, start + TAU / 24.0,
			5, Color(safe_color, 0.70), 2.0, true)
	draw_circle(Vector2.ZERO, 4.0, safe_color)
	draw_line(Vector2(-10, 0), Vector2(10, 0), Color(safe_color, 0.55), 1.0)
	draw_line(Vector2(0, -10), Vector2(0, 10), Color(safe_color, 0.55), 1.0)

	# The dock is deliberately visual only, so the safe zone cannot trap the boat.
	draw_rect(Rect2(58, -58, 55, 116), Color("3b4c51"))
	draw_rect(Rect2(43, -45, 69, 14), Color("82908b"))
	draw_rect(Rect2(43, 31, 69, 14), Color("82908b"))
	draw_line(Vector2(58, -59), Vector2(58, 59), Color("aeb8a4"), 3.0)
	for y in range(-40, 45, 17):
		draw_line(Vector2(69, y), Vector2(110, y), Color("526467"), 2.0)
	for corner in [Vector2(45, -38), Vector2(45, 38)]:
		draw_circle(corner, 4.0, Color("ffe69a"))

	draw_string(ThemeDB.fallback_font, Vector2(-39, -79), "HARBOR",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17, safe_color)
	draw_string(ThemeDB.fallback_font, Vector2(-43, 83), "[E] UNLOAD",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color("b7cec5"))
