class_name BoostButton
extends Control
## Level HUD: the armed Oxygen Boost. Click to use it. It shakes and shows a hint every time a
## survivor's heart turns red, until it is used.

signal activated

const SIZE := Vector2(76, 86)

var _shake: float = 0.0
var _hint: float = 0.0
var _time: float = 0.0


func _init() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Oxygen Boost: +15 s for everyone in the water"


func nudge() -> void:
	_shake = 1.2
	_hint = 4.0
	queue_redraw()


func is_shaking() -> bool:
	return _shake > 0.0


func hint_visible() -> bool:
	return _hint > 0.0


func advance(delta: float) -> void:
	_time += delta
	_shake = maxf(_shake - delta, 0.0)
	_hint = maxf(_hint - delta, 0.0)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		activated.emit()


func _draw() -> void:
	var offset := Vector2(sin(_time * 55.0) * 5.0 * minf(_shake, 1.0), 0)
	var rotation_now := sin(_time * 40.0) * 0.12 * minf(_shake, 1.0)
	draw_set_transform(SIZE * 0.5 + offset, rotation_now, Vector2.ONE)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.06, 0.16, 0.22, 0.95)
	panel.border_color = HudIcons.GOLD if _shake > 0.0 else HudIcons.TEAL
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(12)
	draw_style_box(panel, Rect2(-SIZE * 0.5, SIZE))
	HudIcons.oxygen_tank(self, Vector2(0, -10), 40.0, HudIcons.TEAL)
	draw_string(ThemeDB.fallback_font, Vector2(-SIZE.x * 0.5, 34), "+15 s", HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, 15, HudIcons.GOLD)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _hint > 0.0:
		var alpha := clampf(_hint / 0.5, 0.0, 1.0)
		var box := Rect2(Vector2(SIZE.x + 10, 10), Vector2(250, 58))
		var bubble := StyleBoxFlat.new()
		bubble.bg_color = Color(0.05, 0.11, 0.16, 0.94 * alpha)
		bubble.border_color = Color(HudIcons.GOLD, alpha)
		bubble.set_border_width_all(2)
		bubble.set_corner_radius_all(10)
		draw_style_box(bubble, box)
		draw_colored_polygon(PackedVector2Array([Vector2(SIZE.x + 10, 30), Vector2(SIZE.x + 2, 38), Vector2(SIZE.x + 10, 46)]), Color(HudIcons.GOLD, alpha))
		draw_string(ThemeDB.fallback_font, box.position + Vector2(0, 24), "Someone is running out of air!", HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 14, Color(HudIcons.GOLD, alpha))
		draw_string(ThemeDB.fallback_font, box.position + Vector2(0, 44), "Click to give everyone +15 s", HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 13, Color(HudIcons.TEXT, alpha))
