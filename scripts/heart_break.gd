class_name HeartBreak
extends Control
## Full-screen "a life is lost" moment: the screen dims, a big heart rises into the middle, cracks
## down the centre and its two halves fall apart. advance() is public so tests can step it by hand.

signal finished

const DIM := Color(0.02, 0.05, 0.09, 0.62)
const FILL := Color("f0727a")
const OUTLINE := Color("ffd0d3")
const CRACK := Color("0d1c29")
const TEXT_COLOR := Color("ffd0d3")
const HEART_SIZE := Vector2(150, 140)
const CENTER := Vector2(576, 300)

const RISE := 0.40 ## Heart grows in from small and slightly low.
const HOLD := 0.25
const CRACK_TIME := 0.25 ## The crack runs down the heart.
const SPLIT := 0.70 ## The halves drift apart, tilt and fade.
const DURATION := RISE + HOLD + CRACK_TIME + SPLIT

var elapsed: float = 0.0
var playing: bool = false
var caption: String = ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func play(text: String) -> void:
	caption = text
	elapsed = 0.0
	playing = true
	visible = true
	queue_redraw()


func is_playing() -> bool:
	return playing


func advance(delta: float) -> void:
	if not playing:
		return
	elapsed += delta
	if elapsed >= DURATION:
		finish()
		return
	queue_redraw()


## Ends at once (also used by tests). Emits finished exactly once per play().
func finish() -> void:
	if not playing:
		return
	playing = false
	visible = false
	elapsed = 0.0
	finished.emit()


func _draw() -> void:
	var fade_out := 1.0 - smoothstep(DURATION - 0.35, DURATION, elapsed)
	draw_rect(Rect2(Vector2.ZERO, Vector2(1152, 648)), Color(DIM, DIM.a * smoothstep(0.0, 0.2, elapsed) * fade_out))
	var rise := ease(clampf(elapsed / RISE, 0.0, 1.0), 0.35)
	var scale_now := lerpf(0.35, 1.0, rise) * (1.0 + 0.06 * sin(clampf((elapsed - RISE) / HOLD, 0.0, 1.0) * PI))
	var center := CENTER + Vector2(0, lerpf(60.0, 0.0, rise))
	var crack_t := clampf((elapsed - RISE - HOLD) / CRACK_TIME, 0.0, 1.0)
	var split_t := clampf((elapsed - RISE - HOLD - CRACK_TIME) / SPLIT, 0.0, 1.0)
	var shape := LifeHeart.heart_shape(HEART_SIZE * scale_now)
	var crack := _crack_line(HEART_SIZE * scale_now)
	if split_t <= 0.0:
		var alpha := rise
		draw_set_transform(center, 0.0, Vector2.ONE)
		draw_colored_polygon(shape, Color(FILL, alpha))
		draw_polyline(LifeHeart.closed(shape), Color(OUTLINE, alpha), 3.0, true)
		if crack_t > 0.0:
			var shown := int(ceil(crack_t * (crack.size() - 1))) + 1
			draw_polyline(crack.slice(0, shown), CRACK, 5.0, true)
	else:
		# Two halves, cut along the crack, drifting apart and dropping as they fade.
		var alpha := 1.0 - split_t
		var drift := ease(split_t, 1.8)
		for side in [-1.0, 1.0]:
			var half := _half(shape, crack, side)
			var offset := Vector2(side * 46.0 * drift, 80.0 * drift * drift)
			draw_set_transform(center + offset, side * 0.32 * drift, Vector2.ONE)
			for piece in half:
				draw_colored_polygon(piece, Color(FILL.darkened(0.15), alpha))
				draw_polyline(LifeHeart.closed(piece), Color(OUTLINE, alpha), 2.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if caption != "":
		draw_string(ThemeDB.fallback_font, Vector2(0, CENTER.y + 120), caption, HORIZONTAL_ALIGNMENT_CENTER, 1152, 26,
			Color(TEXT_COLOR, clampf(elapsed / RISE, 0.0, 1.0) * fade_out))


## A zig-zag from the top notch of the heart to its tip.
func _crack_line(heart_size: Vector2) -> PackedVector2Array:
	var unit := PackedVector2Array([
		Vector2(0.0, -0.27), Vector2(-0.08, -0.12), Vector2(0.07, 0.02),
		Vector2(-0.06, 0.18), Vector2(0.03, 0.32), Vector2(0.0, 0.52)])
	var line := PackedVector2Array()
	for point in unit:
		line.append(point * heart_size)
	return line


## The part of the heart on one side of the crack (side -1 is left, +1 is right).
func _half(shape: PackedVector2Array, crack: PackedVector2Array, side: float) -> Array[PackedVector2Array]:
	var cutter := crack.duplicate()
	var far := 2000.0 * side
	cutter.append(Vector2(far, crack[crack.size() - 1].y + 400.0))
	cutter.append(Vector2(far, crack[0].y - 400.0))
	cutter.insert(0, Vector2(0.0, crack[0].y - 400.0))
	return Geometry2D.intersect_polygons(shape, cutter)
