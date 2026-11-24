class_name TourOverlay
extends Node2D
## Level 1 guided tour, drawn in screen space just under the HUD. Two independent parts:
## - the movement hint: the screen dims except a spotlight on the boat, and a panel above the
##   boat shows the WASD and arrow keys until the player first steers;
## - the E prompt: a small key-cap bubble above the boat ("pick up" / "drop off").
## Neither takes input. advance() is public so tests can step it by hand.

const DIM := Color(0.02, 0.05, 0.09, 0.66)
const PANEL_BG := Color(0.05, 0.11, 0.16, 0.92)
const PANEL_BORDER := Color("7fe0cc")
const KEY_BG := Color("1f3a47")
const KEY_BORDER := Color("e4ece8")
const GOLD := Color("ffda92")
const TEXT := Color("e4ece8")
const MUTED := Color("b8cdd2")
const SEA := Rect2(24, 116, 1104, 452)
const SPOT_RADIUS := 62.0
const MOVE_PANEL := Vector2(330, 128)
const PROMPT_PANEL := Vector2(300, 46)
const FADE_IN := 0.45
const FADE_OUT := 0.35

var boat: Node2D
## Movement hint: 0 = hidden, fades towards 1 while shown.
var move_alpha: float = 0.0
var move_showing: bool = false
var prompt_text: String = ""
var prompt_alpha: float = 0.0
var _shown_prompt: String = ""
var _time: float = 0.0


func _ready() -> void:
	set_process(false)


func show_move_hint() -> void:
	move_showing = true
	queue_redraw()


func dismiss_move_hint() -> void:
	move_showing = false


func is_move_hint_visible() -> bool:
	return move_showing or move_alpha > 0.0


## Empty text hides the prompt (with a short fade).
func set_prompt(text: String) -> void:
	prompt_text = text
	if text != "":
		_shown_prompt = text


func clear() -> void:
	move_showing = false
	move_alpha = 0.0
	prompt_text = ""
	prompt_alpha = 0.0
	_shown_prompt = ""
	queue_redraw()


func advance(delta: float) -> void:
	_time += delta
	move_alpha = move_toward(move_alpha, 1.0 if move_showing else 0.0, delta / (FADE_IN if move_showing else FADE_OUT))
	prompt_alpha = move_toward(prompt_alpha, 1.0 if prompt_text != "" else 0.0, delta / 0.2)
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(boat):
		return
	var at := boat.global_position
	if move_alpha > 0.0:
		_draw_move_hint(at, move_alpha)
	if prompt_alpha > 0.0 and _shown_prompt != "":
		_draw_prompt(at, prompt_alpha)


func _panel_rect(at: Vector2, panel_size: Vector2, lift: float) -> Rect2:
	var top_left := at + Vector2(-panel_size.x * 0.5, -lift - panel_size.y)
	top_left.x = clampf(top_left.x, SEA.position.x + 8, SEA.end.x - panel_size.x - 8)
	if top_left.y < SEA.position.y + 8: # No room above: show it below the boat instead.
		top_left.y = at.y + lift
	return Rect2(top_left, panel_size)


