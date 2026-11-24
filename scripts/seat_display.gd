class_name SeatDisplay
extends Control
## HUD: a lifeboat with one dot per seat. Empty seats are hollow; a boarded survivor turns a seat
## green with a short pop. A newly bought seat can be highlighted (pulsing glow).

const DOT := 15.0
const PITCH := 22.0

var capacity: int = 1
var passengers: int = 0
var highlight_seat: int = -1
var _pops: Dictionary = {}
var _time: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(110, 40)
	size = custom_minimum_size


func set_state(new_capacity: int, new_passengers: int) -> void:
	if new_passengers > passengers:
		for index in range(passengers, mini(new_passengers, new_capacity)):
			_pops[index] = 0.0
	capacity = new_capacity
	passengers = new_passengers
	custom_minimum_size.x = 48.0 + capacity * PITCH
	size.x = custom_minimum_size.x
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	for key in _pops.keys():
		_pops[key] += delta
		if _pops[key] > 0.45:
			_pops.erase(key)
	if not _pops.is_empty() or highlight_seat >= 0:
		queue_redraw()


func _draw() -> void:
	HudIcons.boat(self, Vector2(16, 20), 30.0)
	for index in range(capacity):
		var center := Vector2(48 + index * PITCH, 20)
		var scale_now := 1.0
		if _pops.has(index):
			scale_now = 1.0 + 0.6 * sin(clampf(_pops[index] / 0.45, 0.0, 1.0) * PI)
		if index == highlight_seat:
			var glow := 0.5 + 0.5 * sin(_time * 7.0)
			draw_circle(center, DOT * (1.0 + 0.7 * glow), Color(HudIcons.GOLD, 0.25 + 0.3 * glow))
		var radius := DOT * 0.5 * scale_now
		if index < passengers:
			draw_circle(center, radius, Color("6fe39a"))
			draw_arc(center, radius, 0.0, TAU, 20, Color.WHITE, 1.6, true)
			HudIcons.person(self, center + Vector2(0, 1), radius * 1.5, Color("0d1c29"))
		else:
			draw_circle(center, radius, Color(0.08, 0.15, 0.2))
			draw_arc(center, radius, 0.0, TAU, 20, HudIcons.GOLD if index == highlight_seat else HudIcons.MUTED, 1.6, true)
