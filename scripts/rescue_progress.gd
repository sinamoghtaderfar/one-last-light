class_name RescueProgress
extends Control
## HUD progress for the level, readable for any number of survivors: one continuous bar.
## Green from the left: delivered. Pale green after it: aboard. Red from the right: drowned.
## Grey: still in the water. A tick marks the deliveries needed to win. "n/N" sits on the right.

const BAR := Rect2(30, 13, 240, 14)
const SAVED := Color("6fe39a")
const ABOARD := Color("6fe39a")
const LOST := Color("e5545c")
const EMPTY := Color("23404c")

var total: int = 1
var delivered: int = 0
var aboard: int = 0
var lost: int = 0
var required: int = 1
var highlight: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(330, 40)
	size = custom_minimum_size


func set_state(new_total: int, new_delivered: int, new_aboard: int, new_lost: int, new_required: int) -> void:
	total = maxi(new_total, 1)
	delivered = new_delivered
	aboard = new_aboard
	lost = new_lost
	required = new_required
	queue_redraw()


func saved_ratio() -> float:
	return float(delivered) / total


func lost_ratio() -> float:
	return float(lost) / total


func _draw() -> void:
	HudIcons.person(self, Vector2(13, 20), 22.0, SAVED if delivered == total else HudIcons.TEXT)
	var bar := BAR
	var back := StyleBoxFlat.new()
	back.bg_color = EMPTY
	back.set_corner_radius_all(7)
	draw_style_box(back, bar)
	var w := bar.size.x
	var saved_w := w * saved_ratio()
	var aboard_w := w * float(aboard) / total
	var lost_w := w * lost_ratio()
	if saved_w > 0.0:
		_fill(Rect2(bar.position, Vector2(saved_w, bar.size.y)), SAVED, true, saved_w >= w - 0.5)
	if aboard_w > 0.0:
		var aboard_rect := Rect2(bar.position + Vector2(saved_w, 0), Vector2(aboard_w, bar.size.y))
		_fill(aboard_rect, Color(ABOARD, 0.35), saved_w <= 0.0, false)
		draw_rect(aboard_rect.grow(-1.0), Color(ABOARD, 0.9), false, 1.0)
	if lost_w > 0.0:
		_fill(Rect2(bar.end - Vector2(lost_w, bar.size.y), Vector2(lost_w, bar.size.y)), LOST, lost_w >= w - 0.5, true)
	# The win line: deliveries needed. With spare lives it sits before the end of the bar.
	if required < total:
		var x := bar.position.x + w * float(required) / total
		draw_line(Vector2(x, bar.position.y - 4), Vector2(x, bar.end.y + 4), HudIcons.GOLD, 2.0, true)
	draw_rect(bar, Color(1, 1, 1, 0.18), false, 1.0)
	if highlight > 0.0:
		draw_rect(bar.grow(5.0 + 3.0 * highlight), Color(HudIcons.GOLD, 0.8 * highlight), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(bar.end.x + 10, 27), "%d/%d" % [delivered, total], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, HudIcons.TEXT)


func _fill(rect: Rect2, color: Color, round_left: bool, round_right: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 7 if round_left else 0
	style.corner_radius_bottom_left = 7 if round_left else 0
	style.corner_radius_top_right = 7 if round_right else 0
	style.corner_radius_bottom_right = 7 if round_right else 0
	draw_style_box(style, rect)