func _draw_move_hint(at: Vector2, alpha: float) -> void:
	# Dim everything except a soft spotlight around the boat: one very wide ring whose inner edge
	# is the spotlight, plus a thin feathered ring.
	var width := 2600.0
	draw_arc(at, SPOT_RADIUS + width * 0.5, 0.0, TAU, 96, Color(DIM, DIM.a * alpha), width, true)
	draw_arc(at, SPOT_RADIUS - 6.0, 0.0, TAU, 96, Color(DIM, DIM.a * alpha * 0.45), 12.0, true)
	var pulse := 0.5 + 0.5 * sin(_time * 4.0)
	draw_arc(at, SPOT_RADIUS - 2.0, 0.0, TAU, 64, Color(PANEL_BORDER, alpha * (0.45 + 0.4 * pulse)), 2.0, true)

	var box := _panel_rect(at, MOVE_PANEL, SPOT_RADIUS + 10.0)
	_draw_panel(box, alpha)
	var font := ThemeDB.fallback_font
	draw_string(font, box.position + Vector2(0, 26), "MOVE YOUR BOAT", HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 18, Color(GOLD, alpha))
	# WASD cluster on the left, arrow keys on the right, "or" between them.
	var key := 24.0
	var gap := 4.0
	var left := box.position + Vector2(box.size.x * 0.27, 44)
	var right := box.position + Vector2(box.size.x * 0.73, 44)
	var bounce := Vector2(0, -2.0 * pulse)
	_draw_key(left + Vector2(-key * 0.5, 0) + bounce, key, "W", alpha)
	_draw_key(left + Vector2(-key * 1.5 - gap, key + gap), key, "A", alpha)
	_draw_key(left + Vector2(-key * 0.5, key + gap), key, "S", alpha)
	_draw_key(left + Vector2(key * 0.5 + gap, key + gap), key, "D", alpha)
	_draw_key(right + Vector2(-key * 0.5, 0) + bounce, key, "", alpha, -PI * 0.5)
	_draw_key(right + Vector2(-key * 1.5 - gap, key + gap), key, "", alpha, PI)
	_draw_key(right + Vector2(-key * 0.5, key + gap), key, "", alpha, PI * 0.5)
	_draw_key(right + Vector2(key * 0.5 + gap, key + gap), key, "", alpha, 0.0)
	draw_string(font, Vector2(box.position.x, left.y + key + 6), "or", HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 13, Color(MUTED, alpha))
	draw_string(font, box.position + Vector2(0, box.size.y - 12), "Use WASD or the arrow keys to steer.", HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 12, Color(MUTED, alpha))


func _draw_prompt(at: Vector2, alpha: float) -> void:
	var box := _panel_rect(at, PROMPT_PANEL, 30.0)
	_draw_panel(box, alpha)
	var key := 28.0
	var key_pos := box.position + Vector2(10, (box.size.y - key) * 0.5)
	var pulse := 0.5 + 0.5 * sin(_time * 5.0)
	_draw_key(key_pos, key, "E", alpha, NAN, Color(GOLD, alpha * (0.6 + 0.4 * pulse)))
	draw_string(ThemeDB.fallback_font, Vector2(key_pos.x + key + 10, box.position.y + box.size.y * 0.5 + 5), _shown_prompt,
		HORIZONTAL_ALIGNMENT_LEFT, box.size.x - key - 30, 14, Color(TEXT, alpha))


func _draw_panel(box: Rect2, alpha: float) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(PANEL_BG, PANEL_BG.a * alpha)
	style.border_color = Color(PANEL_BORDER, alpha * 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	draw_style_box(style, box)


## A key cap. With an arrow angle it draws an arrow instead of a letter (the bundled font has no
## arrow glyphs, so they are drawn as triangles).
func _draw_key(top_left: Vector2, key: float, letter: String, alpha: float, arrow_angle: float = NAN, border: Color = Color(0, 0, 0, 0)) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(KEY_BG, alpha)
	style.border_color = border if border.a > 0.0 else Color(KEY_BORDER, alpha * 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	style.border_width_bottom = 4
	draw_style_box(style, Rect2(top_left, Vector2(key, key)))
	var center := top_left + Vector2(key * 0.5, key * 0.5 - 1.0)
	if not is_nan(arrow_angle):
		var tri := PackedVector2Array([Vector2(6, 0), Vector2(-4, -5.5), Vector2(-4, 5.5)])
		var rotated := PackedVector2Array()
		for point in tri:
			rotated.append(center + point.rotated(arrow_angle))
		draw_colored_polygon(rotated, Color(TEXT, alpha))
	elif letter != "":
		draw_string(ThemeDB.fallback_font, Vector2(top_left.x, center.y + 5), letter, HORIZONTAL_ALIGNMENT_CENTER, key, 14, Color(TEXT, alpha))
