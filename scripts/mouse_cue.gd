class_name MouseCue
extends Node2D
## Level 1 hint: "MOVE YOUR MOUSE". A child of the lighthouse, drawn with native canvas calls only
## (no emoji, no font symbols), never takes input, and fades out by itself.

@export var visible_seconds: float = 3.0
## Pause between activation and the first fade-in, so the cue never competes with the GO! flash.
@export var start_delay: float = 0.0
@export var fade_in_seconds: float = 0.35
@export var fade_out_seconds: float = 0.7
## Where the cue sits relative to the lighthouse: above the island, clear of the harbor and the HUD.
@export var anchor_offset: Vector2 = Vector2(-40, -118)

const TEXT_COLOR := Color("ffda92")
const MUTED_COLOR := Color("b8cdd2")
const TEAL_COLOR := Color("7fe0cc")
const BOX_SIZE := Vector2(252, 108)
const TITLE := "MOVE YOUR MOUSE"
const SUBTITLE := "Aim the lighthouse beam to find the survivor."

var elapsed: float = 0.0
var playing: bool = false


func _ready() -> void:
	position = anchor_offset
	z_index = 12
	hide()
	set_process(false)


## Starts (or restarts) the three seconds. Called once per level start, after gameplay activates.
func play() -> void:
	elapsed = -start_delay
	playing = true
	modulate.a = 0.0
	show()
	set_process(true)
	queue_redraw()


func stop() -> void:
	playing = false
	elapsed = 0.0
	hide()
	set_process(false)


func _process(delta: float) -> void:
	if not playing:
		return
	elapsed += delta
	if elapsed >= visible_seconds:
		stop()
		return
	modulate.a = alpha()
	queue_redraw()


## The cue's panel in the node's own coordinates.
func box_rect() -> Rect2:
	return Rect2(-BOX_SIZE * 0.5, BOX_SIZE)


func is_playing() -> bool:
	return playing


## 0 → 1 over the fade-in, 1 while shown, then 1 → 0 so the last moments are a smooth fade.
func alpha() -> float:
	var rise := smoothstep(0.0, fade_in_seconds, maxf(elapsed, 0.0))
	var fall := 1.0 - smoothstep(visible_seconds - fade_out_seconds, visible_seconds, elapsed)
	return clampf(rise * fall, 0.0, 1.0)


func _draw() -> void:
	var box := box_rect()
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.05, 0.11, 0.16, 0.84)
	panel.border_color = Color("41616b")
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(10)
	draw_style_box(panel, box)
	# Mouse pictogram, swaying left and right between two arrows.
	var sway := sin(elapsed * 4.2) * 11.0
	var center := Vector2(sway, box.position.y + 34.0)
	var body := StyleBoxFlat.new()
	body.bg_color = Color(0.89, 0.93, 0.91, 0.12)
	body.border_color = TEXT_COLOR
	body.set_border_width_all(2)
	body.set_corner_radius_all(10)
	draw_style_box(body, Rect2(center + Vector2(-10, -15), Vector2(20, 30)))
	draw_line(center + Vector2(0, -15), center + Vector2(0, -3), TEXT_COLOR, 1.5, true)
	draw_line(center + Vector2(-10, -3), center + Vector2(10, -3), TEXT_COLOR, 1.5, true)
	draw_circle(center + Vector2(0, -9), 1.6, TEAL_COLOR)
	var pulse := 0.55 + 0.45 * sin(elapsed * 4.2 + PI * 0.5)
	for side in [-1.0, 1.0]:
		var tip := Vector2(side * 44.0, center.y)
		var color := Color(TEAL_COLOR, 0.35 + 0.65 * (pulse if side > 0.0 else 1.0 - pulse))
		draw_line(tip - Vector2(side * 22.0, 0), tip, color, 2.5, true)
		draw_line(tip, tip - Vector2(side * 8.0, -7.0), color, 2.5, true)
		draw_line(tip, tip - Vector2(side * 8.0, 7.0), color, 2.5, true)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(box.position.x, box.position.y + 72.0), TITLE,
		HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 20, TEXT_COLOR)
	draw_string(font, Vector2(box.position.x, box.position.y + 94.0), SUBTITLE,
		HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 11, MUTED_COLOR)
