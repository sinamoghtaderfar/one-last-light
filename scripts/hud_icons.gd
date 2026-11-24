class_name HudIcons
extends RefCounted
## Small pictograms shared by the HUD, the shop and the result screens, drawn with canvas
## primitives (the bundled font has no emoji or symbol glyphs, and Web builds have no fallback).

const TEAL := Color("7fe0cc")
const GOLD := Color("ffda92")
const TEXT := Color("e4ece8")
const MUTED := Color("91abb7")
const RED := Color("d9363e")


static func star_points(center: Vector2, outer: float, inner: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(10):
		var radius := outer if index % 2 == 0 else inner
		points.append(center + Vector2.from_angle(-PI * 0.5 + index * PI / 5.0) * radius)
	return points


static func star(item: CanvasItem, center: Vector2, size: float, filled: bool, color: Color = GOLD) -> void:
	var shape := star_points(center, size, size * 0.45)
	if filled:
		item.draw_colored_polygon(shape, color)
	else:
		item.draw_colored_polygon(shape, Color(0.1, 0.17, 0.22, 0.9))
	var loop := shape.duplicate()
	loop.append(shape[0])
	item.draw_polyline(loop, color if filled else Color(color, 0.55), 1.5, true)


## A small lighthouse with rays: the Light Points currency.
static func light_point(item: CanvasItem, center: Vector2, size: float, alpha: float = 1.0) -> void:
	var s := size / 20.0
	for angle in [-0.5, 0.0, 0.5]:
		var dir := Vector2.from_angle(-PI * 0.5 + angle)
		item.draw_line(center + Vector2(0, -9) * s + dir * 6.0 * s, center + Vector2(0, -9) * s + dir * 12.0 * s, Color(GOLD, alpha * 0.9), 2.0 * s, true)
	item.draw_colored_polygon(PackedVector2Array([center + Vector2(-5, 10) * s, center + Vector2(5, 10) * s, center + Vector2(3, -5) * s, center + Vector2(-3, -5) * s]), Color(TEXT, alpha))
	item.draw_rect(Rect2(center + Vector2(-4, 1) * s, Vector2(8, 3) * s), Color(RED, alpha))
	item.draw_rect(Rect2(center + Vector2(-4, -10) * s, Vector2(8, 5) * s), Color(GOLD, alpha))


## A person (head and shoulders), used by the progress bar.
static func person(item: CanvasItem, center: Vector2, size: float, color: Color) -> void:
	var s := size / 20.0
	item.draw_circle(center + Vector2(0, -4) * s, 4.5 * s, color)
	item.draw_colored_polygon(PackedVector2Array([
		center + Vector2(-8, 9) * s, center + Vector2(-6, 3) * s, center + Vector2(-2, 1) * s,
		center + Vector2(2, 1) * s, center + Vector2(6, 3) * s, center + Vector2(8, 9) * s]), color)


## A side-on lifeboat (white hull, red band), used by the seat display.
static func boat(item: CanvasItem, center: Vector2, size: float, alpha: float = 1.0) -> void:
	var s := size / 24.0
	var hull := PackedVector2Array([center + Vector2(-12, -1) * s, center + Vector2(12, -1) * s, center + Vector2(8, 6) * s, center + Vector2(-9, 6) * s])
	item.draw_colored_polygon(hull, Color("f6f3ec", alpha))
	item.draw_line(center + Vector2(-11, 1) * s, center + Vector2(11, 1) * s, Color(RED, alpha), 2.2 * s, true)
	item.draw_rect(Rect2(center + Vector2(-4, -6) * s, Vector2(8, 5) * s), Color("c9d6d8", alpha))


## Shop item pictograms, one per ShopCatalog.Kind.
static func shop_item(item: CanvasItem, kind: int, center: Vector2, size: float, color: Color) -> void:
	var s := size / 40.0
	match kind:
		ShopCatalog.Kind.CAPACITY:
			boat(item, center + Vector2(0, 6) * s, 34.0 * s)
			for index in range(3):
				item.draw_circle(center + Vector2(-9 + index * 9, -10) * s, 3.4 * s, color if index < 2 else Color(color, 0.35))
		ShopCatalog.Kind.SPEED:
			boat(item, center + Vector2(4, 4) * s, 30.0 * s)
			for row in range(3):
				item.draw_line(center + Vector2(-20, -6 + row * 6) * s, center + Vector2(-10 + row * 2, -6 + row * 6) * s, color, 2.2 * s, true)
		ShopCatalog.Kind.LIGHT:
			item.draw_colored_polygon(PackedVector2Array([center + Vector2(-2, -8) * s, center + Vector2(20, -18) * s, center + Vector2(20, 2) * s]), Color(GOLD, 0.45))
			light_point(item, center + Vector2(-6, 2) * s, 26.0 * s)
		ShopCatalog.Kind.DINGHY:
			boat(item, center + Vector2(-6, 6) * s, 22.0 * s)
			boat(item, center + Vector2(9, -4) * s, 16.0 * s)
			item.draw_arc(center + Vector2(9, -4) * s, 12.0 * s, -PI, 0.0, 16, Color(color, 0.8), 1.6 * s, true)
		ShopCatalog.Kind.BOOST:
			oxygen_tank(item, center, size, color)


static func oxygen_tank(item: CanvasItem, center: Vector2, size: float, color: Color) -> void:
	var s := size / 40.0
	var body := StyleBoxFlat.new()
	body.bg_color = Color("2f6f86")
	body.border_color = color
	body.set_border_width_all(maxi(1, roundi(2.0 * s)))
	body.set_corner_radius_all(roundi(7.0 * s))
	item.draw_style_box(body, Rect2(center + Vector2(-8, -12) * s, Vector2(16, 28) * s))
	item.draw_rect(Rect2(center + Vector2(-3, -17) * s, Vector2(6, 5) * s), color)
	item.draw_line(center + Vector2(0, -2) * s, center + Vector2(0, 8) * s, Color.WHITE, 2.5 * s, true)
	item.draw_line(center + Vector2(-5, 3) * s, center + Vector2(5, 3) * s, Color.WHITE, 2.5 * s, true)
