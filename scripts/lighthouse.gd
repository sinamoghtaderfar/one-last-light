class_name Lighthouse
extends Node2D
## The drawn cone and contact detection use the same mouse-controlled bearing.

@export var rotation_speed: float = 6.0 # radians per second
@export var beam_length: float = 660.0
@export var beam_width: float = 0.48

## Shop upgrades: each light level adds this much length and cone width to the authored beam.
@export var length_per_level: float = 110.0
@export var width_per_level: float = 0.10

var beam_angle: float = -PI
var enabled: bool = true
var _base_length: float = -1.0
var _base_width: float = -1.0


func apply_light_level(light_level: int) -> void:
	if _base_length < 0.0:
		_base_length = beam_length
		_base_width = beam_width
	beam_length = _base_length + length_per_level * maxi(light_level, 0)
	beam_width = _base_width + width_per_level * maxi(light_level, 0)
	queue_redraw()


func _process(delta: float) -> void:
	if enabled:
		aim_at(get_global_mouse_position(), delta)


## Snaps the beam to face a world position at once, e.g. the harbor when a round is prepared.
func point_at(point: Vector2) -> void:
	var direction := point - global_position
	if not direction.is_zero_approx():
		beam_angle = direction.angle()
		queue_redraw()


func aim_at(point: Vector2, delta: float) -> void:
	var direction := point - global_position
	if not direction.is_zero_approx():
		beam_angle = rotate_toward(beam_angle, direction.angle(), rotation_speed * delta)
		queue_redraw()


func is_illuminated(world_position: Vector2) -> bool:
	var offset: Vector2 = world_position - global_position
	if not enabled or offset.length() > beam_length:
		return false
	return absf(wrapf(offset.angle() - beam_angle, -PI, PI)) <= beam_width * 0.5


func _draw() -> void:
	# Drawing geometry avoids sprite imports and works with Compatibility rendering.
	var cone := PackedVector2Array([Vector2.ZERO])
	for step in range(25):
		var angle: float = beam_angle - beam_width * 0.5 + beam_width * step / 24.0
		cone.append(Vector2.from_angle(angle) * beam_length)
	draw_colored_polygon(cone, Color(1.0, 0.86, 0.39, 0.13))
	draw_line(Vector2.ZERO, cone[1], Color(1.0, 0.88, 0.46, 0.20), 1.0, true)
	draw_line(Vector2.ZERO, cone[cone.size() - 1], Color(1.0, 0.88, 0.46, 0.20), 1.0, true)
	draw_line(Vector2.ZERO, Vector2.from_angle(beam_angle) * beam_length,
		Color(1.0, 0.90, 0.60, 0.10), 2.0, true)

	draw_circle(Vector2.ZERO, 55.0, Color(0.35, 0.55, 0.59, 0.18))
	var island := PackedVector2Array([
		Vector2(-46, -11), Vector2(-31, -37), Vector2(3, -46),
		Vector2(35, -31), Vector2(48, 6), Vector2(26, 38),
		Vector2(-9, 47), Vector2(-39, 29),
	])
	draw_colored_polygon(island, Color("48575d"))
	island.append(island[0])
	draw_polyline(island, Color("7d8d8f"), 2.0, true)
	draw_circle(Vector2(-24, 17), 8.0, Color("617174"))
	draw_circle(Vector2(26, 12), 6.0, Color("617174"))

	var tower := PackedVector2Array([
		Vector2(-13, 21), Vector2(13, 21), Vector2(9, -24), Vector2(-9, -24),
	])
	draw_colored_polygon(tower, Color("e8e4cc"))
	draw_rect(Rect2(-11, -3, 22, 10), Color("c76b54"))
	draw_rect(Rect2(-5, 10, 10, 11), Color("263c43"))
	draw_rect(Rect2(-13, -30, 26, 10), Color("243a42"))
	draw_rect(Rect2(-10, -28, 20, 6), Color("ffe69a"))
	draw_line(Vector2(-17, -31), Vector2(17, -31), Color("dce2d6"), 3.0, true)
	draw_line(Vector2(-14, -18), Vector2(14, -18), Color("dce2d6"), 3.0, true)
	draw_string(ThemeDB.fallback_font, Vector2(-46, 70), "LIGHTHOUSE",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color("a5b9ba"))
