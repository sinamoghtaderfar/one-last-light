class_name LifeHeart
extends Control
## One life in the top HUD. A level has allowed_losses + 1 of them; each drowned survivor takes one.
## Drawn with canvas primitives, like the rest of the graybox.

const FILL := Color("f0727a")
const OUTLINE := Color("ffd0d3")
const SHINE := Color(1, 1, 1, 0.35)

static var _unit_shape := PackedVector2Array()


func _init() -> void:
	custom_minimum_size = Vector2(26, 26)
	size = Vector2(26, 26)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


## Heart outline in a unit box (0..1 on both axes), shared with the heart-break animation.
static func unit_heart() -> PackedVector2Array:
	if _unit_shape.is_empty():
		var raw := PackedVector2Array()
		for step in range(48):
			var angle := TAU * step / 48.0
			raw.append(Vector2(
				16.0 * pow(sin(angle), 3.0),
				-(13.0 * cos(angle) - 5.0 * cos(2.0 * angle) - 2.0 * cos(3.0 * angle) - cos(4.0 * angle))))
		var low := raw[0]
		var high := raw[0]
		for point in raw:
			low = Vector2(minf(low.x, point.x), minf(low.y, point.y))
			high = Vector2(maxf(high.x, point.x), maxf(high.y, point.y))
		for point in raw:
			_unit_shape.append((point - low) / (high - low))
	return _unit_shape


## The heart centred on the origin, size wide and high.
static func heart_shape(heart_size: Vector2) -> PackedVector2Array:
	var shape := PackedVector2Array()
	for point in unit_heart():
		shape.append((point - Vector2(0.5, 0.5)) * heart_size)
	return shape


static func closed(points: PackedVector2Array) -> PackedVector2Array:
	var loop := points.duplicate()
	loop.append(points[0])
	return loop


func _draw() -> void:
	var shape := heart_shape(size)
	draw_set_transform(size * 0.5, 0.0, Vector2.ONE)
	draw_colored_polygon(shape, FILL)
	draw_polyline(closed(shape), OUTLINE, 1.4, true)
	draw_circle(Vector2(-size.x * 0.2, -size.y * 0.18), size.x * 0.08, SHINE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
