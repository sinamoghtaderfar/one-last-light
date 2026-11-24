class_name Harbor
extends Node2D
## Boats may enter this nonblocking safe zone to deliver all passengers.

@export var safe_radius: float = 62.0

var boat_present: bool = false
## The boat is full: the harbor blinks to call it back.
var calling: bool = false
var _time: float = 0.0


func contains_point(point: Vector2) -> bool:
	return global_position.distance_to(point) <= safe_radius


func set_boat_present(present: bool) -> void:
	if boat_present != present:
		boat_present = present
		queue_redraw()


func set_calling(value: bool) -> void:
	if calling != value:
		calling = value
		_time = 0.0
		set_process(calling)
		queue_redraw()


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


## 0..1, about two blinks a second while calling.
func blink() -> float:
	return 0.5 + 0.5 * sin(_time * TAU * 2.0) if calling else 0.0


func _draw() -> void:
	if calling:
		# Calling the boat back: a gold glow on the berth and the dock, and a ring rippling outwards.
		var glow := blink()
		draw_circle(Vector2.ZERO, safe_radius, Color("ffda92", 0.10 + 0.18 * glow))
		var ripple := fposmod(_time * 0.9, 1.0)
		draw_arc(Vector2.ZERO, safe_radius + 6.0 + ripple * 34.0, 0.0, TAU, 48, Color("ffda92", 0.7 * (1.0 - ripple)), 3.0, true)
		draw_rect(Rect2(56, -60, 59, 120), Color("ffda92", 0.12 + 0.22 * glow))
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
		draw_circle(corner, 4.0 + 3.0 * blink(), Color("ffe69a"))

	draw_string(ThemeDB.fallback_font, Vector2(-39, -79), "HARBOR",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17, safe_color.lerp(Color("ffda92"), blink()))
	if calling:
		draw_string(ThemeDB.fallback_font, Vector2(-60, -100), "BRING THEM HERE",
			HORIZONTAL_ALIGNMENT_CENTER, 120.0, 11, Color("ffda92", 0.6 + 0.4 * blink()))
	draw_string(ThemeDB.fallback_font, Vector2(-43, 83), "[E] UNLOAD",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color("b7cec5"))
